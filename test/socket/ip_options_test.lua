local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local socket = require('net.socket')

local EXTERNALLY_CLOSED_SOCKET

function testcase.after_each()
    if EXTERNALLY_CLOSED_SOCKET then
        -- Discard stale ownership without closing a possibly reused fd.
        EXTERNALLY_CLOSED_SOCKET:unwrap()
        EXTERNALLY_CLOSED_SOCKET = nil
    end
end

function testcase.ip_recvttl()
    -- IP_RECVTTL requests the sender TTL as ancillary data on recvmsg().
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, opt_err = s:ip_recvttl(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:ip_recvttl()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:ip_recvttl(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:ip_recvttl()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF from the initial getsockopt call in either operation.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:ip_recvttl()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:ip_recvttl(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.ip_recvtos()
    -- IP_RECVTOS requests the sender IPv4 TOS byte as ancillary data.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, opt_err = s:ip_recvtos(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:ip_recvtos()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:ip_recvtos(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:ip_recvtos()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF from the initial getsockopt call in either operation.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:ip_recvtos()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:ip_recvtos(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.broadcast()
    -- SO_BROADCAST permits sending to the IPv4 limited-broadcast address.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    local s = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local prev, opt_err = s:broadcast(true)
    assert.is_false(prev)
    assert.is_nil(opt_err)
    local value, get_err = s:broadcast()
    assert.is_true(value)
    assert.is_nil(get_err)
    prev, opt_err = s:broadcast(false)
    assert.is_true(prev)
    assert.is_nil(opt_err)
    value, get_err = s:broadcast()
    assert.is_false(value)
    assert.is_nil(get_err)

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF from the initial getsockopt call in either operation.
    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:broadcast()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:broadcast(true)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.ipv6_recvhoplimit()
    -- IPV6_RECVHOPLIMIT requests the sender IPv6 hop-limit as ancillary
    -- data on recvmsg().
    local s = assert(socket.new_inet6({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, err = s:ipv6_recvhoplimit(true)
    assert.is_false(prev)
    assert.is_nil(err)
    local enabled
    enabled, err = s:ipv6_recvhoplimit()
    assert.is_true(enabled)
    assert.is_nil(err)
    prev, err = s:ipv6_recvhoplimit(false)
    assert.is_true(prev)
    assert.is_nil(err)
    enabled, err = s:ipv6_recvhoplimit()
    assert.is_false(enabled)
    assert.is_nil(err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    enabled, err = s:ipv6_recvhoplimit()
    assert.is_nil(enabled)
    assert(error_is(err, errno.EBADF))
    enabled, err = s:ipv6_recvhoplimit(true)
    assert.is_nil(enabled)
    assert(error_is(err, errno.EBADF))
end
