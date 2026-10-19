local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local rlimit = require('testcase.rlimit')

local EXTERNALLY_CLOSED_SOCKET

function testcase.after_each()
    if EXTERNALLY_CLOSED_SOCKET then
        -- Discard stale ownership without closing a possibly reused fd.
        EXTERNALLY_CLOSED_SOCKET:unwrap()
        EXTERNALLY_CLOSED_SOCKET = nil
    end
end

function testcase.atmark()
    -- atmark() returns false when the socket has no pending OOB data.
    local socks = assert(socket.pair({
        socktype = 'stream',
        protocol = 'auto',
    }))
    assert.is_false(socks[1]:atmark())
    socks[1]:close()
    socks[2]:close()

    -- atmark() on a stale (externally-closed) fd surfaces an error via
    -- sockatmark() EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:atmark()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.sendable_recvable_basic()
    -- sendable(sec) / recvable(sec) block for up to `sec` seconds and
    -- return (true) once the socket is writable / readable, or (false,
    -- nil, true) on timeout.  On a fresh stream pair the send side is
    -- immediately writable and the recv side times out.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- immediate readiness (sec = 0)
    local ok, err, timeout = a:sendable(0)
    assert.is_true(ok)
    assert.is_nil(err)
    assert.is_nil(timeout)

    -- readiness with a positive timeout branch: nothing is pending so
    -- recvable should time out.
    ok, err, timeout = b:recvable(0.001)
    assert.is_false(ok)
    assert.is_nil(err)
    assert.is_true(timeout)

    assert.equal(a:write('x'), 1)
    ok, err, timeout = b:recvable(1)
    assert.is_true(ok)
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.equal(b:read(1), 'x')
    a:close()
    b:close()
end

function testcase.sendable_recvable_on_stale_fd()
    -- Force poll_lua's POLLNVAL branch (EBADF):
    -- 1. create a real socket, then externally close its fd via
    --    socket.close(fd) so the userdata still holds a numerically valid
    --    but kernel-closed fd
    -- 2. sendable/recvable then invoke poll() on that stale fd and get
    --    POLLNVAL, which is surfaced as EBADF
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = s:fd()
    assert(socket.close(fd))
    EXTERNALLY_CLOSED_SOCKET = s

    local rv, err, timeout = s:sendable(0)
    assert.is_false(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
    rv, err, timeout = s:recvable(0)
    assert.is_false(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
    rv, err, timeout = s:sendable(0, true)
    assert.is_false(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
    rv, err, timeout = s:recvable(0, true)
    assert.is_false(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
end

function testcase.sendable_recvable_on_closed_socket()
    -- sendable/recvable both go through poll_lua.  A socket closed via
    -- close() has fd == -1 and must surface EBADF, matching the POLLNVAL
    -- result poll(2) reports for an externally closed fd: the two closed
    -- states carry the same meaning and must not be distinguished by
    -- whether the descriptor number is still stored.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err, timeout = s:sendable(0)
    assert.is_false(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
    rv, err, timeout = s:recvable(0)
    assert.is_false(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
end

local HIGH_FD_TARGET = 1030
local limit = assert(rlimit('nofile'))

if limit.cur == -1 or limit.cur >= HIGH_FD_TARGET + 2 then
    function testcase.sendable_recvable_supports_high_fd_values()
        -- Both tested descriptors must exceed the historical fd_set limit.
        -- Keep every acquired socket until verification, and release all of
        -- them before reporting any failure, including descriptor exhaustion.
        local hoard = {}
        local ok, err = pcall(function()
            local a, b
            for _ = 1, HIGH_FD_TARGET do
                local socks = assert(socket.pair({
                    socktype = 'stream',
                }))
                hoard[#hoard + 1] = socks[1]
                hoard[#hoard + 1] = socks[2]
                if math.min(socks[1]:fd(), socks[2]:fd()) >= HIGH_FD_TARGET then
                    a, b = socks[1], socks[2]
                    break
                end
            end
            assert(a and b, 'could not obtain two high descriptors')
            assert(a:fd() >= HIGH_FD_TARGET)
            assert(b:fd() >= HIGH_FD_TARGET)
            local ready, poll_err, timeout = a:sendable(0)
            assert.is_true(ready)
            assert.is_nil(poll_err)
            assert.is_nil(timeout)
            ready, poll_err, timeout = b:recvable(0.001)
            assert.is_false(ready)
            assert.is_nil(poll_err)
            assert.is_true(timeout)
            assert.equal(a:write('x'), 1)
            ready, poll_err, timeout = b:recvable(1)
            assert.is_true(ready)
            assert.is_nil(poll_err)
            assert.is_nil(timeout)
            assert.equal(b:read(1), 'x')
        end)
        for _, s in ipairs(hoard) do
            s:close()
        end
        assert(ok, err)
    end
else
    io.stderr:write('skip: sendable_recvable_supports_high_fd_values ' ..
                        'requires RLIMIT_NOFILE >= 1032\n')
end
