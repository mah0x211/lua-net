local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local socket = require('net.socket')
local wait = require('io.wait')
local tls_context = require('net.tls.context')
local tls_cache = require('net.tls.cache')
local tls_server = require('net.tls.server')
local DEADLINE = context_helpers.DEADLINE
local new_ep = context_helpers.new_ep
local handshake = context_helpers.handshake
local transfer_write = context_helpers.transfer_write
local close_ep = context_helpers.close_ep
local exec = support.exec
local new_tls_server = support.new_tls_server
local new_tls_client = support.new_tls_client
local free_port = support.free_port
local start_s_server = support.start_s_server
local start_s_client = support.start_s_client
local start_s_client_tls12_cipher = support.start_s_client_tls12_cipher
local wait_listen = support.wait_listen
local get_server_config = support.get_server_config
local UNVERIFIED = { verify_name = false, verify_cert = false }

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.secure_cipher_suite_selects_ecdhe_aead()
    -- the 'secure' cipher suite policy admits only ECDHE+AEAD suites on
    -- TLS 1.2 (the TLSRef intermediate profile); an AEAD client connects
    -- while an RSA-key-exchange CBC client must be rejected.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    -- the AEAD-only client negotiates an ECDHE-RSA AEAD suite
    local proc =
        start_s_client_tls12_cipher(port, 'ECDHE-RSA-AES128-GCM-SHA256')
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key, 'tlsv1.2',
                                         'secure', nil, 300))
    local ctx = assert(tls_context.accept(server, afd))
    local ep = new_ep(ctx, 'server', afd)

    assert(handshake(ep))
    assert.equal(ep.ctx:get_cipher(), 'ECDHE-RSA-AES128-GCM-SHA256')
    assert(close_ep(ep))
    proc:close()

    -- an RSA-key-exchange CBC client is inside HIGH:!aNULL but outside
    -- the ECDHE+AEAD-only policy, so the handshake must fail
    local proc2 = start_s_client_tls12_cipher(port, 'AES128-SHA')
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd2 = assert(lsock:acceptfd())
    local asock2 = assert(socket.wrap(afd2))
    socks[#socks + 1] = asock2
    local server2 = assert(new_tls_server(get_server_config().cert,
                                          get_server_config().key, 'tlsv1.2',
                                          'secure', nil, 300))
    local ctx2 = assert(tls_context.accept(server2, afd2))
    local ep2 = new_ep(ctx2, 'server', afd2)

    local ok, err = handshake(ep2)
    assert.is_false(ok)
    assert.not_nil(err)

    for _, s in ipairs(socks) do
        s:close()
    end
    proc2:close()
end

function testcase.accept_s_client_tls13_ciphersuite_allowed()
    -- Every TLS 1.3 suite of the cipher policy must negotiate: s_client
    -- offers one suite per iteration, all of them inside the policy.
    for _, suite in ipairs({
        'TLS_AES_256_GCM_SHA384',
        'TLS_CHACHA20_POLY1305_SHA256',
        'TLS_AES_128_GCM_SHA256',
    }) do
        local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
            reuseaddr = true,
            reuseport = true,
        }))
        local socks = {
            lsock,
        }
        assert(lsock:listen())
        local port = assert(lsock:getsockname()):port()

        local proc = start_s_client(port, nil, suite)
        assert(wait.readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        local asock = assert(socket.wrap(afd))
        socks[#socks + 1] = asock
        local fd = asock:fd()

        local server = assert(new_tls_server(get_server_config().cert,
                                             get_server_config().key, 'default',
                                             'default'))
        local ctx = assert(tls_context.accept(server, fd))
        local ep = new_ep(ctx, 'server', fd)

        assert(handshake(ep), suite .. ' must negotiate')
        assert(transfer_write(ep, proc, 'tls1.3 ' .. suite))
        assert(close_ep(ep))
        for _, s in ipairs(socks) do
            s:close()
        end
        proc:close()
    end
end

function testcase.accept_s_client_tls13_ciphersuite_rejected()
    -- TLS 1.3 suites outside the cipher policy must not negotiate: s_client
    -- offers only TLS_AES_128_CCM_SHA256, which the policy does not include.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client(port, nil, 'TLS_AES_128_CCM_SHA256')
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key, 'default',
                                         'default'))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    local ok = handshake(ep)
    assert.is_false(ok)

    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.connect_s_server_tls13_ciphersuite_rejected()
    -- Client side of the cipher policy: s_server offers only
    -- TLS_AES_128_CCM_SHA256, which the client policy does not include.
    local port = free_port()
    local proc = start_s_server(port, nil, 'TLS_AES_128_CCM_SHA256')
    local csock = assert(wait_listen(port))
    local socks = {
        csock,
    }
    local fd = csock:fd()

    local client = assert(new_tls_client('default', 'default'))
    local ctx = assert(tls_context.connect(client, fd, UNVERIFIED))
    local ep = new_ep(ctx, 'client', fd)

    local ok = handshake(ep)
    assert.is_false(ok)

    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.new_server_cipher_preference()
    -- TLS 1.2 cipher preference: the client offers AES128-SHA256 before
    -- AES256-SHA384, while the 'default' server policy (HIGH:!aNULL) ranks
    -- AES256-SHA384 first. Default keeps SSL_OP_CIPHER_SERVER_PREFERENCE
    -- (server order wins); prefer_client_ciphers = true drops the option
    -- (client order wins).
    local selected_cipher = function(prefer_client)
        local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
            reuseaddr = true,
            reuseport = true,
        }))
        local socks = {
            lsock,
        }
        assert(lsock:listen())
        local port = assert(lsock:getsockname()):port()

        local proc = exec('openssl', {
            's_client',
            '-connect',
            '127.0.0.1:' .. tostring(port),
            '-brief',
            '-noservername',
            '-tls1_2',
            '-cipher',
            'ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384',
        })
        assert(wait.readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        -- Keep the wrapper alive so its __gc does not close the fd while
        -- the TLS context still uses it.
        local asock = assert(socket.wrap(afd))
        socks[#socks + 1] = asock
        local fd = asock:fd()

        local server = assert(new_tls_server(get_server_config().cert,
                                             get_server_config().key, 'tlsv1.2',
                                             'default', nil, 300, prefer_client))
        local ctx = assert(tls_context.accept(server, fd))
        local ep = new_ep(ctx, 'server', fd)
        assert(handshake(ep))

        -- s_client -brief prints the negotiated suite on stderr.
        local selected
        for line in proc.stderr:lines() do
            selected = line:match('^Ciphersuite:%s+(%S+)')
            if selected then
                break
            end
        end
        assert(close_ep(ep))
        for _, s in ipairs(socks) do
            s:close()
        end
        proc:close()
        return selected
    end

    -- default: the server preference (AES256-SHA384 ranks first) wins.
    assert.equal(selected_cipher(nil), 'ECDHE-RSA-AES256-SHA384')
    -- prefer_client_ciphers = true: the client order wins.
    assert.equal(selected_cipher(true), 'ECDHE-RSA-AES128-SHA256')
end

function testcase.new_server_sni_cipher_preference()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())

    local function selected_cipher(server, protocol, servername)
        local args = {
            's_client',
            '-connect',
            '127.0.0.1:' .. tostring(assert(lsock:getsockname()):port()),
            '-quiet',
            '-no_ign_eof',
            protocol,
            '-cipher',
            'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384',
            '-ciphersuites',
            'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384',
        }
        if servername then
            args[#args + 1] = '-servername'
            args[#args + 1] = servername
        else
            args[#args + 1] = '-noservername'
        end
        local proc = assert(exec('openssl', args))
        assert(wait.readable(lsock:fd(), DEADLINE))
        local sock = assert(socket.wrap(assert(lsock:acceptfd())))
        local ctx = assert(tls_context.accept(server, sock:fd()))
        local ep = new_ep(ctx, 'server', sock:fd(), sock)
        assert(handshake(ep))
        local cipher = ctx:get_cipher()
        assert(close_ep(ep))
        assert.equal(assert(proc:close()).exit, 0)
        return cipher
    end

    for _, conf in ipairs({
        {
            protocol = '-tls1_2',
            client_first = 'ECDHE-RSA-AES128-GCM-SHA256',
            server_first = 'ECDHE-RSA-AES256-GCM-SHA384',
        },
        {
            protocol = '-tls1_3',
            client_first = 'TLS_AES_128_GCM_SHA256',
            server_first = 'TLS_AES_256_GCM_SHA384',
        },
    }) do
        for _, cache in ipairs({
            false,
            tls_cache({
                ctx_capacity = 2,
            }),
        }) do
            for _, prefer_client in ipairs({
                true,
                false,
            }) do
                local target = assert(tls_server({
                    cert = get_server_config().cert,
                    key = get_server_config().key,
                    prefer_client_ciphers = prefer_client,
                    cache = cache or nil,
                }))
                local root = assert(tls_server({
                    cert = get_server_config().cert,
                    key = get_server_config().key,
                    prefer_client_ciphers = not prefer_client,
                    cache = cache or nil,
                    sni_callback = function(name)
                        if name == 'www.example.com' then
                            return target
                        end
                    end,
                }))
                local expected = prefer_client and conf.client_first or
                                     conf.server_first
                local root_expected = prefer_client and conf.server_first or
                                          conf.client_first
                local direct = selected_cipher(target, conf.protocol)
                assert.equal(direct, expected)
                assert.equal(selected_cipher(root, conf.protocol,
                                             'www.example.com'), direct)
                assert.equal(selected_cipher(root, conf.protocol), root_expected)
                assert.equal(selected_cipher(root, conf.protocol,
                                             'unknown.example.com'),
                             root_expected)
            end
        end
    end
    lsock:close()
end
