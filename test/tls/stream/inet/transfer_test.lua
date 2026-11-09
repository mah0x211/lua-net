local support = require('test.tls.stream.inet.helpers').new()
local testcase = require('testcase')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local socketpair = require('testcase.socketpair')
local shutdown = require('testcase.shutdown')
local assert = require('assert')
local error_is = require('error').is
local errno = require('errno')
local inet = require('net.stream.inet')
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

function testcase.write_read()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = get_server_config(),
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    -- test that communicates with write and read
    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                tlscfg = CLIENT_CONFIG,
            }))

            assert.not_nil(c.tls_bio)
            assert(c:write(msg))

            -- the client sees the server certificate after the handshake
            assert.re_match(c:get_peer_cert(), '^-----BEGIN CERTIFICATE')

            -- wait for peer to close
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)
    assert.not_nil(peer.tls_bio)

    local rcv = assert(peer:read())
    assert.equal(rcv, msg)

    -- the negotiation getters are reachable through the stream socket; the
    -- server sees no peer certificate because the client presented none
    assert.re_match(peer:get_version(), '^TLSv1\\.[23]$')
    assert.re_match(peer:get_cipher(), '^TLS_')
    assert.is_nil(peer:get_peer_cert())

    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.send_recv()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = get_server_config(),
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    -- test that communicates with send and recv
    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                tlscfg = CLIENT_CONFIG,
            }))

            assert(c:send(msg))

            -- wait for peer to close
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)

    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendmsg_recvmsg()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = get_server_config(),
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    -- test that sendmsg and recvmsg are not supported
    local len, err = c:sendmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = c:recvmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    len, err = peer:sendmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = peer:recvmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.write_read_bio_large_payload()
    -- SSL_MODE_ENABLE_PARTIAL_WRITE is enabled on the client SSL_CTX, so a
    -- plaintext payload larger than a single TLS record is delivered in
    -- multiple SSL_write returns.  The client-side write wrapper must loop
    -- on the "partial" indication until every byte reaches the peer.  A
    -- 32 KiB payload spans two records and reliably exercises the partial
    -- path without exhausting the SO_SNDBUF / SO_RCVBUF of the loopback
    -- socket pair.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = string.rep('X', 32 * 1024)

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
            assert(c.tls_bio ~= nil, 'BIO not set on client')
            assert(c:write(msg))
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on server peer')

    local buf = {}
    local total = 0
    while total < #msg do
        local chunk = peer:read()
        if not chunk then
            break
        end
        buf[#buf + 1] = chunk
        total = total + #chunk
    end
    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
    assert.equal(total, #msg)
    assert.equal(table.concat(buf), msg)
end

function testcase.read_returns_data_with_pending_txbuf()
    -- A read() whose SSL_read succeeded must return the received string
    -- even when draining the TX BIO would fail.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = get_server_config().cert,
            key = get_server_config().key,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local ping = 'ping'
    local parent_signal, child_signal = assert(socketpair())

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            parent_signal:close()
            local c = assert(inet.client.new(host, port, {
                tlscfg = {
                    verify_name = CLIENT_CONFIG.verify_name,
                    verify_time = CLIENT_CONFIG.verify_time,
                    verify_cert = CLIENT_CONFIG.verify_cert,
                },
            }))
            assert(c:handshake())
            assert(child_signal:read())
            child_signal:close()
            assert(c:write(ping))
            c:read()
            c:close()
        end)
    end

    child_signal:close()
    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')
    assert(peer:rcvtimeo(3))
    assert(peer:handshake())
    -- The low-level write queues ciphertext without draining it to the fd.
    assert.equal(peer.tls:write('reply'), 5)
    local _, pending = peer.tls_bio:peek()
    assert.greater(pending, 0)
    assert(parent_signal:write('x'))
    parent_signal:close()
    assert(peer:bio_fill())
    assert(shutdown(peer:fd(), 'wr'))
    local drained, drain_err = peer.tls_bio:drain()
    assert.is_nil(drained)
    assert.equal(drain_err.type, errno.EPIPE)

    local got = peer:read()
    assert.is_string(got)
    assert.equal(got, ping)

    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.write_drain_error_keeps_sent()
    -- Go-style contract: when the TX BIO drain fails after OpenSSL
    -- accepted the plaintext, write() must report the accepted byte
    -- count with (sent, err) instead of discarding it with nil —
    -- re-sending accepted plaintext would duplicate it on the wire.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        sndbuf = 2048,
        rcvbuf = 2048,
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
                sndbuf = 2048,
                rcvbuf = 2048,
                tlscfg = {
                    verify_name = CLIENT_CONFIG.verify_name,
                    verify_time = CLIENT_CONFIG.verify_time,
                    verify_cert = CLIENT_CONFIG.verify_cert,
                },
            }))
            -- Complete the handshake and keep the peer alive while the
            -- server tests its locally shut-down write direction.
            assert(c:write('ping'))
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')
    assert.equal(peer:read(), 'ping')
    assert(shutdown(peer:fd(), 'wr'))

    -- One TLS record is accepted into the memory BIO, then its drain
    -- deterministically fails with EPIPE. A zero sent count is incorrect.
    local sent, err, timeout = peer:write(msg)
    assert.equal(sent, #msg)
    assert.equal(err.type, errno.EPIPE)
    assert.is_nil(timeout)

    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end
