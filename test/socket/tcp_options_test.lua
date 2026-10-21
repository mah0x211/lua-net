local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local errno = require('errno')

local EXTERNALLY_CLOSED_SOCKET

function testcase.after_each()
    if EXTERNALLY_CLOSED_SOCKET then
        -- The fd is already closed; discard stale ownership without closing
        -- a descriptor that may since have been reused.
        EXTERNALLY_CLOSED_SOCKET:unwrap()
        EXTERNALLY_CLOSED_SOCKET = nil
    end
end

function testcase.tcpcork()
    -- TCP_CORK / TCP_NOPUSH batches small writes into full-sized segments.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, opt_err = s:tcpcork(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:tcpcork()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:tcpcork(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:tcpcork()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:tcpcork()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:tcpcork(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.tcpnodelay()
    -- TCP_NODELAY disables the Nagle algorithm for latency-sensitive traffic.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, opt_err = s:tcpnodelay(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:tcpnodelay()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:tcpnodelay(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:tcpnodelay()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:tcpnodelay()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:tcpnodelay(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.tcpkeepalive()
    -- TCP_KEEPALIVE / TCP_KEEPIDLE sets the idle time before keepalive probes.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local before, opt_err = s:tcpkeepalive()
    assert.is_number(before)
    assert.is_nil(opt_err)
    local prev
    prev, opt_err = s:tcpkeepalive(60)
    assert.equal(prev, before)
    assert.is_nil(opt_err)
    local value
    value, opt_err = s:tcpkeepalive()
    assert.equal(value, 60)
    assert.is_nil(opt_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:tcpkeepalive()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:tcpkeepalive(60)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.tcpkeepcnt()
    -- TCP_KEEPCNT sets the maximum number of unacked keepalive probes.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local before, opt_err = s:tcpkeepcnt()
    assert.is_number(before)
    assert.is_nil(opt_err)
    local prev
    prev, opt_err = s:tcpkeepcnt(3)
    assert.equal(prev, before)
    assert.is_nil(opt_err)
    local value
    value, opt_err = s:tcpkeepcnt()
    assert.equal(value, 3)
    assert.is_nil(opt_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:tcpkeepcnt()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:tcpkeepcnt(3)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.tcpkeepintvl()
    -- TCP_KEEPINTVL sets the interval between keepalive probes.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local before, opt_err = s:tcpkeepintvl()
    assert.is_number(before)
    assert.is_nil(opt_err)
    local prev
    prev, opt_err = s:tcpkeepintvl(30)
    assert.equal(prev, before)
    assert.is_nil(opt_err)
    local value
    value, opt_err = s:tcpkeepintvl()
    assert.equal(value, 30)
    assert.is_nil(opt_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:tcpkeepintvl()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:tcpkeepintvl(30)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end
