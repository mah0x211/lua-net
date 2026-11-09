local support = require('test.tls.stream.inet.helpers').new()
local testcase = require('testcase')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local socketpair = require('testcase.socketpair')
local wait = require('io.wait')
local assert = require('assert')
local socket = require('net.socket')
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

function testcase.read_reports_error_on_half_close_without_close_notify()
    -- Socket:read must distinguish how the peer ended the connection: a
    -- peer that shuts its write side down (FIN) without a close_notify
    -- surfaces OpenSSL's unexpected-EOF error instead of a clean EOF.
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
    local parent_signal, child_signal = assert(socketpair())

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            parent_signal:close()

            local c = assert(inet.client.new(host, port, {
                servername = 'www.example.com',
                tlscfg = CLIENT_CONFIG,
            }))
            assert(c:send('hello'))
            assert(wait.readable(child_signal:fd(), 1))
            assert.equal(child_signal:read(), 'hello received')
            assert(c:send('world'))
            -- half-close: FIN without a close_notify
            assert(socket.shutdown(c:fd(), 'wr'))
            -- Keep the half-closed connection alive until the parent
            -- has observed unexpected EOF without a close_notify.
            assert(wait.readable(child_signal:fd(), 1))
            assert.equal(child_signal:read(), 'EOF received')
            child_signal:close()
        end)
    end

    child_signal:close()
    local peer = assert(s:accept())
    -- bound the reads: without the EOF classification the third read would
    -- spin until this deadline and report a bare timeout
    assert(peer:rcvtimeo(1))
    assert.equal(peer:recv(), 'hello')
    assert(parent_signal:write('hello received'))
    assert.equal(peer:recv(), 'world')
    local rv, err = peer:recv()
    assert.is_nil(rv)
    assert.not_nil(err)
    assert(parent_signal:write('EOF received'))
    parent_signal:close()
    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.read_reports_clean_eof_on_close_notify()
    -- A peer that closes gracefully (close_notify via Socket:close, which
    -- shuts the TLS layer down first) reads back as a clean EOF (nil, nil)
    -- on the other end - the counterpart of the half-close error above.
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

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                servername = 'www.example.com',
                tlscfg = {
                    verify_name = CLIENT_CONFIG.verify_name,
                    verify_time = CLIENT_CONFIG.verify_time,
                    verify_cert = CLIENT_CONFIG.verify_cert,
                },
            }))
            assert(c:send('bye'))
            -- the server closes gracefully; its close_notify must surface as
            -- a clean EOF here, not an error
            assert(c:rcvtimeo(1))
            local rv, err, timeout = c:recv()
            assert.is_nil(rv)
            assert.is_nil(err)
            assert.is_nil(timeout)
            assert(c:close())
        end)
    end

    local peer = assert(s:accept())
    assert(peer:rcvtimeo(1))
    assert.equal(peer:recv(), 'bye')
    -- graceful close: close() shuts the TLS layer down (close_notify)
    -- before disposing the fd
    assert(peer:close())
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.read_shares_rcvtimeo_with_first_handshake()
    -- Before the fix, a read that triggered the initial handshake let the
    -- handshake take its own sndtimeo budget instead of respecting the
    -- caller's rcvtimeo.  With rcvtimeo=1s and sndtimeo=5s a handshake
    -- against a silent peer used to block for ~5s; now it must timeout
    -- within rcvtimeo.
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

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            -- open a plain TCP socket to the TLS server and never send
            -- anything.  The peer will start the TLS handshake wait; from
            -- the server side we call read() with a short rcvtimeo and a
            -- longer sndtimeo -- read must honour rcvtimeo.
            local plain = require('net.stream.inet')
            local raw = assert(plain.client.new(host, port))
            raw:read(nil, 5) -- keep the connection alive without sending
            raw:close()
        end)
    end
    local peer = assert(s:accept())
    assert(peer:rcvtimeo(1))
    assert(peer:sndtimeo(5))

    local gettime = require('time.clock').gettime
    local t0 = gettime()
    local msg, err, timeout = peer:read()
    local elapsed = gettime() - t0

    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(timeout)
    -- the bug honoured sndtimeo (5s) instead of rcvtimeo (1s); allow
    -- generous scheduling jitter for the correct behaviour while staying
    -- clear of the buggy one
    assert(elapsed < 3,
           string.format(
               'read took %.3fs, expected within rcvtimeo (1s) plus' ..
                   ' scheduling jitter; bug allowed up to sndtimeo (5s)',
               elapsed))

    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end
