local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local tls_context = require('net.tls.context')
local tls_client = require('net.tls.client')
local new_ep = context_helpers.new_ep
local handshake = context_helpers.handshake
local transfer_write = context_helpers.transfer_write
local close_ep = context_helpers.close_ep
local new_tls_client = support.new_tls_client
local free_port = support.free_port
local start_s_server = support.start_s_server
local wait_listen = support.wait_listen
local start_s_server_cert = support.start_s_server_cert
local connect_verifying_client = support.connect_verifying_client
local get_server_config = support.get_server_config
local get_verify_fixture_dir = support.get_verify_fixture_dir
local UNVERIFIED = { verify_name = false, verify_cert = false }

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.connect_requires_servername_when_full_verify()
    -- Full verification without a servername has no identity to match
    -- against the peer certificate, so connect must refuse to proceed.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    -- servername=nil, verify_name=true, verify_time=true,
    -- verify_cert=true: full verification requested with no identity
    -- to verify against.
    local ctx, cerr = tls_context.connect(client, sp[1]:fd())
    assert(ctx == nil, 'connect must fail when servername is required')
    assert(cerr, 'connect must return an error object')
    assert.match(tostring(cerr), 'servername', false)
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.connect_allows_missing_servername_with_verify_cert_false()
    -- With certificate verification fully disabled there is no identity
    -- to match, so connect must not demand a servername; SNI is simply
    -- not sent.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    -- servername=nil, verify_name=false, verify_time=true,
    -- verify_cert=false: verification is fully disabled, so there is
    -- no identity requirement to satisfy.
    local ctx, err = tls_context.connect(client, sp[1]:fd(), UNVERIFIED)
    assert(ctx, err)
    assert(ctx:close())
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.connect_rejects_verify_name_without_verify_cert()
    -- Name verification runs as part of certificate verification, so
    -- requesting it while disabling certificate verification is a
    -- contradiction and must surface as an error instead of silently
    -- taking no effect.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    -- servername='www.example.com', verify_name=true, verify_time=true,
    -- verify_cert=false
    local ctx, err = tls_context.connect(client, sp[1]:fd(), {
        servername = 'www.example.com',
        verify_cert = false,
    })
    assert(ctx == nil, 'connect must fail on the contradictory request')
    assert(err, 'connect must return an error object')
    assert.match(tostring(err), 'verify_name', false)
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.connect_rejects_embedded_nul_servername()
    -- A servername containing an embedded NUL ("www.example.com\0.evil")
    -- would be silently truncated to "www.example.com" by the C string APIs
    -- used for SNI, hostname verification and IP identity; connect must
    -- reject it with EINVAL instead.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())

    -- with full verification
    local ctx, err = tls_context.connect(client, sp[1]:fd(), {
        servername = 'www.example.com\0.evil',
    })
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    -- with verification fully disabled (SNI would still truncate)
    ctx, err = tls_context.connect(client, sp[1]:fd(), {
        servername = 'a\0.evil',
        verify_name = false,
        verify_cert = false,
    })
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    for _, s in ipairs(sp) do
        s:close()
    end
end

function testcase.connect_accepts_ip_servername_with_verify()
    -- IPv4/IPv6 literals are accepted with verify enabled; SSL_get0_param
    -- receives an IP identity through X509_VERIFY_PARAM_set1_ip_asc.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    for _, servername in ipairs({
        '127.0.0.1',
        '::1',
    }) do
        local ctx, cerr = tls_context.connect(client, sp[1]:fd(), {
            servername = servername,
        })
        assert(ctx, cerr and tostring(cerr) or
                   'connect must accept IP servername with verify enabled')
    end
    -- close only after the loop: connect() now rejects the -1 fd reported by
    -- a closed socket instead of silently handing it to OpenSSL.
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.connect_accepts_no_servername_when_hostname_verify_disabled()
    -- Dropping hostname verification exempts the caller from providing a
    -- servername; connect must accept nil then.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    local ctx, cerr = tls_context.connect(client, sp[1]:fd(), UNVERIFIED)
    assert(ctx, cerr and tostring(cerr) or
               'connect must accept nil servername when verify_name=false')
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.client_verify_good_chain_succeeds()
    -- control for the negative fixtures: the good-server certificate
    -- chains to the loaded trust anchor and matches the servername, so
    -- full verification succeeds and the session transfers data.
    local port = free_port()
    local proc = start_s_server_cert(port, get_verify_fixture_dir() ..
                                         '/good-server.crt',
                                     get_verify_fixture_dir() ..
                                         '/good-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', true,
                                             true, true)
    assert(ep, err and tostring(err) or
               'full verification must accept the good certificate')
    collectgarbage('collect')
    assert(transfer_write(ep, proc, 'verified'))
    assert(close_ep(ep))
    proc:close()
end

function testcase.client_verify_untrusted_chain_fails_handshake()
    -- a self-signed certificate that does not chain to the loaded trust
    -- anchor must fail the handshake under full verification
    local port = free_port()
    local proc = start_s_server_cert(port, get_verify_fixture_dir() ..
                                         '/untrusted-server.crt',
                                     get_verify_fixture_dir() ..
                                         '/untrusted-server.key')
    local ep, err, verify_error = connect_verifying_client(port,
                                                           'www.example.com',
                                                           true, true, true)
    assert.is_nil(ep)
    assert.not_nil(err)
    assert.equal(verify_error, 'self-signed certificate')

    proc:close()
end

function testcase.client_verify_name_mismatch_fails_handshake()
    -- a validly chained certificate whose CN does not match the
    -- servername must fail the handshake under full verification
    local port = free_port()
    local proc = start_s_server_cert(port, get_verify_fixture_dir() ..
                                         '/wrongname-server.crt',
                                     get_verify_fixture_dir() ..
                                         '/wrongname-server.key')
    local ep, err, verify_error = connect_verifying_client(port,
                                                           'www.example.com',
                                                           true, true, true)
    assert.is_nil(ep)
    assert.not_nil(err)
    assert.equal(verify_error, 'hostname mismatch')

    proc:close()
end

function testcase.client_verify_expired_cert_fails_handshake()
    -- an otherwise valid certificate whose validity period has ended
    -- must fail the handshake under full verification
    local port = free_port()
    local proc = start_s_server_cert(port, get_verify_fixture_dir() ..
                                         '/expired-server.crt',
                                     get_verify_fixture_dir() ..
                                         '/expired-server.key')
    local ep, err, verify_error = connect_verifying_client(port,
                                                           'www.example.com',
                                                           true, true, true)
    assert.is_nil(ep)
    assert.not_nil(err)
    assert.equal(verify_error, 'certificate has expired')

    proc:close()
end

function testcase.client_verify_cert_false_allows_untrusted_chain()
    -- effectiveness of verify_cert=false: certificate verification is
    -- skipped entirely, so even the untrusted certificate connects and
    -- transfers data
    local port = free_port()
    local proc = start_s_server_cert(port, get_verify_fixture_dir() ..
                                         '/untrusted-server.crt',
                                     get_verify_fixture_dir() ..
                                         '/untrusted-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', false,
                                             true, false)
    assert(ep, err and tostring(err) or
               'verify_cert=false must accept the untrusted certificate')
    assert(transfer_write(ep, proc, 'unverified'))
    assert(close_ep(ep))
    proc:close()
end

function testcase.client_verify_name_false_allows_name_mismatch()
    -- effectiveness of verify_name=false: the chain is still verified
    -- but the hostname mismatch no longer fails the handshake
    local port = free_port()
    local proc = start_s_server_cert(port, get_verify_fixture_dir() ..
                                         '/wrongname-server.crt',
                                     get_verify_fixture_dir() ..
                                         '/wrongname-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', false,
                                             true, true)
    assert(ep, err and tostring(err) or
               'verify_name=false must accept the mismatched hostname')
    assert(transfer_write(ep, proc, 'name-off'))
    assert(close_ep(ep))
    proc:close()
end

function testcase.client_verify_time_false_allows_expired_cert()
    -- effectiveness of verify_time=false: the chain and the hostname are
    -- still verified but the expired validity period no longer fails
    -- the handshake
    local port = free_port()
    local proc = start_s_server_cert(port, get_verify_fixture_dir() ..
                                         '/expired-server.crt',
                                     get_verify_fixture_dir() ..
                                         '/expired-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', true,
                                             false, true)
    assert(ep, err and tostring(err) or
               'verify_time=false must accept the expired certificate')
    assert(transfer_write(ep, proc, 'time-off'))
    assert(close_ep(ep))
    proc:close()
end

function testcase.new_client_verify_options()
    local client = assert(tls_client({
        verify_depth = 5,
        cafile = get_server_config().cert,
        capath = '.',
    }))
    assert.match(tostring(client), '^net.tls.client: ', false)

    local ctx, err = tls_client({
        cafile = './no-such-ca.pem',
        capath = '.',
    })
    assert.is_nil(ctx)
    assert.not_nil(err)
end

function testcase.new_client_verify_locations_optional_arguments()
    assert(tls_client({
        cafile = get_server_config().cert,
    }))
    assert(tls_client({
        capath = '.',
    }))
end

function testcase.connect_verify_time_false_with_valid_cert()
    -- verify_time=false installs the expiry-ignoring callback; a valid (non-expired)
    -- fixture cert drives its preverify_ok=1 branch.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(tls_client({
        cafile = get_server_config().cert,
        capath = '.',
    }))
    -- servername matches CN of the fixture cert; verify_time=false, but
    -- the cert is not expired, so the callback returns preverify_ok as-is.
    local ctx = assert(tls_context.connect(client, fd, {
        servername = 'www.example.com',
        verify_time = false,
    }))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))
    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.connect_ip_servername_with_verify_name_false()
    -- servername is a numeric IP AND verify_name=false: the SNI-skip +
    -- verify-skip branch runs (no X509_VERIFY_PARAM_set1_ip_asc call).
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, {
        servername = '127.0.0.1',
        verify_name = false,
        verify_cert = false,
    }))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))

    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.connect_rejects_servername_longer_than_sni_limit()
    -- SNI hostnames are capped at 255 octets.  Passing a longer name must
    -- surface SSL_set_tlsext_host_name's failure through the standard
    -- (nil, error) return of tls_context.connect.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx, err = tls_context.connect(client, sp[1]:fd(), {
        servername = string.rep('a', 256),
    })
    assert.is_nil(ctx)
    assert(err)
    assert.match(tostring(err), 'ssl3_ctrl', false)

    sp[1]:close()
    sp[2]:close()
end

function testcase.new_client_rejects_out_of_range_verify_depth()
    assert(tls_client({
        verify_depth = 0,
    }))
    assert(tls_client({
        verify_depth = 2147483647,
    }))
    assert.throws(function()
        tls_client({
            verify_depth = 2147483648,
        })
    end)
end
