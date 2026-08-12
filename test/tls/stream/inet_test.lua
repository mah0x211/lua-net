require('luacov')
local testcase = require('testcase')
local fork = require('testcase.fork')
local assert = require('assert')
local exec = require('exec').execvp
local error_is = require('error').is
local errno = require('errno')
local errno_eai = require('errno.eai')
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

    TESTFILE = os.tmpname()
    os.remove(TESTFILE)

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
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'tcp')
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.greater(ai:port(), 0)
    assert(s:close())

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.server.new('invalid hostname', 0, {
        tlscfg = SERVER_CONFIG,
    })
    assert.not_nil(error_is(err, errno_eai.EAI_NONAME))
    _, err = inet.server.new(host, 'invalid servname', {
        tlscfg = SERVER_CONFIG,
    })
    assert(error_is(err, errno_eai.EAI_SERVICE) or
               error_is(err, errno_eai.EAI_NONAME))

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

    -- test that return client
    assert(s:listen())
    local c, err, timeout, ai = assert(inet.client.new(host, port, {
        deadline = 0.1,
        tlscfg = CLIENT_CONFIG,
    }))
    assert(not err, err)
    assert.is_nil(timeout)
    assert.match(tostring(c), '^net.tls.stream.inet.Client: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(c:isnonblock(), 'c.nonblock is not false')
    assert.equal(c:family(), 'inet')
    assert.equal(c:socktype(), 'stream')
    assert.equal(c:protocol(), 'tcp')
    assert(c:close())
    assert(s:close())

    -- test that returns error that refuse
    c, err, timeout = inet.client.new(host, port, {
        deadline = 0.1,
        tlscfg = CLIENT_CONFIG,
    })
    assert.is_nil(c)
    assert.not_nil(error_is(err, errno.ECONNREFUSED))
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

    -- test that the stream layer wraps an accepted TLS connection as a
    -- net.tls.stream.inet.Socket
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.write_read()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
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
    assert(p:wait())
end

function testcase.send_recv()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
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
    f:close()
    assert(p:wait())
end

function testcase.sendfile_recv_with_offset_nil_bytes()
    -- Regression: sendfile(f, nil, offset>0) must transfer only the bytes
    -- from `offset` to end-of-file.  A previous implementation used
    -- stat.size directly and drove pread past EOF for offset > 0.
    local f = assert(io.open(TESTFILE, 'w+'))
    local msg = 'hello world - sendfile offset nil bytes regression'
    assert(f:write(msg))
    assert(f:flush())
    local offset = 6 -- skip "hello "
    local expected = msg:sub(offset + 1)

    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:sendfile(f, nil, offset))
        -- wait for peer to close before shutting down TLS
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    local total = 0
    local chunks = {}
    while total < #expected do
        local data = assert(peer:recv())
        total = total + #data
        chunks[#chunks + 1] = data
    end
    assert.equal(total, #expected)
    assert.equal(table.concat(chunks), expected)

    peer:close()
    s:close()
    f:close()
    assert(p:wait())
end

function testcase.sendfile_stops_at_eof()
    -- Regression: sendfile(f, bytes, offset) with bytes larger than the
    -- remaining file must not spin on pread returning the empty string.
    -- The wrapper stops at EOF and reports what it managed to transfer.
    local f = assert(io.open(TESTFILE, 'w+'))
    local msg = 'short'
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

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = CLIENT_CONFIG,
        }))
        -- Request many more bytes than the file actually has.
        local n = assert(c:sendfile(f, 4096, 0))
        assert(n <= #msg,
               'sendfile must not report more bytes than the file holds')
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    local total = 0
    local chunks = {}
    while total < #msg do
        local data = assert(peer:recv())
        total = total + #data
        chunks[#chunks + 1] = data
    end
    assert.equal(table.concat(chunks), msg)

    peer:close()
    s:close()
    f:close()
    assert(p:wait())
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
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = c:recvmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    len, err = peer:sendmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = peer:recvmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

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
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = c:readv()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    len, err = peer:writev()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = peer:readv()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.server_set_sni_callback()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
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

function testcase.write_read_bio()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    -- test that communicates with write and read in BIO mode
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        -- verify BIO is active on the client side
        assert(c.tls_bio ~= nil, 'BIO not set on client')
        assert(c:write(msg))
        -- wait for peer to close
        c:read()
        c:close()
        return
    end
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)
    -- verify BIO is active on the server side
    assert(peer.tls_bio ~= nil, 'BIO not set on server peer')

    local rcv = assert(peer:read())
    assert.equal(rcv, msg)
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.write_read_bio_large_payload()
    -- SSL_MODE_ENABLE_PARTIAL_WRITE is enabled on the client SSL_CTX, so a
    -- plaintext payload larger than a single TLS record is delivered in
    -- multiple SSL_write returns.  The client-side write wrapper must loop
    -- on the "partial" indication until every byte reaches the peer.  A
    -- 32 KiB payload spans two records and reliably exercises the partial
    -- path without exhausting the SO_SNDBUF / SO_RCVBUF of the loopback
    -- socket pair.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = string.rep('X', 32 * 1024)

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        assert(c.tls_bio ~= nil, 'BIO not set on client')
        assert(c:write(msg))
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on server peer')

    local buf = {}
    local total = 0
    while total < #msg do
        local chunk = peer:read()
        if not chunk then
            break
        end
        buf[#buf + 1] = chunk
        total = total + #chunk
    end
    peer:close()
    s:close()
    assert(p:wait())
    assert.equal(total, #msg)
    assert.equal(table.concat(buf), msg)
end
