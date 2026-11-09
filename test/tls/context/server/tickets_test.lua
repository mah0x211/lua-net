local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local socket = require('net.socket')
local wait = require('io.wait')
local sleep = require('testcase.timer').sleep
local tls_context = require('net.tls.context')
local tls_cache = require('net.tls.cache')
local tls_server = require('net.tls.server')
local DEADLINE = context_helpers.DEADLINE
local new_ep = context_helpers.new_ep
local handshake = context_helpers.handshake
local close_ep = context_helpers.close_ep
local exec = support.exec
local new_tls_server = support.new_tls_server
local get_server_config = support.get_server_config
local get_client_cert_fixture_dir = support.get_client_cert_fixture_dir
local TICKET_SESSION = support.TICKET_SESSION
local ticket_connection = support.ticket_connection

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end
local function count_resumed(lsock, server, port, nconns, no_ticket)
    local args = {
        's_client',
        '-connect',
        '127.0.0.1:' .. tostring(port),
        '-reconnect',
        '-noservername',
        '-tls1_2',
    }
    if no_ticket then
        args[#args + 1] = '-no_ticket'
    end
    local proc = assert(exec('openssl', args))

    for _ = 1, nconns do
        assert(wait.readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        -- keep the wrapper alive so its __gc does not close the fd during
        -- the handshake
        local asock = assert(socket.wrap(afd))
        local ctx = assert(tls_context.accept(server, afd))
        local ep = new_ep(ctx, 'server', afd)
        assert(handshake(ep))
        assert(close_ep(ep))
        asock:close()
    end

    -- "Q" terminates s_client's interactive loop, closing stdout and
    -- thus ending the iteration below
    assert(proc.stdin:write('Q\n'))
    local reused = 0
    for line in proc.stdout:lines() do
        if line:match('^Reused,') then
            reused = reused + 1
        end
    end
    proc:close()
    return reused
end

function testcase.new_server_session_tickets_disabled()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key, 'tlsv1.2'))
    assert.equal(count_resumed(lsock, server, port, 6), 5)
    assert.equal(count_resumed(lsock, server, port, 6, true), 0)

    server = assert(new_tls_server(get_server_config().cert,
                                   get_server_config().key, 'tlsv1.2',
                                   'default', nil, 0))
    assert.equal(count_resumed(lsock, server, port, 6), 0)

    server = assert(new_tls_server(get_server_config().cert,
                                   get_server_config().key, 'tlsv1.2',
                                   'default', nil, -1))
    assert.equal(count_resumed(lsock, server, port, 6), 0)

    lsock:close()
end

function testcase.new_server_resumes_tls12_and_tls13_tickets()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local session = TICKET_SESSION
    os.remove(session)

    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local server = assert(new_tls_server(get_server_config().cert,
                                             get_server_config().key))
        local reused, ticket = ticket_connection(lsock, server, protocol,
                                                 session)
        assert.is_false(reused)
        assert.is_true(ticket)
        reused, ticket = ticket_connection(lsock, server, protocol, session,
                                           true)
        assert.is_true(reused)
        assert.is_true(ticket)

        local other = assert(new_tls_server(get_server_config().cert,
                                            get_server_config().key))
        reused = ticket_connection(lsock, other, protocol, session, true)
        assert.is_false(reused)
    end
    os.remove(session)
    lsock:close()
end

function testcase.new_server_disables_tls13_tickets()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, timeout in ipairs({
        0,
        -1,
    }) do
        local server = assert(tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            session_timeout = timeout,
        }))
        os.remove(TICKET_SESSION)
        local reused, ticket = ticket_connection(lsock, server, '-tls1_3',
                                                 TICKET_SESSION)
        assert.is_false(reused)
        assert.is_false(ticket)
    end
    lsock:close()
end

function testcase.new_server_shares_ticket_keys_with_cached_context()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local cache = tls_cache({
            ctx_capacity = 1,
            session_capacity = 64,
        })
        local opts = {
            cert = get_server_config().cert,
            key = get_server_config().key,
            cache = cache,
        }
        local first = assert(tls_server(opts))
        local reused, ticket = ticket_connection(lsock, first, protocol,
                                                 TICKET_SESSION)
        assert.is_false(reused)
        assert.is_true(ticket)
        local second = assert(tls_server(opts))
        assert.is_true(ticket_connection(lsock, second, protocol,
                                         TICKET_SESSION, true))
        local nctx, nsessions = cache:size()
        assert.equal(nctx, 1)
        assert.equal(nsessions, 0)
        assert(cache:clear())
        local fresh = assert(tls_server(opts))
        assert.is_false(ticket_connection(lsock, fresh, protocol,
                                          TICKET_SESSION, true))
    end
    lsock:close()
end

function testcase.new_server_expired_tickets_fall_back_to_full_handshake()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local server = assert(tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            session_timeout = 1,
        }))
        local reused, ticket = ticket_connection(lsock, server, protocol,
                                                 TICKET_SESSION)
        assert.is_false(reused)
        assert.is_true(ticket)
        sleep(2)
        assert.is_false(ticket_connection(lsock, server, protocol,
                                          TICKET_SESSION, true))
    end
    lsock:close()
end

function testcase.new_server_resumes_tickets_with_client_certificate()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local client_opts = {
        cert = get_client_cert_fixture_dir() .. '/client.crt',
        key = get_client_cert_fixture_dir() .. '/client.key',
    }
    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local server = assert(tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            verify_mode = 'require',
            cafile = get_client_cert_fixture_dir() .. '/ca.crt',
        }))
        assert.is_false(ticket_connection(lsock, server, protocol,
                                          TICKET_SESSION, false, client_opts))
        assert.is_true(ticket_connection(lsock, server, protocol,
                                         TICKET_SESSION, true, client_opts))
    end
    lsock:close()
end
