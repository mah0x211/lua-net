local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local newstate = require('newstate')

local loopback_ifname = require('test.socket_helpers').loopback_ifname

function testcase.new_inet()
    -- new_inet(opts) creates a raw AF_INET socket with socket(AF_INET,
    -- opts.socktype, opts.protocol) followed by FD_CLOEXEC + O_NONBLOCK.
    -- The socket is not bound; the caller drives bind/connect via
    -- s:bind(ai) / s:connect(ai) afterwards.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'tcp')
    s:close()

    -- SOCK_DGRAM + IPPROTO_UDP is also accepted.
    s = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'dgram')
    assert.equal(s:protocol(), 'udp')
    s:close()

    -- opts.protocol defaults to 0 ("auto") when omitted.
    s = assert(socket.new_inet({
        socktype = 'stream',
    }))
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'auto')
    s:close()

    -- Unknown opts keys are silently ignored (delegated to check_options).
    s = assert(socket.new_inet({
        socktype = 'stream',
        not_a_recognized_socket_option = true,
    }))
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'auto')
    s:close()
end

function testcase.new_inet_missing_socktype()
    -- opts.socktype is required; omitting it surfaces a Lua error at the
    -- new_raw_socket_lua guard.
    local err = assert.throws(function()
        socket.new_inet({})
    end)
    assert.match(err, 'opts.socktype is required', false)

    err = assert.throws(function()
        socket.new_inet()
    end)
    assert.match(err, 'opts.socktype is required', false)
end

function testcase.new_inet_applies_combined_multicast_options()
    local ifname = assert(loopback_ifname())
    local s = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
        mcastloop = false,
        mcastttl = 4,
        mcastif = ifname,
    }))
    assert.is_false(s:mcastloop())
    assert.equal(s:mcastttl(), 4)
    assert.equal(s:mcastif(), ifname)
    s:close()
end

function testcase.new_inet6_applies_combined_multicast_options()
    local ifname = assert(loopback_ifname())
    local s = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
        mcastloop = false,
        mcastttl = 4,
        mcastif = ifname,
    }))
    assert.is_false(s:mcastloop())
    assert.equal(s:mcastttl(), 4)
    assert.equal(s:mcastif(), ifname)
    s:close()
end

function testcase.new_inet_and_inet6_keep_multicast_options_alive_during_gc()
    local ifname = assert(loopback_ifname())
    local L = assert(newstate.new())
    assert(L:loadstring([[
        local constructor, ifname = ...
        local socket = require('net.socket')
        local weak = setmetatable({}, {__mode = 'v'})
        local observed = false
        local options_alive = false
        local registry = debug.getregistry()
        local socket_mt = assert(registry['net.socket'])
        local registry_mt = getmetatable(registry)
        collectgarbage('collect')
        collectgarbage('stop')
        -- In this isolated state, intercept the constructor's real
        -- luaL_getmetatable lookup. Collect while its C frame is active,
        -- before new_socket applies the borrowed multicast option.
        registry['net.socket'] = nil
        setmetatable(registry, {
            __index = function(_, key)
                assert(key == 'net.socket', key)
                rawset(registry, key, socket_mt)
                collectgarbage('collect')
                observed = true
                options_alive = weak[1] ~= nil
                return socket_mt
            end,
        })
        local function arm(options)
            weak[1] = options
            return options
        end
        -- ifname stays rooted independently, so observing the options
        -- lifetime never requires dereferencing a collected string.
        local s, err = socket[constructor](arm({
            socktype = 'dgram',
            protocol = 'udp',
            mcastif = ifname,
        }))
        setmetatable(registry, registry_mt)
        local actual
        if s then
            actual = s:mcastif()
            s:close()
        end
        collectgarbage('restart')
        assert(s, tostring(err))
        return observed, options_alive, actual
    ]]))
    for _, constructor in ipairs({
        'new_inet',
        'new_inet6',
    }) do
        local ok, observed, options_alive, actual = L:run(constructor, ifname)
        assert(ok, observed)
        assert.is_true(observed)
        assert.is_true(options_alive)
        assert.equal(actual, ifname)
    end
end

function testcase.new_inet6()
    -- new_inet6(opts) creates an unbound AF_INET6 socket.
    local s = assert(socket.new_inet6({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(s:family(), 'inet6')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'tcp')
    s:close()

    s = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(s:family(), 'inet6')
    assert.equal(s:socktype(), 'dgram')
    assert.equal(s:protocol(), 'udp')
    s:close()
end

function testcase.new_inet6_missing_socktype()
    -- opts.socktype is required for new_inet6 as well.
    local err = assert.throws(function()
        socket.new_inet6({})
    end)
    assert.match(err, 'opts.socktype is required', false)
end

function testcase.new_unix()
    -- new_unix(opts) creates a raw AF_UNIX socket with socket(family,
    -- opts.socktype, opts.protocol) followed by FD_CLOEXEC + O_NONBLOCK.
    -- The socket is not bound; the caller drives bind/connect via
    -- s:bind(ai) / s:connect(ai) afterwards.
    local s = assert(socket.new_unix({
        socktype = 'stream',
    }))
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'auto')
    s:close()

    -- SOCK_DGRAM is also accepted; protocol defaults to 0.
    s = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'dgram')
    assert.equal(s:protocol(), 'auto')
    s:close()

    -- Empty / unknown opts keys are ignored (delegated to check_options).
    s = assert(socket.new_unix({
        socktype = 'stream',
        not_a_recognized_socket_option = true,
    }))
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'auto')
    s:close()
end

function testcase.new_unix_missing_socktype()
    -- opts.socktype is required; omitting it surfaces a Lua error at the
    -- new_raw_socket_lua guard.
    local err = assert.throws(function()
        socket.new_unix({})
    end)
    assert.match(err, 'opts.socktype is required', false)
end

function testcase.new_unix_bad_protocol()
    -- socket(AF_UNIX, SOCK_STREAM, IPPROTO_TCP) fails with EPROTONOSUPPORT,
    -- exercising new_socket's socket() == -1 branch which propagates the
    -- failure back to new_unix as (nil, err).
    local s, err = socket.new_unix({
        socktype = 'stream',
        protocol = 'tcp',
    })
    assert.is_nil(s)
    assert(err)
end

function testcase.pair_stream()
    -- pair creates a pair of connected unix stream sockets.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    assert.equal(#socks, 2)
    assert.equal(socks[1]:family(), 'unix')
    assert.equal(socks[2]:family(), 'unix')
    assert.equal(socks[1]:socktype(), 'stream')
    assert.equal(socks[2]:socktype(), 'stream')
    assert.equal(socks[1]:protocol(), 'auto')
    assert.equal(socks[2]:protocol(), 'auto')
    socks[1]:close()
    socks[2]:close()
end

function testcase.pair_dgram()
    -- pair creates a pair of connected unix dgram sockets.
    local socks = assert(socket.pair({
        socktype = 'dgram',
    }))
    assert.equal(#socks, 2)
    assert.equal(socks[1]:family(), 'unix')
    assert.equal(socks[2]:family(), 'unix')
    assert.equal(socks[1]:socktype(), 'dgram')
    assert.equal(socks[2]:socktype(), 'dgram')
    assert.equal(socks[1]:protocol(), 'auto')
    assert.equal(socks[2]:protocol(), 'auto')
    socks[1]:close()
    socks[2]:close()
end

function testcase.pair_opts()
    -- opts.socktype is required.
    local err = assert.throws(function()
        socket.pair({})
    end)
    assert.match(err, 'opts.socktype is required', false)

    -- opts.protocol / opts.socktype must be strings (check_socktype /
    -- check_protocol type-check branches).
    err = assert.throws(function()
        socket.pair({
            socktype = 'stream',
            protocol = 123,
        })
    end)
    assert.match(err, 'opts.protocol must be string')

    err = assert.throws(function()
        socket.pair({
            socktype = 123,
        })
    end)
    assert.match(err, 'opts.socktype must be string')

    -- Unknown symbolic values are rejected by check_socktype / check_protocol.
    err = assert.throws(function()
        socket.pair({
            socktype = 'invalid',
        })
    end)
    assert.match(err, 'not a recognized socket type')

    err = assert.throws(function()
        socket.pair({
            socktype = 'stream',
            protocol = 'invalid',
        })
    end)
    assert.match(err, 'not a recognized protocol')
end

function testcase.pair_socketpair_failure()
    -- socketpair(AF_UNIX, SOCK_DGRAM, IPPROTO_TCP) fails with
    -- EPROTONOSUPPORT, so pair_lua's socketpair() -1 branch is exercised.
    local s, err = socket.pair({
        socktype = 'dgram',
        protocol = 'tcp',
    })
    assert.is_nil(s)
    assert(err)
end
