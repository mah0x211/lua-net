local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')

local uname = assert(io.popen('uname -s'))
local OS = assert(uname:read('*l'))
assert(uname:close())

-- Linux reports twice the requested SO_RCVBUF/SO_SNDBUF size.
local BUFFER_SIZE = OS == 'Linux' and 8192 or 4096

local EXTERNALLY_CLOSED_SOCKET

function testcase.after_each()
    if EXTERNALLY_CLOSED_SOCKET then
        -- The fd is already closed; discard stale ownership without closing
        -- a descriptor that may since have been reused.
        EXTERNALLY_CLOSED_SOCKET:unwrap()
        EXTERNALLY_CLOSED_SOCKET = nil
    end
end

function testcase.dontroute()
    -- SO_DONTROUTE bypasses the normal routing table for outbound datagrams.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, opt_err = s:dontroute(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:dontroute()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:dontroute(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:dontroute()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:dontroute()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:dontroute(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.keepalive()
    -- SO_KEEPALIVE enables periodic keepalive probes on connected stream sockets.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, opt_err = s:keepalive(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:keepalive()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:keepalive(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:keepalive()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:keepalive()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:keepalive(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.oobinline()
    -- SO_OOBINLINE places out-of-band data inline with normal recv() data.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, opt_err = s:oobinline(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:oobinline()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:oobinline(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:oobinline()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:oobinline()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:oobinline(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.reuseaddr()
    -- SO_REUSEADDR allows the local address to be reused when binding.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, opt_err = s:reuseaddr(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:reuseaddr()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:reuseaddr(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:reuseaddr()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:reuseaddr()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:reuseaddr(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.reuseport()
    -- SO_REUSEPORT allows multiple listeners on the same address/port pair.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, opt_err = s:reuseport(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:reuseport()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:reuseport(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:reuseport()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:reuseport()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:reuseport(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.timestamp()
    -- SO_TIMESTAMP delivers a timestamp cmsg with each recvmsg().
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local prev, opt_err = s:timestamp(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:timestamp()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:timestamp(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:timestamp()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:timestamp()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:timestamp(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.rcvbuf()
    -- SO_RCVBUF sets the receive buffer size hint.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local before, opt_err = s:rcvbuf()
    assert.is_number(before)
    assert.is_nil(opt_err)
    local prev
    prev, opt_err = s:rcvbuf(4096)
    assert.equal(prev, before)
    assert.is_nil(opt_err)
    local value
    value, opt_err = s:rcvbuf()
    assert.equal(value, BUFFER_SIZE)
    assert.is_nil(opt_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:rcvbuf()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:rcvbuf(4096)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.rcvlowat()
    -- SO_RCVLOWAT sets the low-water mark for recv/select readiness.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local before, opt_err = s:rcvlowat()
    assert.is_number(before)
    assert.is_nil(opt_err)
    local prev
    prev, opt_err = s:rcvlowat(2)
    assert.equal(prev, before)
    assert.is_nil(opt_err)
    local value
    value, opt_err = s:rcvlowat()
    assert.equal(value, 2)
    assert.is_nil(opt_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:rcvlowat()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:rcvlowat(1)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.sndbuf()
    -- SO_SNDBUF sets the send buffer size hint.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local before, opt_err = s:sndbuf()
    assert.is_number(before)
    assert.is_nil(opt_err)
    local prev
    prev, opt_err = s:sndbuf(4096)
    assert.equal(prev, before)
    assert.is_nil(opt_err)
    local value
    value, opt_err = s:sndbuf()
    assert.equal(value, BUFFER_SIZE)
    assert.is_nil(opt_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:sndbuf()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:sndbuf(4096)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

if OS == 'Linux' then
    function testcase.sndlowat_rejects_changes()
        -- Linux exposes a fixed SO_SNDLOWAT of 1 but rejects its setter.
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        local value, err = s:sndlowat()
        assert.equal(value, 1)
        assert.is_nil(err)
        value, err = s:sndlowat(1)
        assert.is_nil(value)
        assert(error_is(err, errno.ENOPROTOOPT))
        value, err = s:sndlowat()
        assert.equal(value, 1)
        assert.is_nil(err)

        assert(socket.close(s:fd()))
        EXTERNALLY_CLOSED_SOCKET = s
        value, err = s:sndlowat()
        assert.is_nil(value)
        assert(error_is(err, errno.EBADF))
        value, err = s:sndlowat(1)
        assert.is_nil(value)
        assert(error_is(err, errno.EBADF))
    end
else
    function testcase.sndlowat()
        -- The setter returns the previous low-water mark, not the new value.
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        local before, err = s:sndlowat()
        assert.is_number(before)
        assert.is_nil(err)
        local prev
        prev, err = s:sndlowat(1)
        assert.equal(prev, before)
        assert.is_nil(err)
        local value
        value, err = s:sndlowat()
        assert.equal(value, 1)
        assert.is_nil(err)

        assert(socket.close(s:fd()))
        EXTERNALLY_CLOSED_SOCKET = s
        value, err = s:sndlowat()
        assert.is_nil(value)
        assert(error_is(err, errno.EBADF))
        value, err = s:sndlowat(1)
        assert.is_nil(value)
        assert(error_is(err, errno.EBADF))
    end
end

function testcase.linger()
    -- SO_LINGER controls how close() handles unsent data on a stream socket.
    -- The Lua binding uses a signed integer to encode both the on/off flag
    -- and the linger interval in seconds:
    --  * value >= 0 : SO_LINGER on, l_linger = value seconds
    --  * value < 0  : SO_LINGER off (disabled)
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    -- Getter returns the current linger value; setters round-trip: a
    -- positive value enables SO_LINGER with that interval and a negative
    -- value disables it (read back as -1).
    local before, opt_err = s:linger()
    assert.is_int(before)
    assert.is_nil(opt_err)
    local prev
    prev, opt_err = s:linger(1)
    assert.equal(prev, before)
    assert.is_nil(opt_err)
    local value
    value, opt_err = s:linger()
    assert.equal(value, 1)
    assert.is_nil(opt_err)
    prev, opt_err = s:linger(-1)
    assert.equal(prev, 1)
    assert.is_nil(opt_err)
    value, opt_err = s:linger()
    assert.equal(value, -1)
    assert.is_nil(opt_err)

    -- A stale (externally-closed) fd causes both getter and setter to
    -- surface EBADF.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:linger()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:linger(1)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

if OS == 'Darwin' then
    function testcase.acceptconn_returns_enoprotoopt()
        -- macOS defines SO_ACCEPTCONN but does not expose it via getsockopt.
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        local enabled, err = s:acceptconn()
        assert.is_nil(enabled)
        assert(error_is(err, errno.ENOPROTOOPT))

        local ai = assert(addrinfo.inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
        }))
        assert(s:bind(ai))
        assert(s:listen())
        enabled, err = s:acceptconn()
        assert.is_nil(enabled)
        assert(error_is(err, errno.ENOPROTOOPT))
        s:close()
    end
else
    function testcase.acceptconn()
        -- SO_ACCEPTCONN is converted to a boolean by the Lua binding.
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        -- A non-listening socket reports false without an error.
        local enabled, err = s:acceptconn()
        assert.is_false(enabled)
        assert.is_nil(err)
        local ai = assert(addrinfo.inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
        }))
        assert(s:bind(ai))
        assert(s:listen())
        -- A listening socket reports true without an error.
        enabled, err = s:acceptconn()
        assert.is_true(enabled)
        assert.is_nil(err)
        s:close()
    end
end
