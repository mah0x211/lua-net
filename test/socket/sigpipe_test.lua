local testcase = require('testcase')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local signal = require('testcase.signal')
local assert = require('assert')
local socket = require('net.socket')
local errno = require('errno')

function testcase.send_survives_sigpipe_after_shutdown_wr()
    -- Writing after the local write direction is shut down must surface
    -- EPIPE as a Lua error object, not kill the process with SIGPIPE.
    -- The child runs with SIGPIPE at its default disposition so the
    -- runner's SIGPIPE ignore cannot mask the behaviour; the parent
    -- detects a SIGPIPE death via the wait status.
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            assert(signal.sigdefault('SIGPIPE'))
            local socks = assert(socket.pair({
                socktype = 'stream',
            }))
            assert(socks[1]:shutdown('wr'))
            local sent, err = socks[1]:send('x')
            assert.is_nil(sent)
            assert.equal(err.type, errno.EPIPE)
        end)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.write_survives_sigpipe_after_shutdown_wr()
    -- Same as send_survives_sigpipe_after_shutdown_wr, but through the
    -- plain write() path.
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            assert(signal.sigdefault('SIGPIPE'))
            local socks = assert(socket.pair({
                socktype = 'stream',
            }))
            assert(socks[1]:shutdown('wr'))
            local n, err = socks[1]:write('x')
            assert.is_nil(n)
            assert.equal(err.type, errno.EPIPE)
        end)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendmsg_survives_sigpipe_after_shutdown_wr()
    -- Same as send_survives_sigpipe_after_shutdown_wr, but through the
    -- sendmsg() path.
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            assert(signal.sigdefault('SIGPIPE'))
            local socks = assert(socket.pair({
                socktype = 'stream',
            }))
            assert(socks[1]:shutdown('wr'))
            local sent, err = socks[1]:sendmsg('x')
            assert.is_nil(sent)
            assert.equal(err.type, errno.EPIPE)
        end)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.wrap_send_survives_sigpipe_after_shutdown_wr()
    -- Re-wrapping an already protected socket preserves SIGPIPE safety.
    -- This does not test adoption of an initially unprotected descriptor.
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            assert(signal.sigdefault('SIGPIPE'))
            local socks = assert(socket.pair({
                socktype = 'stream',
            }))
            local fd = assert(socks[1]:unwrap())
            local s = assert(socket.wrap(fd))
            assert(s:shutdown('wr'))
            local sent, err = s:send('x')
            assert.is_nil(sent)
            assert.equal(err.type, errno.EPIPE)
        end)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.accept_send_survives_sigpipe_after_shutdown_wr()
    -- Sockets obtained via accept() must be as SIGPIPE-safe as paired
    -- ones.
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            assert(signal.sigdefault('SIGPIPE'))
            local server = assert(socket.bind_inet('127.0.0.1', 0, {
                socktype = 'stream',
                protocol = 'tcp',
                reuseaddr = true,
            }))
            assert(server:listen())
            local ai = assert(server:getsockname())
            local client = assert(socket.connect_inet('127.0.0.1', ai:port(), {
                socktype = 'stream',
                protocol = 'tcp',
            }))
            assert(server:recvable(1))
            local peer = assert(server:accept())
            assert(peer:shutdown('wr'))
            local sent, err = peer:send('x')
            assert.is_nil(sent)
            assert.equal(err.type, errno.EPIPE)
            client:close()
        end)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end
