local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local tls_context = require('net.tls.context')
local tls_client = require('net.tls.client')
local new_ep = context_helpers.new_ep
local make_loopback_pair = context_helpers.make_loopback_pair
local handshake = context_helpers.handshake
local close_ep = context_helpers.close_ep
local handshake_pair = context_helpers.handshake_pair
local new_tls_server = support.new_tls_server
local new_tls_client = support.new_tls_client
local free_port = support.free_port
local start_s_server = support.start_s_server
local wait_listen = support.wait_listen
local get_server_config = support.get_server_config
local get_chain_fixture_dir = support.get_chain_fixture_dir
local UNVERIFIED = { verify_name = false, verify_cert = false }

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.encrypted_length()
    -- encrypted_length returns the maximum ciphertext size that may
    -- accompany a single record for the given protocol version.  Derive
    -- the expectations from the TLS record limits instead of magic
    -- numbers: a 5-byte header plus the 2^14 plaintext bound, with the
    -- per-version integrity overheads (1024 compression allowance,
    -- 16-byte explicit IV from TLS 1.1, MAC 20/64 bytes, 256 padding;
    -- TLS 1.3 uses a single 256-byte overhead budget).
    local header, plain = 5, 2 ^ 14
    local tls10 = header + plain + 1024 + 20 + 256
    local tls11 = tls10 + 16
    local tls12 = header + plain + 1024 + 16 + 64 + 256
    local tls13 = header + plain + 256

    assert.equal(tls_context.encrypted_length('tlsv1.0'), tls10)
    assert.equal(tls_context.encrypted_length('tlsv1.1'), tls11)
    assert.equal(tls_context.encrypted_length('tlsv1.2'), tls12)
    assert.equal(tls_context.encrypted_length('tlsv1.3'), tls13)
    -- 'default' and 'tlsv1' allow up to TLS 1.3; the largest ciphertext
    -- among the permitted versions is the TLS 1.2 bound
    assert.equal(tls_context.encrypted_length('default'), tls12)
    assert.equal(tls_context.encrypted_length('tlsv1'), tls12)
end

function testcase.methods_after_close()
    -- close before handshake exercises the "handshake_cb != NULL" branch that
    -- releases the SSL context without SSL_shutdown; further calls surface
    -- EINVAL through the shared "!ctx->ssl" gates in each method.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), UNVERIFIED))

    assert(ctx:close())
    -- second close is a no-op via the "!ctx->ssl" early return
    assert(ctx:close())

    -- every method returns (nil/false, EINVAL) once the SSL context is gone
    local ok, err = ctx:handshake()
    assert.is_false(ok)
    assert.equal(err.type, errno.EINVAL)

    local n, werr = ctx:write('data')
    assert.is_nil(n)
    assert.equal(werr.type, errno.EINVAL)

    local s, rerr = ctx:read()
    assert.is_nil(s)
    assert.equal(rerr.type, errno.EINVAL)

    local bio, gerr = ctx:get_bio()
    assert.is_nil(bio)
    assert.equal(gerr.type, errno.EINVAL)

    local alpn, aerr = ctx:get_alpn()
    assert.is_nil(alpn)
    assert.equal(aerr.type, errno.EINVAL)

    sp[1]:close()
    sp[2]:close()
end

function testcase.new_contexts_have_no_mutation_methods()
    local client = assert(new_tls_client())
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))

    assert.is_nil(client.set_verify_depth)
    assert.is_nil(client.load_verify_locations)
    assert.is_nil(client.set_crls)
    assert.is_nil(server.set_verify)
    assert.is_nil(server.set_sni_callback)
end

function testcase.tostring_metamethods()
    -- __tostring on tls.client, tls.server and tls.context userdata.
    local client = assert(new_tls_client())
    assert.match(tostring(client), '^net.tls.client: ', false)

    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    assert.match(tostring(server), '^net.tls.server: ', false)

    local csock, ssock = make_loopback_pair()
    local ctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))
    assert.match(tostring(ctx), '^net.tls.context: ', false)
    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.handshake_idempotent_after_success()
    -- Once the handshake completes, handshake_cb is cleared; calling
    -- handshake() again must short-circuit to the "already done" branch
    -- instead of re-entering SSL_connect/SSL_accept.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, UNVERIFIED))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))
    assert(ctx:handshake())

    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.get_alpn_returns_nil_when_not_negotiated()
    -- get_alpn is a hot path that ends in `return 0` when no ALPN was
    -- selected; the plain handshake path never advertises ALPN, so a
    -- fresh handshake must expose the len==0 branch.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, UNVERIFIED))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))
    assert.is_nil(ctx:get_alpn())

    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.negotiation_getters_after_handshake()
    -- Verified handshake against the chain fixture (root -> intermediate ->
    -- leaf): get_version / get_cipher / get_peer_cert / get_verify_result
    -- report the negotiated parameters on both endpoints.
    local csock, ssock = assert(make_loopback_pair())
    local server = assert(new_tls_server(
                              get_chain_fixture_dir() .. '/fullchain.pem',
                              get_chain_fixture_dir() .. '/leaf.key'))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local sep = new_ep(sctx, 'server', ssock:fd())

    local client = assert(tls_client({
        cafile = get_chain_fixture_dir() .. '/root.crt',
        capath = '.',
    }))
    local cctx = assert(tls_context.connect(client, csock:fd(), {
        servername = 'www.example.com',
    }))
    local cep = new_ep(cctx, 'client', csock:fd())

    assert(handshake_pair(cep, sep))

    -- the negotiated parameters are visible on both endpoints
    for _, ep in ipairs({
        cep,
        sep,
    }) do
        assert.re_match(ep.ctx:get_version(), '^TLSv1\\.[23]$')
        assert.re_match(ep.ctx:get_cipher(), '^TLS_')
    end

    -- the client sees the server leaf certificate in PEM form; the server
    -- sees no peer certificate because the client presented none
    assert.re_match(cep.ctx:get_peer_cert(), '^-----BEGIN CERTIFICATE')
    assert.is_nil(sep.ctx:get_peer_cert())

    -- the chain verified successfully against the root CA
    assert.is_true(cep.ctx:get_verify_result())

    -- the getters are not the subject here; dispose both contexts
    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.negotiation_getters_before_and_after_close()
    -- Before the handshake OpenSSL reports an unknown version, no cipher
    -- and no peer certificate; after close() every getter surfaces the
    -- disposed-context error like get_alpn().
    local csock, ssock = assert(make_loopback_pair())
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local client = assert(new_tls_client())
    local cctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))

    -- before the handshake the version value is OpenSSL-dependent (some
    -- versions report the maximum supported version, others "unknown");
    -- only its presence is stable.  No cipher is selected and the peer has
    -- not presented a certificate yet.
    assert.is_string(cctx:get_version())
    assert.is_nil(cctx:get_cipher())
    assert.is_nil(cctx:get_peer_cert())
    -- the verify result starts at X509_V_OK and has not been computed yet
    assert.is_true(cctx:get_verify_result())

    assert(cctx:close())
    assert(sctx:close())
    local v, err = cctx:get_version()
    assert.is_nil(v)
    assert.not_nil(err)
    v, err = cctx:get_cipher()
    assert.is_nil(v)
    assert.not_nil(err)
    v, err = cctx:get_peer_cert()
    assert.is_nil(v)
    assert.not_nil(err)
    v, err = cctx:get_verify_result()
    assert.is_nil(v)
    assert.not_nil(err)

    csock:close()
    ssock:close()
end
