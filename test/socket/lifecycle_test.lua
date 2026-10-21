local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local fileno = require('io.fileno')
local UNWRAPPED_FD
local EXTERNALLY_CLOSED_SOCKET

function testcase.after_each()
    if EXTERNALLY_CLOSED_SOCKET then
        -- Discard stale ownership without closing a possibly reused fd.
        EXTERNALLY_CLOSED_SOCKET:unwrap()
        EXTERNALLY_CLOSED_SOCKET = nil
    end
    if UNWRAPPED_FD then
        socket.close(UNWRAPPED_FD)
        UNWRAPPED_FD = nil
    end
end

function testcase.cloexec()
    -- FD_CLOEXEC controls whether the fd is closed on exec().
    --
    -- Fresh sockets have FD_CLOEXEC set. Toggle it off and back on via
    -- F_SETFD; a stale fd surfaces EBADF via F_GETFD.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.is_true(s:cloexec())
    local prev, opt_err = s:cloexec(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:cloexec()
    assert.is_false(value)
    assert.is_nil(get_err)
    prev, opt_err = s:cloexec(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    value, get_err = s:cloexec()
    assert.is_true(value)
    assert.is_nil(get_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local ok, err = s:cloexec()
    assert.is_nil(ok)
    assert.equal(err.type, errno.EBADF)
end

function testcase.nonblock()
    -- O_NONBLOCK controls whether IO on the fd blocks or returns EAGAIN.
    --
    -- Fresh sockets have O_NONBLOCK set. Toggle it off and back on via
    -- F_SETFL; a stale fd surfaces EBADF via F_GETFL.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.is_true(s:nonblock())
    local prev, opt_err = s:nonblock(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:nonblock()
    assert.is_false(value)
    assert.is_nil(get_err)
    prev, opt_err = s:nonblock(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    value, get_err = s:nonblock()
    assert.is_true(value)
    assert.is_nil(get_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local ok, err = s:nonblock()
    assert.is_nil(ok)
    assert.equal(err.type, errno.EBADF)
end

function testcase.protocol()
    -- protocol() returns the socket's protocol name.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(s:protocol(), 'tcp')
    s:close()
end

function testcase.tostring()
    -- tostring(sock) returns a string like "net.socket: 0x...".
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.match(tostring(s), '^net.socket: ', false)
    s:close()
end

function testcase.dup_on_closed_socket()
    -- test that dup() on a closed socket returns nil + EBADF rather than
    -- silently succeeding.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local dup, err = s:dup()
    assert.is_nil(dup)
    assert(err)
    assert.equal(err.type, errno.EBADF)
end

function testcase.dup_on_stale_fd()
    -- A closed positive fd on a still-live userdata makes dup() fail
    -- with EBADF, without marking the userdata itself as closed.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local d, err = s:dup()
    assert.is_nil(d)
    assert.equal(err.type, errno.EBADF)
end

function testcase.dup()
    -- dup() returns a different fd referring to the same socket, with
    -- independent ownership and preserved family / socktype attributes.
    local s = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local addr = assert(s:getsockname())
    local dup = assert(s:dup())
    assert(dup:fd() ~= s:fd())
    assert.equal(dup:family(), s:family())
    assert.equal(dup:socktype(), s:socktype())
    assert.is_true(dup:cloexec())
    assert(s:close())
    local copied_addr = assert(dup:getsockname())
    assert.equal(copied_addr:addr(), addr:addr())
    assert.equal(copied_addr:port(), addr:port())
    dup:close()
end

function testcase.wrap_non_socket_fd()
    -- test that socket.wrap on a regular file fd surfaces
    -- getsockname's ENOTSOCK error rather than crashing.
    local f = assert(io.tmpfile())
    local s, err = socket.wrap(fileno(f))
    assert.is_nil(s)
    assert(err, 'wrap on a non-socket fd should return an error')
    assert.equal(err.type, errno.ENOTSOCK)
    f:close()
end

function testcase.wrap_invalid_fd()
    -- test that socket.wrap on a closed / invalid fd surfaces EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = s:unwrap()
    assert(socket.close(fd))
    local wrapped, err = socket.wrap(fd)
    assert.is_nil(wrapped)
    assert(err)
    assert.equal(err.type, errno.EBADF)
end

function testcase.wrap()
    -- socket.wrap() takes a raw fd (typically from unwrap() or a foreign
    -- system-call) and returns a new socket userdata that owns it.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = s:unwrap()
    UNWRAPPED_FD = fd
    local wrapped = assert(socket.wrap(fd))
    UNWRAPPED_FD = nil
    assert.equal(wrapped:family(), 'inet')
    wrapped:close()
end

function testcase.wrap_sets_cloexec_and_nonblock()
    -- The documented contract for socket.wrap(fd) is that the adopted fd
    -- inherits both FD_CLOEXEC and O_NONBLOCK regardless of its prior
    -- state.  Forge a raw fd whose FD_CLOEXEC is deliberately cleared and
    -- verify wrap() re-applies both flags -- a foreign fd handed to wrap
    -- must not leak into child processes on subsequent exec().
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:cloexec(false))
    assert.is_false(s:cloexec())
    assert(s:nonblock(false))
    assert.is_false(s:nonblock())

    local fd = s:unwrap()
    UNWRAPPED_FD = fd
    local wrapped = assert(socket.wrap(fd))
    UNWRAPPED_FD = nil
    assert.is_true(wrapped:cloexec())
    assert.is_true(wrapped:nonblock())
    wrapped:close()
end

function testcase.unwrap_returns_fd_and_disables_socket()
    -- unwrap() returns the original fd and removes the userdata's metatable.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local original_fd = s:fd()
    local fd = s:unwrap()
    UNWRAPPED_FD = fd
    assert.is_int(fd)
    assert.equal(fd, original_fd)
    assert.is_nil(getmetatable(s))
    assert(socket.close(fd))
    UNWRAPPED_FD = nil
end

function testcase.close_shutdown_and_close_both_fail()
    -- socket.close(fd, how) calls shutdown() then close().  When the fd has
    -- already been closed, both syscalls fail with EBADF and closefd() must
    -- surface the chained error: the top-level error carries the close(2)
    -- failure and its `wrap` field carries the shutdown(2) failure.  A
    -- previous assertion of just `assert(err)` accepted any truthy value and
    -- would not have detected a regression that dropped the chained
    -- shutdown error or mislabelled either op.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = s:unwrap()
    assert(socket.close(fd))

    local ok, err = socket.close(fd, 'rd')
    assert.is_false(ok)
    assert(err, 'closefd() must return an error object when both syscalls fail')
    assert.equal(err.op, 'close')
    assert.equal(err.type, errno.EBADF)
    assert(err.wrap,
           'closefd() must attach the shutdown failure to err.wrap when both fail')
    assert.equal(err.wrap.op, 'shutdown')
    assert.equal(err.wrap.type, errno.EBADF)
end

function testcase.close_with_shutdown_error()
    -- socket.close(fd, how) performs shutdown(how) followed by close(fd).
    -- shutdown(2) on a socket that has never been connected fails with
    -- ENOTCONN, but close(2) still succeeds; closefd() must therefore return
    -- (false, ENOTCONN-from-shutdown), NOT the errno that happens to remain
    -- in the thread after close(2) returned successfully.
    --
    -- The previous assertion `assert(rv or err)` was trivially satisfied by
    -- the non-nil error alone and did not verify that the reported errno
    -- was the one shutdown(2) had recorded.  This regression asserts on the
    -- concrete type / op so a future refactor cannot silently swap the
    -- reported errno for whatever value happened to sit in `errno` after
    -- close(2).
    local closed = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = closed:unwrap()
    UNWRAPPED_FD = fd

    local rv, err = socket.close(fd, 'rd')
    -- Check before any new fd can reuse this number; also clean up a leak.
    local close_ok, close_err = socket.close(fd)
    UNWRAPPED_FD = nil
    assert.is_false(rv)
    assert(err, 'closefd() must return an error when shutdown(2) fails')
    assert.equal(err.op, 'shutdown')
    assert.equal(err.type, errno.ENOTCONN)
    assert.is_nil(err.wrap)
    assert.is_false(close_ok)
    assert.equal(close_err.type, errno.EBADF)
end

function testcase.shutdown_invalid_flags()
    -- The `how` argument to shutdown() (both the method form and the
    -- static socket.shutdown(fd, how) form) must be one of the strings
    -- "rd", "wr", "rdwr".  Non-strings and unknown strings are rejected
    -- by checkshutflag() with a diagnostic Lua error.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local err = assert.throws(function()
        socks[1]:shutdown(1)
    end)
    assert.match(err, 'how must be string', false)

    err = assert.throws(function()
        socks[1]:shutdown('invalid')
    end)
    assert.match(err, 'not a recognized shutdown direction', false)

    err = assert.throws(function()
        socket.shutdown(socks[1]:fd(), 1)
    end)
    assert.match(err, 'how must be string', false)

    socks[1]:close()
    socks[2]:close()
end

function testcase.shutdown()
    -- Method write shutdown sends EOF to the peer without closing reads.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    local ok, err = a:shutdown('wr')
    assert.is_true(ok)
    assert.is_nil(err)
    local data, again
    data, err, again = b:read()
    assert.is_nil(data)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(b:write('x'), 1)
    assert(a:recvable(1))
    assert.equal(a:read(1), 'x')
    a:close()
    b:close()

    -- Static read shutdown produces local EOF without closing writes.
    socks = assert(socket.pair({
        socktype = 'stream',
    }))
    a, b = socks[1], socks[2]
    ok, err = socket.shutdown(b:fd(), 'rd')
    assert.is_true(ok)
    assert.is_nil(err)
    data, err, again = b:read()
    assert.is_nil(data)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(b:write('y'), 1)
    assert(a:recvable(1))
    assert.equal(a:read(1), 'y')
    a:close()
    b:close()
end

function testcase.shutdown_on_closed_socket()
    -- shutdown() on a closed socket returns (false, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local ok, err = s:shutdown('rd')
    assert.is_false(ok)
    assert.equal(err.type, errno.EBADF)
end
