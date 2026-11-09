local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local socket = require('net.socket')
local wait = require('io.wait')
local tls_context = require('net.tls.context')
local tls_cache = require('net.tls.cache')
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')
local DEADLINE = context_helpers.DEADLINE
local new_ep = context_helpers.new_ep
local make_loopback_pair = context_helpers.make_loopback_pair
local handshake_pair = context_helpers.handshake_pair
local new_tls_server = support.new_tls_server
local new_tls_client = support.new_tls_client
local get_server_config = support.get_server_config
local ticket_connection = support.ticket_connection

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end
local function new_sni_protocol_pair(root_protocol, target_protocol,
                                     client_protocol)
    local csock, ssock = make_loopback_pair()
    local target = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key,
                                         target_protocol))
    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        protocol = root_protocol,
        sni_callback = function(name)
            assert.equal(name, 'www.example.com')
            return target
        end,
    }))
    local client = assert(new_tls_client(client_protocol))
    local cctx = assert(tls_context.connect(client, csock:fd(), {
        servername = 'www.example.com',
        verify_name = false,
        verify_cert = false,
    }))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    return new_ep(cctx, 'client', csock:fd(), csock),
           new_ep(sctx, 'server', ssock:fd(), ssock)
end

function testcase.server_callbacks_are_independent_with_cached_context()
    local cache = tls_cache({
        ctx_capacity = 2,
    })
    local calls = {}
    local without_callback = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        cache = cache,
    }))
    local first = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        cache = cache,
        sni_callback = function(name)
            calls[#calls + 1] = 'first:' .. name
            return nil
        end,
    }))
    local second = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        cache = cache,
        sni_callback = function(name)
            calls[#calls + 1] = 'second:' .. name
            return nil
        end,
    }))
    assert.equal(cache:size(), 1)

    local client = assert(new_tls_client())
    for _, server in ipairs({
        first,
        second,
        without_callback,
    }) do
        local csock, ssock = make_loopback_pair()
        local cctx = assert(tls_context.connect(client, csock:fd(), {
            servername = 'www.example.com',
            verify_name = false,
            verify_cert = false,
        }))
        local sctx = assert(tls_context.accept(server, ssock:fd()))
        collectgarbage('collect')
        assert(handshake_pair(new_ep(cctx, 'client', csock:fd()),
                              new_ep(sctx, 'server', ssock:fd())))
        assert(cctx:close())
        assert(sctx:close())
        csock:close()
        ssock:close()
    end
    assert.equal(calls, {
        'first:www.example.com',
        'second:www.example.com',
    })
end

function testcase.sni_switch_accepts_target_protocol()
    for _, case in ipairs({
        {
            root = 'tlsv1.2',
            target = 'tlsv1.3',
            version = 'TLSv1.3',
        },
        {
            root = 'tlsv1.3',
            target = 'tlsv1.2',
            version = 'TLSv1.2',
        },
    }) do
        local cep, sep = new_sni_protocol_pair(case.root, case.target,
                                               case.target)
        assert(handshake_pair(cep, sep))
        assert.equal(cep.ctx:get_version(), case.version)
        assert.equal(sep.ctx:get_version(), case.version)
        assert(cep.ctx:close())
        assert(sep.ctx:close())
        cep.sock:close()
        sep.sock:close()
    end
end

function testcase.sni_switch_clears_root_protocol_for_default_target()
    for _, case in ipairs({
        {
            root = 'tlsv1.2',
            client = 'tlsv1.3',
            version = 'TLSv1.3',
        },
        {
            root = 'tlsv1.3',
            client = 'tlsv1.2',
            version = 'TLSv1.2',
        },
    }) do
        local cep, sep =
            new_sni_protocol_pair(case.root, 'default', case.client)
        assert(handshake_pair(cep, sep))
        assert.equal(cep.ctx:get_version(), case.version)
        assert.equal(sep.ctx:get_version(), case.version)
        assert(cep.ctx:close())
        assert(sep.ctx:close())
        cep.sock:close()
        sep.sock:close()
    end
end

function testcase.sni_switch_rejects_protocol_outside_target_range()
    for _, case in ipairs({
        {
            target = 'tlsv1.3',
            client = 'tlsv1.2',
        },
        {
            target = 'tlsv1.2',
            client = 'tlsv1.3',
        },
    }) do
        local cep, sep = new_sni_protocol_pair('default', case.target,
                                               case.client)
        local err = assert.throws(handshake_pair, cep, sep)
        assert.match(err, 'unsupported protocol')
        assert(cep.ctx:close())
        assert(sep.ctx:close())
        cep.sock:close()
        sep.sock:close()
    end
end

function testcase.sni_callback_with_captured_arguments()
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local target = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local extra = {}
    for i = 1, 20 do
        extra[i] = i
    end
    local got
    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        sni_callback = function(name)
            got = {
                n = #extra + 1,
            }
            for i = 1, #extra do
                got[i] = extra[i]
            end
            got[#extra + 1] = name
            return target
        end,
    }))

    local cctx = assert(tls_context.connect(client, csock:fd(), {
        servername = 'www.example.com',
        verify_name = false,
        verify_cert = false,
    }))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))

    -- all 20 extra arguments plus the servername reach the callback intact
    assert(got, 'the sni callback must have run')
    assert.equal(got.n, 21)
    for i = 1, 20 do
        assert.equal(got[i], i)
    end
    assert.equal(got[21], 'www.example.com')

    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.cached_server_sni_callback_survives_clear_and_gc()
    local csock, ssock = make_loopback_pair()
    local cache = tls_cache({
        ctx_capacity = 1,
    })
    local seen
    local opts = {
        cert = get_server_config().cert,
        key = get_server_config().key,
        cache = cache,
        sni_callback = function(name)
            seen = name
        end,
    }
    local server
    do
        local first = assert(tls_server(opts))
        server = assert(tls_server(opts))
        assert.is_true(first ~= server)
        assert.equal(cache:size(), 1)
    end

    assert.is_true(cache:clear())
    collectgarbage('collect')

    local client = assert(tls_client({}))
    local cctx = assert(tls_context.connect(client, csock:fd(), {
        servername = 'www.example.com',
        verify_name = false,
        verify_cert = false,
    }))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))
    assert.equal(seen, 'www.example.com')

    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.new_server_skips_sni_callback_for_ip_literals()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local called = false
    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        sni_callback = function()
            called = true
        end,
    }))
    for _, name in ipairs({
        '127.0.0.1',
        '::1',
    }) do
        assert.is_false(ticket_connection(lsock, server, '-tls1_2', nil, false,
                                          {
            servername = name,
        }))
        assert.is_false(called)
    end
    lsock:close()
end

function testcase.new_server_acknowledges_sni_on_default_fallback()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, opts in ipairs({
        {
            cert = get_server_config().cert,
            key = get_server_config().key,
            sni_callback = function(name)
                assert.equal(name, 'unknown.example.com')
                return nil
            end,
        },
        {
            cert = get_server_config().cert,
            key = get_server_config().key,
        },
    }) do
        local server = assert(tls_server(opts))
        local reused, _, trace = ticket_connection(lsock, server, '-tls1_2',
                                                   nil, false, {
            servername = 'unknown.example.com',
        })
        assert.is_false(reused)
        local bytes = {}
        local hello = assert(trace:match('], ServerHello\n(.-)\n<<<'))
        for hex in hello:gmatch('%x%x') do
            bytes[#bytes + 1] = tonumber(hex, 16)
        end
        -- Skip the handshake header, version, random, session ID, cipher,
        -- compression method and extension-list length.
        local idx = 45 + bytes[39]
        local acknowledged = false
        while idx + 3 <= #bytes do
            local kind = bytes[idx] * 256 + bytes[idx + 1]
            local len = bytes[idx + 2] * 256 + bytes[idx + 3]
            if kind == 0 then
                assert.equal(len, 0)
                acknowledged = true
            end
            idx = idx + 4 + len
        end
        assert.is_true(acknowledged)
    end
    lsock:close()
end

function testcase.new_server_sni_callback_errors_abort_handshake()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, callback in ipairs({
        function()
            error('SNI selection failed')
        end,
        function()
            error({})
        end,
        function()
            error(42, 0)
        end,
        function()
            return false
        end,
    }) do
        local server = assert(tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            sni_callback = callback,
        }))
        local err = assert.throws(ticket_connection, lsock, server, '-tls1_3',
                                  nil, false, {
            servername = 'www.example.com',
        })
        assert.match(err, 'callback failed')
    end
    lsock:close()
end

function testcase.new_server_rejects_malformed_sni()
    local function u16(n)
        return string.char(math.floor(n / 256), n % 256)
    end
    local function client_hello(sni)
        local ext = '\0\0' .. u16(#sni) .. sni
        local body = '\3\3' .. string.rep('\0', 32) .. '\0\0\2\192\47\1\0' ..
                         u16(#ext) .. ext
        local hello = '\1\0' .. u16(#body) .. body
        return '\22\3\1' .. u16(#hello) .. hello
    end
    local called = false
    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        sni_callback = function()
            called = true
        end,
    }))
    for _, sni in ipairs({
        '', -- truncated list
        '\0\0\0\0\1A', -- wrong list length
        '\0\4\1\0\1A', -- unsupported name type
        '\0\4\0\0\2A', -- wrong name length
        '\0\3\0\0\0', -- empty hostname
        u16(259) .. '\0' .. u16(256) .. string.rep('A', 256),
        '\0\4\0\0\1\0', -- embedded NUL
    }) do
        local csock, ssock = make_loopback_pair()
        local ctx = assert(tls_context.accept(server, ssock:fd()))
        local record = client_hello(sni)
        assert.equal(csock:write(record), #record)
        assert(wait.readable(ssock:fd(), DEADLINE))
        assert.equal(ctx:get_bio():fill(), #record)
        local ok, err = ctx:handshake()
        assert.is_false(ok)
        assert.not_nil(err)
        assert.is_false(called)
        ctx:close()
        csock:close()
        ssock:close()
    end

    -- The same packet framing with well-formed SNI must reach selection;
    -- rejecting every packet before the callback is not a passing oracle.
    local name = 'www.example.com'
    local record = client_hello(u16(#name + 3) .. '\0' .. u16(#name) .. name)
    local csock, ssock = make_loopback_pair()
    local ctx = assert(tls_context.accept(server, ssock:fd()))
    assert.equal(csock:write(record), #record)
    assert(wait.readable(ssock:fd(), DEADLINE))
    assert.equal(ctx:get_bio():fill(), #record)
    ctx:handshake()
    ctx:close()
    csock:close()
    ssock:close()
    assert.is_true(called)
end
