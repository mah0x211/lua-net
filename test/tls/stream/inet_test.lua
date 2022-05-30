require('luacov')
require('nosigpipe')
local testcase = require('testcase')
local exec = require('exec').execvp
local errno = require('errno')
local errno_eai = require('errno.eai')
local config = require('net.tls.config')
local net = require('net')
local inet = require('net.stream.inet')

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

    local res = assert(p:waitpid())
    if res.exit ~= 0 then
        error('failed to generate cert files')
    end

    TESTFILE = './' .. os.time() .. '.txt'

    SERVER_CONFIG = config.new()
    assert(SERVER_CONFIG:set_keypair_file('cert.pem', 'cert.key'))
    CLIENT_CONFIG = config.new()
    CLIENT_CONFIG:insecure_noverifycert()
    CLIENT_CONFIG:insecure_noverifyname()
end

function testcase.after_all()
    os.remove(TESTFILE)
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
    assert(not s.nonblock, 'nonblocking mode')
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
            tlscfg = {},
        })
    end), '(libtls.config expected')
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
        deadline = 100,
        tlscfg = CLIENT_CONFIG,
    }))
    assert(not err, err)
    assert.is_nil(timeout)
    assert.match(tostring(c), '^net.tls.stream.inet.Client: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(not c.nonblock, 'c.nonblock is not false')
    assert.equal(c:family(), net.AF_INET)
    assert.equal(c:socktype(), net.SOCK_STREAM)
    assert.equal(c:protocol(), net.IPPROTO_TCP)
    assert(c:close())
    assert(s:close())

    -- test that returns error that refuse
    c, err, timeout = inet.client.new(host, port, {
        deadline = 100,
        tlscfg = CLIENT_CONFIG,
    })
    assert.is_nil(c)
    assert.equal(err.type, errno.ECONNREFUSED)
    assert.is_nil(timeout)

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            tlscfg = {},
        })
    end), '(libtls.config expected,')

    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            deadline = 'foo',
            tlscfg = CLIENT_CONFIG,
        })
    end), 'deadline must be uint', false)
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

local function do_handshake(s1, s2)
    -- NOTE: change to non-blocking mode for handshaking in the same process.
    -- handshake required before send and recv in the same process.
    local pair = {
        s1,
        s2,
    }
    s1.sock:nonblock(true)
    s2.sock:nonblock(true)
    for _ = 1, 5 do
        for _, s in ipairs(pair) do
            local ok, err, timeout = s:handshake()
            if ok then
                s1.sock:nonblock(false)
                s2.sock:nonblock(false)
                return true
            elseif err and not timeout then
                return false, err
            end
        end
    end

    return false, 'failed to handshake()'
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
    local c = assert(inet.client.new(host, port, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    -- handshake required before write and read in the same process.
    assert(do_handshake(c, peer))

    -- test that communicates with write and read
    local msg = 'hello'
    assert(c:write(msg))
    local rcv = assert(peer:read())
    assert.equal(rcv, msg)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
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
    local c = assert(inet.client.new(host, port, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    -- handshake required before send and recv in the same process.
    assert(do_handshake(c, peer))

    -- test that communicates with send and recv
    local msg = 'hello'
    assert(c:send(msg))
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.sendfile_recv()
    -- create large file
    local f = assert(io.open(TESTFILE, 'w+'))
    local tbl = {}
    math.randomseed(os.time())
    for _ = 1, 64 do
        local tok = tostring(math.random())
        tbl[#tbl + 1] = tok .. string.rep(' ', 1024 - #tok)
    end
    local msg = table.concat(tbl)
    assert(f:write(msg))
    assert(f:flush())

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

    -- handshake required before send and recv in the same process.
    assert(do_handshake(c, peer))

    -- test that communicates with sendfile and recv
    c.sock:nonblock(true)
    c:setclocklimit(0.005)
    local size = f:seek('end')
    local remain = size
    local offset = 0
    local total = 0
    tbl = {}
    repeat
        local sent, err, again = c:sendfile(f, remain, offset)
        assert(not err, err)

        -- update next params
        offset = assert.less_or_equal(offset + sent, size)
        remain = assert.greater_or_equal(remain - sent, 0)

        -- repeat until all sent data has been received
        repeat
            local data = assert(peer:recv())
            sent = assert.greater_or_equal(sent - #data, 0)
            total = total + #data
            tbl[#tbl + 1] = data
        until sent == 0
    until not again
    assert.equal(size, total)
    assert.equal(table.concat(tbl), msg)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
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

