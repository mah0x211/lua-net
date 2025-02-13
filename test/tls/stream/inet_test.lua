require('luacov')
local testcase = require('testcase')
local fork = require('testcase.fork')
local assert = require('assert')
local exec = require('exec').execvp
local errno = require('errno')
local errno_eai = require('errno.eai')
local net = require('net')
local inet = require('net.stream.inet')
local new_tls_server = require('net.tls.server')

local SERVER_CONFIG
local CLIENT_CONFIG
local TESTFILE

function testcase.before_all()
    local p = assert(exec('openssl', {
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-x509',
        '-days',
        '1',
        '-keyout',
        'cert.key',
        '-out',
        'cert.pem',
        '-subj',
        '/C=US/CN=www.example.com',
    }))

    for line in p.stderr:lines() do
        print(line)
    end

    local res = assert(p:close())
    if res.exit ~= 0 then
        error('failed to generate cert files')
    end

    TESTFILE = './' .. os.time() .. '.txt'

    SERVER_CONFIG = {
        cert = 'cert.pem',
        key = 'cert.key',
    }
    CLIENT_CONFIG = {
        noverify_name = true,
        noverify_time = true,
        noverify_cert = true,
    }
end

function testcase.after_all()
    os.remove(TESTFILE)
    os.remove('cert.pem')
    os.remove('cert.key')
end

function testcase.server_new()
    local host = '127.0.0.1'
    -- test that create new net.stream.inet.Server
    local s, _, ai = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert.match(tostring(s), '^net.tls.stream.inet.Server: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), net.AF_INET)
    assert.equal(s:socktype(), net.SOCK_STREAM)
    assert.equal(s:protocol(), net.IPPROTO_TCP)
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.greater(ai:port(), 0)
    assert(s:close())

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.server.new('invalid hostname', 0, {
        tlscfg = SERVER_CONFIG,
    })
    assert.equal(err.type, errno_eai.EAI_NONAME)
    _, err = inet.server.new(host, 'invalid servname', {
        tlscfg = SERVER_CONFIG,
    })
    assert(err.type == errno_eai.EAI_SERVICE or err.type == errno_eai.EAI_NONAME)

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.server.new(host, 0, {
            tlscfg = 'hello',
        })
    end), 'opts.tlscfg must be table')
end

function testcase.client_new()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    local sai = assert(s:getsockname())
    local port = assert(sai:port())

    -- NOTE: it returns a connection refused error on linux platform
    -- test that timedout
    -- local c, err, timeout, ai = inet.client.new(host, port, 100)
    -- assert.is_nil(c)
    -- assert.is_true(timeout)
    -- assert.is_nil(err)
    -- assert.is_nil(ai)

    -- test that return client
    assert(s:listen())
    local c, err, timeout, ai = assert(inet.client.new(host, port, {
        deadline = 0.1,
        tlscfg = CLIENT_CONFIG,
    }))
    assert(not err, err)
    assert.is_nil(timeout)
    assert.match(tostring(c), '^net.tls.stream.inet.Client: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(c:isnonblock(), 'c.nonblock is not false')
    assert.equal(c:family(), net.AF_INET)
    assert.equal(c:socktype(), net.SOCK_STREAM)
    assert.equal(c:protocol(), net.IPPROTO_TCP)
    assert(c:close())
    assert(s:close())

    -- test that returns error that refuse
    c, err, timeout = inet.client.new(host, port, {
        deadline = 0.1,
        tlscfg = CLIENT_CONFIG,
    })
    assert.is_nil(c)
    assert.equal(err.type, errno.ECONNREFUSED)
    assert.is_nil(timeout)

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            tlscfg = '',
        })
    end), 'opts.tlscfg must be table')

    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            deadline = 'foo',
            tlscfg = CLIENT_CONFIG,
        })
    end), 'deadline must be finite number', false)
end

function testcase.accept()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port, {
        tlscfg = CLIENT_CONFIG,
    }))

    -- test that accept connection as a net.stream.inet.Socket
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.write_read()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 8443, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    -- test that communicates with write and read
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = CLIENT_CONFIG,
        }))

        assert(c:write(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    local rcv = assert(peer:read())
    assert.equal(rcv, msg)
    peer:close()
    s:close()
end

function testcase.send_recv()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 8443, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    -- test that communicates with send and recv
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = CLIENT_CONFIG,
        }))

        assert(c:send(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)

    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.sendfile_recv()
    -- create large file
    local f = assert(io.open(TESTFILE, 'w+'))
    local tbl = {}
    math.randomseed(os.time())
    for _ = 1, 65 do
        local tok = tostring(math.random())
        tbl[#tbl + 1] = tok .. string.rep(' ', 1024 - #tok)
    end
    local msg = table.concat(tbl)
    assert(f:write(msg))
    assert(f:flush())
    local fsize = f:seek('end')

    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    -- test that communicates with sendfile and recv
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = CLIENT_CONFIG,
        }))

        -- sendfile
        local remain = fsize
        local offset = 0
        repeat
            local sent, err, timeout = c:sendfile(f, remain, offset)
            assert(not err, err)
            -- update next params
            offset = assert.less_or_equal(offset + sent, fsize)
            remain = assert.greater_or_equal(remain - sent, 0)
        until not timeout

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    local total = 0
    tbl = {}
    while total < fsize do
        local data = assert(peer:recv())
        total = total + #data
        assert.less_or_equal(total, fsize)
        tbl[#tbl + 1] = data
    end
    assert.equal(table.concat(tbl), msg)

    peer:close()
    s:close()
end

function testcase.sendmsg_recvmsg()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    -- test that sendmsg and recvmsg are not supported
    local len, err = c:sendmsg()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = c:recvmsg()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

    len, err = peer:sendmsg()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = peer:recvmsg()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.writev_readv()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    -- test that writev and readv are not supported
    local len, err = c:writev()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = c:readv()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

    len, err = peer:writev()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = peer:readv()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.server_set_sni_callback()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 8443, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'
    local ncall = 0

    -- test that communicates with SNI callback
    s:set_sni_callback(function(...)
        ncall = ncall + 1
        assert.equal({
            ...,
        }, {
            'foo',
            'bar',
            'baz',
            'www.example.com',
        })
        return assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    end, 'foo', 'bar', 'baz')

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            servername = 'www.example.com',
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:send(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)
    peer:close()
    assert(p:wait())
    assert.equal(ncall, 1)

    -- test that communicates without SNI callback
    s:set_sni_callback(nil)
    p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            servername = 'www.example.com',
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:send(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)
    rcv = assert(peer:recv())
    assert.equal(rcv, msg)
    peer:close()
    assert(p:wait())
    assert.equal(ncall, 1)

    -- test that throws an error that SNI callback is not function
    local err = assert.throws(s.set_sni_callback, s, 'hello')
    assert.match(err, 'function or nil expected')

    s:close()
end

