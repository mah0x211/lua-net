local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local socket = require('net.socket')
local wait = require('io.wait')
local new_deadline = require('time.clock.deadline').new
local tls_context = require('net.tls.context')
local tls_inet = require('net.tls.stream.inet')
local new_ep = context_helpers.new_ep
local make_loopback_pair = context_helpers.make_loopback_pair
local pump = context_helpers.pump
local handshake_pair = context_helpers.handshake_pair
local new_tls_server = support.new_tls_server
local new_tls_client = support.new_tls_client
local get_server_config = support.get_server_config
local UNVERIFIED = { verify_name = false, verify_cert = false }

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.handshake_reports_clean_close_without_error()
    -- A clean close_notify from the peer during the handshake surfaces
    -- as a failure without an error object, the TCP-convention signature
    -- shared with read(): (false, nil) means the peer closed cleanly,
    -- while every actual failure carries an error object.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = {
        sp[1],
        sp[2],
    }

    local client = assert(new_tls_client())
    local cctx = assert(tls_context.connect(client, sp[1]:fd(), {
        servername = 'www.example.com',
        verify_name = false,
        verify_cert = false,
    }))

    -- the first round sends the ClientHello and asks to read
    local ok, err, want = cctx:handshake()
    assert.is_false(ok)
    assert.is_nil(err)
    assert.is_number(want)
    -- the ClientHello ciphertext must reach the peer
    assert(cctx:get_bio():drain())

    -- the peer answers with a plaintext close_notify alert record
    assert(sp[2]:send('\21\3\3\0\2\1\0'))
    -- move the injected record from the socket into the rx ring so the
    -- BIO-backed handshake can observe it
    assert(cctx:get_bio():fill())

    ok, err, want = cctx:handshake()
    -- the clean close returns no values at all, the TCP-convention
    -- signature shared with read()
    assert.is_nil(ok)
    assert.is_nil(err)
    assert.is_nil(want)

    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.handshake_wrapper_reports_clean_close_without_error()
    -- the net.tls.Socket wrapper keeps the same signature when the peer
    -- closes during the handshake: (false, nil) for the clean close
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = {
        sp[1],
        sp[2],
    }

    local client = assert(new_tls_client())
    local cctx = assert(tls_context.connect(client, sp[1]:fd(), {
        servername = 'www.example.com',
        verify_name = false,
        verify_cert = false,
    }))
    -- the ClientHello ciphertext must reach the peer before it can answer
    -- with a close_notify; the wrapper drives the handshake internally,
    -- so drain/fill manually here
    assert(sp[2]:send('\21\3\3\0\2\1\0'))
    local c = tls_inet.Client(sp[1], cctx)

    local ok, err = c:handshake()
    assert.is_false(ok)
    assert.is_nil(err)

    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.shutdown_close_notify_reaches_peer_bio()
    -- shutdown() must not free the context; the close_notify ciphertext it
    -- leaves in the TX BIO has to be drained to the socket so the peer sees
    -- a clean EOF instead of a truncation.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local cctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))
    local deadline = new_deadline(1)

    -- the initiator's first shutdown leaves its close_notify in the TX BIO
    local ok, err, want = cctx:shutdown()
    assert.is_false(ok)
    assert.is_nil(err)
    assert.equal(want, tls_context.WANT_WRITE)
    -- the context and its BIO must still be alive after the call
    assert(cctx:get_bio(), 'BIO must survive shutdown()')
    pump(cep)

    -- retry: close_notify sent, now waiting for the peer's one
    ok, err, want = cctx:shutdown()
    assert.is_false(ok)
    assert.is_nil(err)
    assert.equal(want, tls_context.WANT_READ)

    -- the peer receives the close_notify as a clean EOF
    while true do
        pump(sep)
        local data, read_err, read_want = sctx:read(1024)
        assert.is_nil(data)
        assert.is_nil(read_err)
        if not read_want then
            break
        end
        assert.equal(read_want, tls_context.WANT_READ)
        local done, sec = deadline:is_done()
        assert(not done, 'peer close_notify timed out')
        assert(wait.readable(ssock:fd(), sec))
    end

    -- the peer already received our close_notify, so its shutdown completes
    -- immediately with its own close_notify left in the TX BIO
    ok, err, want = sctx:shutdown()
    assert.is_true(ok)
    assert.is_nil(err)
    assert.is_nil(want)
    -- the SSL object is released on completion but the BIO stays available
    -- for the final drain
    assert(sctx:get_bio(), 'BIO must survive shutdown() completion')
    pump(sep)
    pump(cep)

    -- the initiator's retry completes once the peer's close_notify arrives
    while true do
        ok, err, want = cctx:shutdown()
        assert.is_nil(err)
        if ok then
            break
        end
        assert.equal(want, tls_context.WANT_READ)
        local done, sec = deadline:is_done()
        assert(not done, 'shutdown close_notify timed out')
        assert(wait.readable(csock:fd(), sec))
        pump(cep)
    end

    -- close() is a pure disposal and idempotent; shutdown() stays true
    -- after disposal
    assert(cctx:close())
    assert(cctx:close())
    assert(cctx:shutdown())
    assert(sctx:close())

    csock:close()
    ssock:close()
end

function testcase.read_reports_clean_close_on_close_notify()
    -- After the peer shuts down cleanly, read() follows the TCP
    -- convention and returns nothing: (nil, nil), like a plain socket
    -- read at EOF, instead of surfacing the close as an error.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local cctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))

    -- initiate the client shutdown and deliver its close_notify
    cctx:shutdown()
    pump(cep)
    pump(sep)

    local str, err, want = sctx:read(1024)
    assert.is_nil(str)
    assert.is_nil(err)
    assert.is_nil(want)

    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.write_fails_after_own_close_notify_sent()
    -- After our own close_notify has been sent, a further write must
    -- fail with an error instead of looking like success.  (Writing
    -- after only the peer's close_notify stays legal: TLS 1.3 allows
    -- the half-close direction.)
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local cctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))

    -- the client's first shutdown leaves its close_notify in the TX BIO
    cctx:shutdown()
    pump(cep)
    pump(sep)

    local n, err = cctx:write('x')
    assert.is_nil(n)
    assert.not_nil(err)

    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.shutdown_before_handshake_and_close_idempotent()
    -- shutdown() before the handshake is a no-op that must not free the
    -- context; close() is an unconditional disposal and idempotent.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), UNVERIFIED))

    assert(ctx:shutdown())
    local bio = assert(ctx:get_bio(), 'BIO must survive shutdown()')
    -- an empty ring drains as a no-op
    assert.equal(bio:drain(), 0)

    assert(ctx:close())
    assert(ctx:close())
    assert(ctx:shutdown())
    assert.is_nil(ctx:get_bio())

    sp[1]:close()
    sp[2]:close()
end
