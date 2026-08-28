require('luacov')
local testcase = require('testcase')
local fork = require('testcase.fork')
local assert = require('assert')
local error_is = require('error').is
local errno = require('errno')
local exec = require('exec').execvp
local unix = require('net.stream.unix')

local SERVER_CONFIG
local CLIENT_CONFIG
local TESTFILE
local PATHNAME

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

function testcase.before_each()
    -- os.tmpname gives each testcase its own PATHNAME / TESTFILE so parallel
    -- runs never collide via a shared os.time() second.
    PATHNAME = os.tmpname()
    os.remove(PATHNAME)
    TESTFILE = os.tmpname()
    os.remove(TESTFILE)
end

function testcase.after_each()
    os.remove(PATHNAME)
    os.remove(TESTFILE)
end

function testcase.after_all()
    os.remove('cert.pem')
    os.remove('cert.key')
end

function testcase.server_new()
    -- test that create new instance of net.stream.unix.Server
    local s, _, ai = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert.match(tostring(s), '^net.tls.stream.unix.Server: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'auto')
    assert(s:close())

    -- test that returns an error that already in use
    local _, err = unix.server.new(PATHNAME, SERVER_CONFIG)
    assert.not_nil(error_is(err, errno.EADDRINUSE))

    -- test that returns an error that name too long
    _, err = unix.server.new('./long-name-' .. string.rep('0', 500) .. '.sock',
                             SERVER_CONFIG)
    assert.not_nil(error_is(err, errno.ENAMETOOLONG))

    -- test that throws an error
    err = assert.throws(function()
        unix.server.new(PATHNAME, 'hello')
    end)
    assert.match(err, 'tlscfg must be table')
end

function testcase.client_new()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())

    -- test that create new instance of net.stream.unix.Client
    local c, _, _, ai = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    assert.match(tostring(c), '^net.tls.stream.unix.Client: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(c:isnonblock(), 'nonblocking mode')
    assert.equal(c:family(), 'unix')
    assert.equal(c:socktype(), 'stream')
    assert.equal(c:protocol(), 'auto')
    assert(c:close())

    -- test that returns an error that name too long
    local _, err = unix.client.new('./long-name-' .. string.rep('0', 500) ..
                                       '.sock', {
        tlscfg = CLIENT_CONFIG,
    })
    assert.not_nil(error_is(err, errno.ENAMETOOLONG))

    -- test that returns an error that not found
    _, err = unix.client.new('./unknown-socket', {
        tlscfg = CLIENT_CONFIG,
    })
    assert.not_nil(error_is(err, errno.ENOENT))
    assert(s:close())

    -- test that throws an error
    err = assert.throws(function()
        unix.client.new(PATHNAME, 'hello')
    end)
    assert.match(err, 'opts must be table')
end

function testcase.client_new_verify_locations()
    -- tlscfg.cafile / capath / verify_depth are forwarded to the TLS
    -- client context.  The fixture certificate is self-signed, so it acts
    -- as its own CA and chain verification succeeds when it is loaded
    -- explicitly.  AF_UNIX has no server name, so the name check stays
    -- disabled.
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local msg = 'hello'

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(unix.client.new(PATHNAME, {
            deadline = 1,
            tlscfg = {
                cafile = 'cert.pem',
                verify_depth = 2,
                noverify_name = true,
            },
        }))
        assert(c:write(msg))
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert.equal(assert(peer:read()), msg)
    assert(peer:close())
    assert(p:wait())

    -- a non-existent CA file surfaces the load_verify_locations error
    local c, err = unix.client.new(PATHNAME, {
        tlscfg = {
            cafile = './no-such-ca.pem',
        },
    })
    assert.is_nil(c)
    assert.match(tostring(err), 'o such file', false)
    assert(s:close())

    -- type validation of the new keys
    assert.match(assert.throws(function()
        unix.client.new(PATHNAME, {
            tlscfg = {
                cafile = 42,
            },
        })
    end), 'tlscfg.cafile must be string')

    assert.match(assert.throws(function()
        unix.client.new(PATHNAME, {
            tlscfg = {
                capath = 42,
            },
        })
    end), 'tlscfg.capath must be string')

    assert.match(assert.throws(function()
        unix.client.new(PATHNAME, {
            tlscfg = {
                verify_depth = -1,
            },
        })
    end), 'tlscfg.verify_depth must be uint')
end

function testcase.accept()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))

    -- test that accept connection as a net.stream.unix.Socket
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.write_read()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local msg = 'hello ' .. os.time()

    -- test that communicates with write and read
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(unix.client.new(PATHNAME, {
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:write(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    local rcv = assert(peer:read())
    assert.equal(rcv, msg)
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.send_recv()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local msg = 'hello ' .. os.time()

    -- test that communicates with send and recv
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(unix.client.new(PATHNAME, {
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:send(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
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
    for _ = 1, 64 do
        local tok = tostring(math.random())
        tbl[#tbl + 1] = tok .. string.rep(' ', 1024 - #tok)
    end
    local msg = table.concat(tbl)
    assert(f:write(msg))
    assert(f:flush())
    local fsize = f:seek('end')

    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())

    -- test that communicates with sendfile and recv
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(unix.client.new(PATHNAME, {
            tlscfg = CLIENT_CONFIG,
        }))
        local remain = fsize
        local offset = 0

        repeat
            local sent, err, timeout = c:sendfile(f, remain, offset, 1024 * 8)
            if err and not timeout then
                error(err)
            end
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
    local total = 0
    tbl = {}
    -- repeat until all sent data has been received
    while total < fsize do
        local data = assert(peer:recv())
        total = total + #data
        tbl[#tbl + 1] = data
    end
    assert.equal(total, fsize)
    assert.equal(table.concat(tbl), msg)

    peer:close()
    s:close()
    f:close()
    assert(p:wait())
end

function testcase.sendmsg_recvmsg()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)

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
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)

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

function testcase.sendfd_recvfd()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)

    -- test that sendfd and recvfd are not supported
    local len, err = c:sendfd()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = c:recvfd()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    len, err = peer:sendfd()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = peer:recvfd()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.client_new_bio_bufcap()
    -- tlscfg.bufcap must be forwarded to net.tls.context.connect/accept on
    -- unix sockets as well: the empty RX ring of a fresh memory-BIO context
    -- reports exactly the requested capacity.
    local cap = 1048576
    local s = assert(unix.server.new(PATHNAME, {
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        use_bio = true,
        bufcap = cap,
    }))
    assert(s:listen())

    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = {
            noverify_name = CLIENT_CONFIG.noverify_name,
            noverify_time = CLIENT_CONFIG.noverify_time,
            noverify_cert = CLIENT_CONFIG.noverify_cert,
            use_bio = true,
            bufcap = cap,
        },
    }))
    assert(c.tls_bio ~= nil, 'BIO not set on client')
    local _, space_len = c.tls_bio:space()
    assert.equal(space_len, cap)

    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')
    _, space_len = peer.tls_bio:space()
    assert.equal(space_len, cap)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.tlscfg_bufcap_validation()
    -- tlscfg.bufcap must be nil or a non-negative integer
    assert.match(assert.throws(function()
        unix.client.new(PATHNAME, {
            tlscfg = {
                bufcap = 'hello',
            },
        })
    end), 'tlscfg.bufcap must be uint')

    assert.match(assert.throws(function()
        unix.server.new(PATHNAME, {
            bufcap = -1,
        })
    end), 'tlscfg.bufcap must be uint')
end

function testcase.write_read_bio()
    local s = assert(unix.server.new(PATHNAME, {
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        use_bio = true,
    }))
    assert(s:listen())
    local msg = 'hello'

    -- test that communicates with write and read in BIO mode
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(unix.client.new(PATHNAME, {
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
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)
    -- verify BIO is active on the server side
    assert(peer.tls_bio ~= nil, 'BIO not set on server peer')

    local rcv = assert(peer:read())
    assert.equal(rcv, msg)
    peer:close()
    s:close()
    assert(p:wait())
end
