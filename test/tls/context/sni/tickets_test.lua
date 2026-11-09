local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local assert = require('assert')
local socket = require('net.socket')
local sleep = require('testcase.timer').sleep
local tls_cache = require('net.tls.cache')
local tls_server = require('net.tls.server')
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

function testcase.new_server_sni_does_not_reuse_root_verification_policy()
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
        local target = assert(tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            verify_mode = 'require',
            cafile = get_client_cert_fixture_dir() .. '/ca.crt',
        }))
        local root = assert(tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            sni_callback = function()
                return target
            end,
        }))
        assert.is_false(ticket_connection(lsock, root, protocol, TICKET_SESSION))
        local err = assert.throws(ticket_connection, lsock, root, protocol,
                                  TICKET_SESSION, true, {
            servername = 'www.example.com',
        })
        assert.match(err, 'certificate')
    end
    lsock:close()
end

function testcase.new_server_resumes_tickets_for_selected_sni_server()
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
        local first = assert(new_tls_server(get_server_config().cert,
                                            get_server_config().key))
        local second = assert(new_tls_server(get_server_config().cert,
                                             get_server_config().key))
        local names = {}
        local root = assert(tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            sni_callback = function(name)
                names[#names + 1] = name
                if name == 'www.example.com' then
                    return first
                elseif name == 'other.example.com' then
                    return second
                end
            end,
        }))
        local opts = {
            servername = 'www.example.com',
        }
        assert.is_false(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                          false, opts))
        assert.is_true(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                         true, opts))
        opts.servername = 'other.example.com'
        assert.is_false(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                          true, opts))
        opts.servername = 'unknown.example.com'
        assert.is_false(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                          false, opts))
        assert.is_true(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                         true, opts))
        assert.equal(names, {
            'www.example.com',
            'www.example.com',
            'other.example.com',
            'unknown.example.com',
            'unknown.example.com',
        })
    end
    lsock:close()
end

function testcase.new_server_sni_applies_ticket_configuration()
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
        for _, cache in ipairs({
            false,
            tls_cache({
                ctx_capacity = 8,
            }),
        }) do
            for _, conf in ipairs({
                {
                    300,
                    0,
                    false,
                },
                {
                    0,
                    300,
                    true,
                },
                {
                    300,
                    -1,
                    false,
                },
                {
                    -1,
                    300,
                    true,
                },
            }) do
                local target = assert(tls_server({
                    cert = get_server_config().cert,
                    key = get_server_config().key,
                    session_timeout = conf[2],
                    cache = cache or nil,
                }))
                local root = assert(tls_server({
                    cert = get_server_config().cert,
                    key = get_server_config().key,
                    session_timeout = conf[1],
                    cache = cache or nil,
                    sni_callback = function()
                        return target
                    end,
                }))
                os.remove(TICKET_SESSION)
                local reused, ticket = ticket_connection(lsock, root, protocol,
                                                         TICKET_SESSION, false,
                                                         {
                    servername = 'www.example.com',
                })
                assert.is_false(reused)
                assert.equal(ticket, conf[3])
            end
        end
    end
    lsock:close()
end

function testcase.new_server_sni_applies_ticket_lifetime()
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
        for _, conf in ipairs({
            {
                300,
                10,
            },
            {
                10,
                300,
            },
        }) do
            local target = assert(tls_server({
                cert = get_server_config().cert,
                key = get_server_config().key,
                session_timeout = conf[2],
            }))
            local root = assert(tls_server({
                cert = get_server_config().cert,
                key = get_server_config().key,
                session_timeout = conf[1],
                sni_callback = function()
                    return target
                end,
            }))
            local opts = {
                servername = 'www.example.com',
            }
            os.remove(TICKET_SESSION)
            local reused, ticket, trace =
                ticket_connection(lsock, root, protocol, TICKET_SESSION, false,
                                  opts)
            assert.is_false(reused)
            assert.is_true(ticket)
            -- Both versions encode the lifetime as uint32 immediately after
            -- the four-byte handshake header. Never print the ticket trace.
            local header = assert(trace:match(
                                      '%], NewSessionTicket\n%s*([%x ]+)'))
            header = header:gsub(' ', '')
            assert.equal(tonumber(header:sub(9, 16), 16), conf[2])
            assert.is_true(ticket_connection(lsock, root, protocol,
                                             TICKET_SESSION, true, opts))
        end
    end
    lsock:close()
end

function testcase.new_server_sni_expires_tickets_using_target_timeout()
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
        local target = assert(tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            session_timeout = 1,
        }))
        local root = assert(tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            session_timeout = 300,
            sni_callback = function()
                return target
            end,
        }))
        local opts = {
            servername = 'www.example.com',
        }
        os.remove(TICKET_SESSION)
        local reused, ticket = ticket_connection(lsock, root, protocol,
                                                 TICKET_SESSION, false, opts)
        assert.is_false(reused)
        assert.is_true(ticket)
        sleep(2)
        assert.is_false(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                          true, opts))
    end
    lsock:close()
end
