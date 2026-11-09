local support = require('test.tls.stream.inet.helpers').new()
local testcase = require('testcase')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local assert = require('assert')
local error_is = require('error').is
local errno = require('errno')
local errno_eai = require('errno.eai')
local inet = require('net.stream.inet')
local get_server_config = support.get_server_config

local CLIENT_CONFIG

function testcase.before_all()
    CLIENT_CONFIG = select(2, support.before_all())
end

function testcase.after_all()
    support.after_all()
end

function testcase.after_each()
    support.after_each()
end

function testcase.server_new()
    local host = '127.0.0.1'
    -- test that create new net.stream.inet.Server
    local s, _, ai = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = get_server_config(),
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
        tlscfg = get_server_config(),
    })
    assert.not_nil(error_is(err, errno_eai.EAI_NONAME))
    _, err = inet.server.new(host, 'invalid servname', {
        tlscfg = get_server_config(),
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
        tlscfg = get_server_config(),
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
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
            verify_mode = 'request',
            cafile = get_server_config().cert,
            capath = '.',
            verify_depth = 2,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    -- the inherited accept also supports the sec deadline
    local tsock, terr, ttimeout = s:accept(nil, 0.05)
    assert.is_nil(tsock)
    assert.is_nil(terr)
    assert.is_true(ttimeout)

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

function testcase.client_new_bio_bufcap()
    -- tlscfg.bufcap must be forwarded to net.tls.context.connect/accept:
    -- the empty RX ring of a fresh memory-BIO context reports exactly the
    -- requested capacity on both the client and the accepted peer.
    local host = '127.0.0.1'
    local cap = 1048576
    local s = assert(inet.server.new(host, 0, {
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
            bufcap = cap,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c = assert(inet.client.new(host, port, {
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

function testcase.client_new_bio_bufcap_unallocatable()
    -- an unallocatable tlscfg.bufcap must fail client.new instead of being
    -- silently ignored and falling back to the minimum buffer size
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        tlscfg = get_server_config(),
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c, err = inet.client.new(host, port, {
        tlscfg = {
            verify_name = CLIENT_CONFIG.verify_name,
            verify_time = CLIENT_CONFIG.verify_time,
            verify_cert = CLIENT_CONFIG.verify_cert,
            bufcap = 4611686018427387904, -- 2^62
        },
    })
    assert.is_nil(c)
    assert(err, 'client.new must surface the bio allocation failure')

    s:close()
end

function testcase.tlscfg_bufcap_validation()
    -- tlscfg.bufcap must be nil or a non-negative integer
    local host = '127.0.0.1'
    assert.match(assert.throws(function()
        inet.client.new(host, 80, {
            tlscfg = {
                bufcap = 'hello',
            },
        })
    end), 'tlscfg.bufcap must be uint')

    assert.match(assert.throws(function()
        inet.server.new(host, 0, {
            tlscfg = {
                bufcap = -1,
            },
        })
    end), 'tlscfg.bufcap must be uint')
end

function testcase.client_new_verify_locations()
    -- tlscfg.cafile / capath / verify_depth are forwarded to the TLS
    -- client context.  The fixture certificate is self-signed, so it acts
    -- as its own CA and full verification succeeds when it is loaded
    -- explicitly.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = get_server_config(),
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                deadline = 1,
                servername = 'www.example.com',
                tlscfg = {
                    cafile = get_server_config().cert,
                    capath = '.',
                    verify_depth = 2,
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

    -- a non-existent CA file surfaces the constructor load error
    local c, err = inet.client.new(host, port, {
        tlscfg = {
            cafile = './no-such-ca.pem',
        },
    })
    assert.is_nil(c)
    assert.match(tostring(err), 'o such file', false)
    assert(s:close())

    -- type validation of the new keys
    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            tlscfg = {
                cafile = 42,
            },
        })
    end), 'tlscfg.cafile must be string')

    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            tlscfg = {
                capath = 42,
            },
        })
    end), 'tlscfg.capath must be string')

    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            tlscfg = {
                verify_depth = -1,
            },
        })
    end), 'tlscfg.verify_depth must be uint')
end
