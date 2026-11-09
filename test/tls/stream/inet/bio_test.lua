local support = require('test.tls.stream.inet.helpers').new()
local testcase = require('testcase')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local inet = require('net.stream.inet')
local tls_inet = require('net.tls.stream.inet')
local tls_context = require('net.tls.context')
local new_tls_client = support.new_tls_client
local get_server_config = support.get_server_config

local CLIENT_CONFIG

function testcase.before_all()
    CLIENT_CONFIG = select(2, support.before_all())
end

function testcase.after_all()
    support.after_all()
end

function testcase.after_each()
    support.after_each()
end

function testcase.bio_fill_without_timeout_does_not_crash()
    -- The internal deadline object was nil when Socket:bio_fill was
    -- called without a sec argument, but the EAGAIN path invoked
    -- deadline:is_done() unconditionally.  On a non-blocking socket
    -- that immediately returns EAGAIN the old code raised "attempt to
    -- index a nil value".  Replace tls_bio with a stub whose fill()
    -- reports EAGAIN deterministically (a real peer may deliver EOF
    -- instead of EAGAIN once the client closes, which made the test
    -- racy), and let the stubbed wait_readable prove that a deadline
    -- was materialized (non-nil remaining sec) before waiting.
    -- These methods only exercise BIO retry/deadline logic; no TLS exchange
    -- or child process is required before installing the controlled BIO.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx =
        assert(tls_context.connect(client, socks[1]:fd(), CLIENT_CONFIG))
    local peer = tls_inet.Client(socks[1], ctx)
    assert.not_nil(peer.tls_bio)

    local bio = peer.tls_bio
    local again = errno.new('EAGAIN')
    peer.tls_bio = {
        fill = function()
            return nil, again, true
        end,
    }

    -- sentinel only the stubbed wait can produce; the stub also asserts
    -- that the deadline provided a numeric remaining sec.
    local sentinel = errno.new('ECANCELED', 'test-sentinel')
    peer.wait_readable = function(_, sec)
        assert(type(sec) == 'number', 'remaining sec must be a number')
        return false, sentinel
    end

    local ok, err = peer:bio_fill()
    assert.is_false(ok)
    assert.equal(err, sentinel)

    peer.tls_bio = bio
    peer:close()
    socks[2]:close()
end

function testcase.bio_drain_without_timeout_does_not_crash()
    -- Same bug class as bio_fill_without_timeout_does_not_crash: with no sec
    -- argument the internal deadline was nil and the EAGAIN path of
    -- bio_drain crashed on deadline:is_done().  Replace tls_bio with a
    -- stub whose drain() reports EAGAIN, and let the stubbed wait_writable
    -- verify that a deadline was materialized (non-nil remaining sec)
    -- before waiting.
    -- These methods only exercise BIO retry/deadline logic; no TLS exchange
    -- or child process is required before installing the controlled BIO.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx =
        assert(tls_context.connect(client, socks[1]:fd(), CLIENT_CONFIG))
    local peer = tls_inet.Client(socks[1], ctx)
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')

    local bio = peer.tls_bio
    local again = errno.new('EAGAIN')
    peer.tls_bio = {
        drain = function()
            return nil, again, true
        end,
    }

    -- sentinel only the stubbed wait can produce; the stub also asserts
    -- that the deadline provided a numeric remaining sec.
    local sentinel = errno.new('ECANCELED', 'test-sentinel')
    peer.wait_writable = function(_, sec)
        assert(type(sec) == 'number', 'remaining sec must be a number')
        return false, sentinel
    end

    local ok, err = peer:bio_drain()
    assert.is_false(ok)
    assert.equal(err, sentinel)

    peer.tls_bio = bio
    peer:close()
    socks[2]:close()
end

function testcase.bio_drain_waits_after_partial_drain_eagain()
    -- drain() reports a partial transfer as (n, nil, true): bytes moved,
    -- but the socket would block.  bio_drain must keep waiting instead of
    -- returning success with the remaining ciphertext still in the TX
    -- buffer, otherwise the peer sees a truncated record stream.
    -- These methods only exercise BIO retry/deadline logic; no TLS exchange
    -- or child process is required before installing the controlled BIO.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx =
        assert(tls_context.connect(client, socks[1]:fd(), CLIENT_CONFIG))
    local peer = tls_inet.Client(socks[1], ctx)
    assert.not_nil(peer.tls_bio)

    local bio = peer.tls_bio
    local ncall = 0
    peer.tls_bio = {
        drain = function()
            ncall = ncall + 1
            if ncall == 1 then
                -- partial drain: some bytes moved, socket now full
                return 4096, nil, true
            end
            -- after wait_writable the rest drains completely
            return 8192
        end,
    }

    local waited = false
    peer.wait_writable = function(_, sec)
        assert(type(sec) == 'number', 'remaining sec must be a number')
        waited = true
        return true
    end

    local ok = peer:bio_drain()
    assert.is_true(ok)
    assert.is_true(waited)
    assert.equal(ncall, 2)

    peer.tls_bio = bio
    peer:close()
    socks[2]:close()
end

function testcase.poll_wait_without_timeout_does_not_crash()
    -- poll_wait without sec must materialize a deadline from the want
    -- direction (WANT_POLLOUT -> sndtimeo, WANT_POLLIN -> rcvtimeo via
    -- bio_drain) instead of passing nil down to the EAGAIN path.
    -- These methods only exercise BIO retry/deadline logic; no TLS exchange
    -- or child process is required before installing the controlled BIO.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx =
        assert(tls_context.connect(client, socks[1]:fd(), CLIENT_CONFIG))
    local peer = tls_inet.Client(socks[1], ctx)
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')

    local bio = peer.tls_bio
    local again = errno.new('EAGAIN')
    peer.tls_bio = {
        drain = function()
            return nil, again, true
        end,
    }

    local sentinel = errno.new('ECANCELED', 'test-sentinel')
    peer.wait_writable = function(_, sec)
        assert(type(sec) == 'number', 'remaining sec must be a number')
        return false, sentinel
    end

    -- WANT_POLLOUT takes the bio_drain path directly
    local ok, err = peer:poll_wait(tls_context.WANT_WRITE)
    assert.is_false(ok)
    assert.equal(err, sentinel)

    -- WANT_POLLIN drains pending record(s) first, so the same stub covers
    -- the recv-direction deadline selection
    ok, err = peer:poll_wait(tls_context.WANT_READ)
    assert.is_false(ok)
    assert.equal(err, sentinel)

    peer.tls_bio = bio
    peer:close()
    socks[2]:close()
end

function testcase.close_bio_after_peer_close_notify()
    -- Regression: once the peer's close_notify has been received,
    -- SSL_shutdown() completes immediately, but the TX BIO still holds the
    -- final close_notify ciphertext.  close() must drain it to the socket
    -- and succeed instead of failing with EINVAL on the freed BIO.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                tlscfg = {
                    verify_name = CLIENT_CONFIG.verify_name,
                    verify_time = CLIENT_CONFIG.verify_time,
                    verify_cert = CLIENT_CONFIG.verify_cert,
                },
            }))
            assert(c:write(msg))
            -- wait for the server to close first so the peer's close_notify is
            -- already received when we close
            local r, err, timeout = c:read()
            assert.is_nil(r)
            assert.is_nil(err)
            assert.is_nil(timeout)
            assert(c:close(), 'close after peer close_notify must succeed')
        end)
    end
    local peer = assert(s:accept())
    assert.equal(peer:read(), msg)
    -- the initiator path (SSL_shutdown == 0 -> drain -> retry) must also
    -- succeed
    assert(peer:close(), 'initiator close must succeed')
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.close_bio_idempotent()
    -- close() must be idempotent: the second call disposes nothing extra
    -- and must not touch the already-freed BIO.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c = assert(inet.client.new(host, port, {
        tlscfg = {
            verify_name = CLIENT_CONFIG.verify_name,
            verify_time = CLIENT_CONFIG.verify_time,
            verify_cert = CLIENT_CONFIG.verify_cert,
        },
    }))
    assert(c.tls_bio ~= nil, 'BIO not set on client')
    -- closing before the handshake must also succeed and be idempotent
    assert(c:close())
    assert(c:close())
    s:close()
end
