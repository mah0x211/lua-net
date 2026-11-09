local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local socket = require('net.socket')
local sleep = require('testcase.timer').sleep
local tls_context = require('net.tls.context')
local tls_cache = require('net.tls.cache')
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')
local new_ep = context_helpers.new_ep
local make_loopback_pair = context_helpers.make_loopback_pair
local handshake = context_helpers.handshake
local transfer_read = context_helpers.transfer_read
local close_ep = context_helpers.close_ep
local handshake_pair = context_helpers.handshake_pair
local free_port = support.free_port
local start_ticket_s_server = support.start_ticket_s_server
local wait_listen = support.wait_listen
local get_server_config = support.get_server_config

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end
local function ticket_connect_opts(host, port, servername, verify_time)
    return {
        host = host,
        port = port,
        servername = servername,
        verify_name = false,
        verify_time = verify_time == nil or verify_time,
        verify_cert = false,
    }
end

local function connect_ticket_client(port, proc, client, opts, cache)
    local sock = assert(wait_listen(port))
    local ctx = assert(tls_context.connect(client, sock:fd(), opts))
    local before
    local ep = new_ep(ctx, 'client', sock:fd())

    if cache then
        before = select(2, cache:size())
    end
    assert(handshake(ep))
    assert(transfer_read(ep, proc, 'A'))
    local after
    if cache then
        after = select(2, cache:size())
    end
    assert(close_ep(ep))
    sock:close()
    return before, after
end

local function count_full_handshakes(proc)
    local count = 0

    for line in proc.stderr:lines() do
        if line:find('write certificate', 1, true) then
            count = count + 1
        end
    end
    assert.equal(assert(proc:close()).exit, 0)
    return count
end

local function assert_client_ticket_cache(protocol)
    local port = free_port()
    local proc = start_ticket_s_server(port, protocol)
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local opts = ticket_connect_opts('127.0.0.1', port)

    for _ = 1, 2 do
        local client = assert(tls_client({
            protocol = protocol,
            cache = cache,
        }))
        local before, after = connect_ticket_client(port, proc, client, opts,
                                                    cache)
        assert.equal(before, 0)
        assert.equal(after, 1)
    end
    assert.equal(count_full_handshakes(proc), 1)
end

function testcase.client_caches_tls12_ticket()
    assert_client_ticket_cache('tlsv1.2')
end

function testcase.client_caches_tls13_psk_ticket()
    assert_client_ticket_cache('tlsv1.3')
end

function testcase.client_ticket_cache_requires_capacity_and_destination()
    for _, case in ipairs({
        {
            connect_opts = ticket_connect_opts('127.0.0.1', 443),
        },
        {
            capacity = 0,
            connect_opts = ticket_connect_opts('127.0.0.1', 443),
        },
        {
            capacity = 1,
            connect_opts = ticket_connect_opts(),
        },
        {
            capacity = 1,
            connect_opts = ticket_connect_opts('127.0.0.1'),
        },
        {
            capacity = 1,
            connect_opts = ticket_connect_opts(nil, 443),
        },
    }) do
        for _, protocol in ipairs({
            'tlsv1.2',
            'tlsv1.3',
        }) do
            local port = free_port()
            local proc = start_ticket_s_server(port, protocol)
            local cache
            if case.capacity ~= nil then
                cache = tls_cache({
                    ctx_capacity = 1,
                    session_capacity = case.capacity,
                })
            end
            local client = assert(tls_client({
                protocol = protocol,
                cache = cache,
            }))

            connect_ticket_client(port, proc, client, case.connect_opts)
            connect_ticket_client(port, proc, client, case.connect_opts)
            if cache then
                assert.equal(select(2, cache:size()), 0)
            end
            assert.equal(count_full_handshakes(proc), 2)
        end
    end
end

function testcase.client_ticket_cache_separates_destination_and_policy()
    local base =
        ticket_connect_opts('server.example', 'https', 'server.example')
    local variants = {
        ticket_connect_opts('other.example', 'https', 'server.example'),
        ticket_connect_opts('server.example', '8443', 'server.example'),
        ticket_connect_opts('server.example', 'https', 'other.example'),
        ticket_connect_opts('server.example', 'https', 'server.example', false),
    }

    for _, variant in ipairs(variants) do
        local port = free_port()
        local proc = start_ticket_s_server(port, 'tlsv1.3')
        local cache = tls_cache({
            ctx_capacity = 1,
            session_capacity = 2,
        })
        local client = assert(tls_client({
            protocol = 'tlsv1.3',
            cache = cache,
        }))

        connect_ticket_client(port, proc, client, base)
        connect_ticket_client(port, proc, client, variant)
        local _, nsessions = cache:size()
        assert.equal(nsessions, 2)
        assert.equal(count_full_handshakes(proc), 2)
    end
end

function testcase.client_ticket_cache_ignores_tls12_session_ids()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.2', {
        '-no_ticket',
    })
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.2',
        cache = cache,
    }))
    local opts = ticket_connect_opts('127.0.0.1', port)

    connect_ticket_client(port, proc, client, opts)
    connect_ticket_client(port, proc, client, opts)
    local _, nsessions = cache:size()
    assert.equal(nsessions, 0)
    assert.equal(count_full_handshakes(proc), 2)
end

function testcase.client_ticket_cache_is_scoped_to_ssl_ctx()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.3')
    local cache = tls_cache({
        ctx_capacity = 2,
        session_capacity = 1,
    })
    local opts = ticket_connect_opts('127.0.0.1', port)
    local first = assert(tls_client({
        protocol = 'tlsv1.3',
        cache = cache,
    }))
    local second = assert(tls_client({
        protocol = 'tlsv1.3',
        alpn = {
            'h2',
        },
        cache = cache,
    }))

    connect_ticket_client(port, proc, first, opts)
    connect_ticket_client(port, proc, second, opts)
    local nctx, nsessions = cache:size()
    assert.equal(nctx, 2)
    assert.equal(nsessions, 2)
    assert.equal(count_full_handshakes(proc), 2)
end

function testcase.client_ticket_cache_clear_discards_session()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.3')
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.3',
        cache = cache,
    }))
    local opts = ticket_connect_opts('127.0.0.1', port)

    connect_ticket_client(port, proc, client, opts)
    assert.equal(select(2, cache:size()), 1)
    assert(cache:clear())
    assert.equal(select(2, cache:size()), 0)
    connect_ticket_client(port, proc, client, opts)
    assert.equal(count_full_handshakes(proc), 2)
end

function testcase.client_ticket_cache_survives_context_creation_failure()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.3')
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.3',
        cache = cache,
    }))
    local opts = ticket_connect_opts('127.0.0.1', port)

    connect_ticket_client(port, proc, client, opts)
    assert.equal(select(2, cache:size()), 1)

    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local failed_opts = ticket_connect_opts('127.0.0.1', port)
    failed_opts.bufcap = 2147483000
    local ctx, err = tls_context.connect(client, sp[1]:fd(), failed_opts)
    assert.is_nil(ctx)
    assert(err, 'connect must surface the bio_buf_init failure')
    sp[1]:close()
    sp[2]:close()

    assert.equal(select(2, cache:size()), 1)
    connect_ticket_client(port, proc, client, opts)
    assert.equal(count_full_handshakes(proc), 1)
end

function testcase.client_ticket_cache_retains_session_after_lua_error()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.3', {
        '-num_tickets',
        '1',
    })
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.3',
        cache = cache,
    }))
    local opts = ticket_connect_opts('127.0.0.1', port)
    local sock = assert(wait_listen(port))
    local ctx = assert(tls_context.connect(client, sock:fd(), opts))
    local ep = new_ep(ctx, 'client', sock:fd())

    assert(handshake(ep))
    assert.equal(select(2, cache:size()), 0)

    local registry = debug.getregistry()
    local mtname = 'net.tls.ssl_session'
    local session_mt = assert(registry[mtname])
    registry[mtname] = nil
    local ok = pcall(function()
        assert(transfer_read(ep, proc, 'A'))
    end)
    registry[mtname] = session_mt

    assert.is_true(ok)
    assert.equal(select(2, cache:size()), 0)

    -- A failed cache write must not interrupt TLS reads. Retry once the
    -- cache is available again, without waiting for another ticket.
    ctx:read(1)
    assert.equal(select(2, cache:size()), 1)
    assert(close_ep(ep))
    sock:close()

    connect_ticket_client(port, proc, client, opts)
    assert.equal(count_full_handshakes(proc), 1)
end

function testcase.client_ticket_cache_discards_expired_session()
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.2',
        cache = cache,
    }))
    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        protocol = 'tlsv1.2',
        session_timeout = 1,
    }))

    local function new_pair()
        local csock, ssock = make_loopback_pair()
        local cctx = assert(tls_context.connect(client, csock:fd(), {
            host = '127.0.0.1',
            port = 443,
            verify_name = false,
            verify_cert = false,
        }))
        local sctx = assert(tls_context.accept(server, ssock:fd()))
        return csock, ssock, cctx, sctx
    end

    local csock, ssock, cctx, sctx = new_pair()
    assert(handshake_pair(new_ep(cctx, 'client', csock:fd()),
                          new_ep(sctx, 'server', ssock:fd())))
    assert.equal(select(2, cache:size()), 1)
    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()

    sleep(2)
    csock, ssock, cctx, sctx = new_pair()
    assert.equal(select(2, cache:size()), 0)
    assert(handshake_pair(new_ep(cctx, 'client', csock:fd()),
                          new_ep(sctx, 'server', ssock:fd())))
    assert.equal(select(2, cache:size()), 1)
    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end
