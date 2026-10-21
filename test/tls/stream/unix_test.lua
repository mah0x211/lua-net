local testcase = require('testcase')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local offset_payload = require('test.offset_payload')
local assert = require('assert')
local error_is = require('error').is
local errno = require('errno')
local cert_fixtures = require('test.tls.cert_fixtures')
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local unix = require('net.stream.unix')

local SERVER_CONFIG
local CERT_DIR
local CLIENT_CONFIG
local TESTFILE
local PATHNAME

local TMPPATHS = {}

--- Tracked tmpname(): the path is removed by after_each even when a
--- test fails midway, so no unix socket or temp file is left behind.
--- @return string path
local function tmpname()
    local path = os.tmpname()
    TMPPATHS[#TMPPATHS + 1] = path
    return path
end

local function get_server_config()
    if not SERVER_CONFIG then
        if not CERT_DIR then
            CERT_DIR = os.tmpname()
            os.remove(CERT_DIR)
            assert(mkdir(CERT_DIR, '0700', true))
        end
        local config = {
            cert = CERT_DIR .. '/cert.pem',
            key = CERT_DIR .. '/cert.key',
        }
        cert_fixtures.server_certificate(config.cert, config.key)
        SERVER_CONFIG = config
    end
    return SERVER_CONFIG
end

function testcase.before_all()
    CLIENT_CONFIG = {
        verify_name = false,
        verify_time = false,
        verify_cert = false,
    }
end

function testcase.before_each()
    -- os.tmpname gives each testcase its own PATHNAME / TESTFILE so parallel
    -- runs never collide via a shared os.time() second.
    PATHNAME = tmpname()
    os.remove(PATHNAME)
    TESTFILE = tmpname()
    os.remove(TESTFILE)
end

function testcase.after_each()
    for i = #TMPPATHS, 1, -1 do
        os.remove(TMPPATHS[i])
        TMPPATHS[i] = nil
    end

    os.remove(PATHNAME)
    os.remove(TESTFILE)
end

function testcase.after_all()
    if CERT_DIR then
        assert(rmdir(CERT_DIR, true))
        CERT_DIR = nil
        SERVER_CONFIG = nil
    end
end

function testcase.server_new()
    -- test that create new instance of net.stream.unix.Server
    local s, _, ai = assert(unix.server.new(PATHNAME, get_server_config()))
    assert.match(tostring(s), '^net.tls.stream.unix.Server: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'auto')
    assert.equal(ai:addr(), PATHNAME)
    assert.equal(assert(s:getsockname()):addr(), PATHNAME)
    assert(s:close())

    -- test that returns an error that already in use
    local _, err = unix.server.new(PATHNAME, get_server_config())
    assert.not_nil(error_is(err, errno.EADDRINUSE))

    -- test that returns an error that name too long
    _, err = unix.server.new('./long-name-' .. string.rep('0', 500) .. '.sock',
                             get_server_config())
    assert.not_nil(error_is(err, errno.ENAMETOOLONG))

    -- test that throws an error
    err = assert.throws(function()
        unix.server.new(PATHNAME, 'hello')
    end)
    assert.match(err, 'tlscfg must be table')
end

function testcase.client_new()
    local s = assert(unix.server.new(PATHNAME, get_server_config()))
    assert(s:listen())

    -- test that create new instance of net.stream.unix.Client
    local c, err, timeout, ai = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.match(tostring(c), '^net.tls.stream.unix.Client: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(c:isnonblock(), 'nonblocking mode')
    assert.equal(c:family(), 'unix')
    assert.equal(c:socktype(), 'stream')
    assert.equal(c:protocol(), 'auto')
    assert.equal(ai:addr(), PATHNAME)
    assert.equal(assert(c:getpeername()):addr(), PATHNAME)
    assert(c:close())

    -- test that returns an error that name too long
    c, err = unix.client.new('./long-name-' .. string.rep('0', 500) .. '.sock',
                             {
        tlscfg = CLIENT_CONFIG,
    })
    assert.is_nil(c)
    assert.not_nil(error_is(err, errno.ENAMETOOLONG))

    -- test that returns an error that not found
    local missing = tmpname()
    os.remove(missing)
    c, err = unix.client.new(missing, {
        tlscfg = CLIENT_CONFIG,
    })
    assert.is_nil(c)
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
    local s = assert(unix.server.new(PATHNAME, get_server_config()))
    assert(s:listen())
    local msg = 'hello'

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(unix.client.new(PATHNAME, {
                deadline = 1,
                tlscfg = {
                    cafile = get_server_config().cert,
                    verify_depth = 2,
                    verify_name = false,
                },
            }))
            assert(c:write(msg))
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert.equal(assert(peer:read()), msg)
    assert(peer:close())
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)

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
    local s = assert(unix.server.new(PATHNAME, get_server_config()))
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
    local s = assert(unix.server.new(PATHNAME, get_server_config()))
    assert(s:listen())
    local msg = 'hello ' .. os.time()

    -- test that communicates with write and read
    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(unix.client.new(PATHNAME, {
                tlscfg = CLIENT_CONFIG,
            }))
            assert.not_nil(c.tls_bio)
            assert(c:write(msg))

            -- wait for peer to close
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)
    assert.not_nil(peer.tls_bio)
    local rcv = assert(peer:read())
    assert.equal(rcv, msg)
    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.send_recv()
    local s = assert(unix.server.new(PATHNAME, get_server_config()))
    assert(s:listen())
    local msg = 'hello ' .. os.time()

    -- test that communicates with send and recv
    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(unix.client.new(PATHNAME, {
                tlscfg = CLIENT_CONFIG,
            }))
            assert(c:send(msg))

            -- wait for peer to close
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)
    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendfile_recv()
    -- create large file
    local f = assert(io.open(TESTFILE, 'w+'))
    local msg = offset_payload(64 * 1024)
    assert(f:write(msg))
    assert(f:flush())
    local fsize = f:seek('end')

    local s = assert(unix.server.new(PATHNAME, get_server_config()))
    assert(s:listen())

    -- test that communicates with sendfile and recv
    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(unix.client.new(PATHNAME, {
                tlscfg = CLIENT_CONFIG,
            }))
            local remain = fsize
            local offset = 0

            repeat
                local sent, err, timeout = c:sendfile(f, remain, offset)
                assert.is_nil(err)
                -- update next params
                offset = assert.less_or_equal(offset + sent, fsize)
                remain = assert.greater_or_equal(remain - sent, 0)
            until not timeout
            assert.equal(remain, 0)

            -- wait for peer to close
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    local total = 0
    local tbl = {}
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
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendmsg_recvmsg()
    local s = assert(unix.server.new(PATHNAME, get_server_config()))
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

function testcase.sendfd_recvfd()
    local s = assert(unix.server.new(PATHNAME, get_server_config()))
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
        cert = get_server_config().cert,
        key = get_server_config().key,
        bufcap = cap,
    }))
    assert(s:listen())

    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = {
            verify_name = CLIENT_CONFIG.verify_name,
            verify_time = CLIENT_CONFIG.verify_time,
            verify_cert = CLIENT_CONFIG.verify_cert,
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

function testcase.client_new_servername()
    -- opts.servername must be validated like the inet client does; AF_UNIX
    -- has no peer name, so name verification requires an explicit servername
    -- (or verify_name = false).
    assert.match(assert.throws(function()
        unix.client.new(PATHNAME, {
            servername = 42,
            tlscfg = CLIENT_CONFIG,
        })
    end), 'opts.servername must be string')

    -- a reachable server is required to reach the tls_connect check;
    -- without a servername the verification cannot proceed
    local s = assert(unix.server.new(PATHNAME, get_server_config()))
    assert(s:listen())
    local c, err = unix.client.new(PATHNAME, {
        tlscfg = {
            protocol = 'default',
        },
    })
    assert.is_nil(c)
    assert.match(tostring(err), 'servername is required', false)
    assert(s:close())
end
