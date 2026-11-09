local support = require('test.tls.stream.inet.helpers').new()
local testcase = require('testcase')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local assert = require('assert')
local inet = require('net.stream.inet')
local new_tls_server = support.new_tls_server
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

function testcase.server_sni_callback()
    local host = '127.0.0.1'
    local msg = 'hello'
    local ncall = 0
    local extra = {
        'foo',
        'bar',
        'baz',
    }
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
            sni_callback = function(name)
                ncall = ncall + 1
                assert.equal(name, 'www.example.com')
                assert.equal(extra, {
                    'foo',
                    'bar',
                    'baz',
                })
                return assert(new_tls_server(get_server_config().cert,
                                             get_server_config().key))
            end,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                servername = 'www.example.com',
                tlscfg = CLIENT_CONFIG,
            }))
            assert(c:send(msg))

            -- wait for peer to close
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)
    peer:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
    assert.equal(ncall, 1)
    s:close()

    local err = assert.throws(function()
        inet.server.new(host, 0, {
            tlscfg = {
                cert = get_server_config().cert,
                key = get_server_config().key,
                sni_callback = 'hello',
            },
        })
    end)
    assert.match(err, 'opts.sni_callback must be function', false)
end

function testcase.server_sni_selects_alpn_of_target_server()
    -- SNI selects ALPN from the returned server. The connection must keep
    -- that server alive until close, without another application owner.
    local host = '127.0.0.1'
    local weak = setmetatable({}, {
        __mode = 'v',
    })
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
            sni_callback = function()
                local target = assert(new_tls_server(get_server_config().cert,
                                                     get_server_config().key,
                                                     nil, nil, {
                    'h2',
                    'http/1.1',
                }))
                weak.server = target
                return target
            end,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                servername = 'www.example.com',
                tlscfg = {
                    verify_name = CLIENT_CONFIG.verify_name,
                    verify_time = CLIENT_CONFIG.verify_time,
                    verify_cert = CLIENT_CONFIG.verify_cert,
                    alpn = {
                        'h2',
                    },
                },
            }))
            assert(c:send('hello'))
            assert.equal(c:get_alpn(), 'h2')
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert(peer:handshake())
    assert.not_nil(weak.server)
    -- The callback has returned; only the connection should own its target.
    collectgarbage('collect')
    collectgarbage('collect')
    assert.not_nil(weak.server)
    assert.equal(peer:get_alpn(), 'h2')
    assert.equal(peer:recv(), 'hello')
    assert(peer:close())
    collectgarbage('collect')
    collectgarbage('collect')
    assert.is_nil(weak.server)
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.server_sni_callback_raises_non_string_error()
    -- A Lua error raised through the SNI callback reaches the C callback
    -- handler as a value of any type. The handshake must report the
    -- callback error as a fatal alert without terminating either process.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
            sni_callback = function()
                error({
                    code = 42,
                })
            end,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                servername = 'www.example.com',
                tlscfg = CLIENT_CONFIG,
            }))
            -- TLS negotiation is deferred until handshake or I/O.
            local ok, err = c:handshake()
            assert.is_false(ok)
            assert.match(err, 'alert internal error')
            c:close()
        end)
    end

    local peer = s:accept()
    assert(peer, 'server must accept the connection')
    local msg, rerr = peer:read()
    assert.is_nil(msg)
    assert(rerr, 'read must surface the handshake failure')
    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sni_callback_runs_on_handshake_coroutine()
    -- The SNI callback must execute on the lua_State driving SSL_accept.
    -- Running the accepted peer's handshake from a coroutine leaves the
    -- state that created the server object suspended, so a stale
    -- tls_server_t.L would drive the Lua callback on a suspended state.
    local host = '127.0.0.1'
    local msg = 'hello'
    local ncall = 0
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
            sni_callback = function(name)
                ncall = ncall + 1
                assert.equal(name, 'www.example.com')
                return assert(new_tls_server(get_server_config().cert,
                                             get_server_config().key))
            end,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                servername = 'www.example.com',
                tlscfg = CLIENT_CONFIG,
            }))
            assert(c:send(msg))
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    -- drive the handshake and the data transfer from a coroutine
    coroutine.wrap(function()
        assert.equal(peer:recv(), msg)
    end)()
    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
    assert.equal(ncall, 1)
end
