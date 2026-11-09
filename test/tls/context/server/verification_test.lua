local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local socket = require('net.socket')
local wait = require('io.wait')
local tls_context = require('net.tls.context')
local tls_server = require('net.tls.server')
local DEADLINE = context_helpers.DEADLINE
local new_ep = context_helpers.new_ep
local handshake = context_helpers.handshake
local close_ep = context_helpers.close_ep
local new_tls_server = support.new_tls_server
local start_s_client = support.start_s_client
local start_s_client_with_cert = support.start_s_client_with_cert
local start_s_client_sni = support.start_s_client_sni
local get_server_config = support.get_server_config
local get_client_cert_fixture_dir = support.get_client_cert_fixture_dir

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.server_verify_client_cert_required()
    -- A require-mode server that trusts the client CA accepts a client
    -- presenting a valid certificate; the client certificate and its
    -- verification result are visible on the accepted context.
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

    local proc = start_s_client_with_cert(port,
                                          get_client_cert_fixture_dir() ..
                                              '/client.crt',
                                          get_client_cert_fixture_dir() ..
                                              '/client.key')
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        verify_mode = 'require',
        cafile = get_client_cert_fixture_dir() .. '/ca.crt',
        capath = '.',
    }))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert.re_match(ctx:get_peer_cert(), '^-----BEGIN CERTIFICATE')
    assert.is_true(ctx:get_verify_result())

    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.server_verify_client_cert_required_rejects_no_cert()
    -- require mode aborts the handshake when the client presents no
    -- certificate
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

    local proc = start_s_client(port)
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        verify_mode = 'require',
        cafile = get_client_cert_fixture_dir() .. '/ca.crt',
        capath = '.',
    }))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    local ok, err = handshake(ep)
    assert.is_false(ok)
    assert.not_nil(err)

    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.server_verify_client_cert_required_rejects_untrusted()
    -- a certificate from a CA the server does not trust fails the handshake
    -- in require mode
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

    local proc = start_s_client_with_cert(port, get_server_config().cert,
                                          get_server_config().key)
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        verify_mode = 'require',
        cafile = get_client_cert_fixture_dir() .. '/ca.crt',
        capath = '.',
    }))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    local ok, err = handshake(ep)
    assert.is_false(ok)
    assert.not_nil(err)

    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.server_verify_client_cert_request_without_cert()
    -- request mode lets the handshake continue without a client
    -- certificate; no peer certificate is then visible
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

    local proc = start_s_client(port)
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        verify_mode = 'request',
        cafile = get_client_cert_fixture_dir() .. '/ca.crt',
        capath = '.',
    }))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert.is_nil(ctx:get_peer_cert())

    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.sni_switch_applies_vhost_verify_settings()
    -- SSL_set_SSL_CTX() only swaps the certificate chain and the sid_ctx;
    -- the verify mode, depth and verify parameters stay on the
    -- connection. A vhost configured with verify_mode='require' was
    -- previously not enforced after an SNI switch, so a client could
    -- bypass the certificate requirement by connecting with the vhost's
    -- hostname.  The switch must re-apply the target CTX verify settings.
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

    -- the root server keeps the default (no client verification)
    -- vhost A requires a client certificate signed by its CA
    local vhosta = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        verify_mode = 'require',
        cafile = get_client_cert_fixture_dir() .. '/ca.crt',
    }))
    -- vhost B keeps the default like the root
    local vhostb = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local root = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        sni_callback = function(name)
            if name == 'www.example.com' then
                return vhosta
            end
            return vhostb
        end,
    }))

    local function accept_handshake()
        assert(wait.readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        local asock = assert(socket.wrap(afd))
        socks[#socks + 1] = asock
        local fd = asock:fd()
        local ctx = assert(tls_context.accept(root, fd))
        local ep = new_ep(ctx, 'server', fd)
        return ep, handshake(ep)
    end

    -- 1) vhost A without a client certificate: the handshake must fail
    local proc = start_s_client_sni(port, 'www.example.com')
    local ep, ok, err = accept_handshake()
    assert.is_false(ok)
    assert.not_nil(err)
    assert(close_ep(ep))
    proc:close()

    -- 2) vhost A with the client certificate: the handshake succeeds
    proc = start_s_client_sni(port, 'www.example.com',
                              get_client_cert_fixture_dir() .. '/client.crt',
                              get_client_cert_fixture_dir() .. '/client.key')
    ep, ok, err = accept_handshake()
    assert(ok, err)
    assert(close_ep(ep))
    proc:close()

    -- 3) vhost B without a client certificate: the handshake succeeds
    proc = start_s_client_sni(port, 'other.example.net')
    ep, ok, err = accept_handshake()
    assert(ok, err)
    assert(close_ep(ep))
    proc:close()

    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.new_server_rejects_out_of_range_verify_depth()
    assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        verify_depth = 2147483647,
    }))
    assert.throws(function()
        tls_server({
            cert = get_server_config().cert,
            key = get_server_config().key,
            verify_depth = 2147483648,
        })
    end)
end

function testcase.new_server_verify_options()
    local config = get_server_config()
    local err = assert.throws(function()
        tls_server({
            cert = config.cert,
            key = config.key,
            verify_mode = 'hello',
        })
    end)
    assert.re_match(err, 'hello')

    local server
    server, err = tls_server({
        cert = config.cert,
        key = config.key,
        verify_mode = 'require',
        cafile = '__net_no_such_ca__.crt',
    })
    assert.is_nil(server)
    assert.not_nil(err)

    assert(tls_server({
        cert = config.cert,
        key = config.key,
        cafile = config.cert,
        capath = '.',
    }))
    for _, mode in ipairs({
        'none',
        'request',
        'require',
    }) do
        assert(tls_server({
            cert = config.cert,
            key = config.key,
            verify_mode = mode,
            verify_depth = 2,
        }))
    end
    assert.throws(function()
        tls_server({
            cert = config.cert,
            key = config.key,
            verify_depth = -1,
        })
    end)
    assert.throws(function()
        tls_server({
            cert = config.cert,
            key = config.key,
            verify_mode = 'require\0',
        })
    end)
end
