local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')

function testcase.recvmsg_empty_input()
    -- recvmsg() with neither bufsize nor cmsgbuf surfaces EINVAL.  A
    -- negative bufsize or cmsgbuf is rejected as a Lua argument error.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- test that recvmsg with neither data nor cmsg buffer returns EINVAL
    local msg, err = a:recvmsg()
    assert.is_nil(msg)
    assert.equal(err.type, errno.EINVAL)

    -- test that a negative bufsize raises
    local rerr = assert.throws(function()
        a:recvmsg(-1, 0)
    end)
    assert.match(rerr, 'bufsize must be non-negative')

    -- test that a negative cmsgbuf raises
    rerr = assert.throws(function()
        a:recvmsg(0, -1)
    end)
    assert.match(rerr, 'cmsgbuf must be non-negative')

    a:close()
    b:close()
end

function testcase.recvmsg_rejects_oversized_data_buffer()
    -- Reject an impractically large data buffer request without depending
    -- on the runtime-specific diagnostic or claiming a particular OOM stage.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local err = assert.throws(function()
        a:recvmsg(1152921504606846976) -- 2^60
    end)
    assert.is_string(err)

    a:close()
    b:close()
end

function testcase.recvmsg_rejects_cmsgbuf_beyond_socklen_t()
    -- The API limits cmsgbuf to UINT32_MAX, independently of the platform's
    -- msg_controllen type. Reject larger requests before allocation.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- integer literals: 2^32 as float arithmetic is rejected by
    -- lua_isinteger on Lua 5.3+ before the guard under test runs
    for _, size in ipairs({
        4294967296, -- 2^32
        4294967396, -- 2^32 + 100
        4611686018427387904, -- 2^62
    }) do
        local err = assert.throws(function()
            a:recvmsg(1, size)
        end)
        assert.match(err, 'cmsgbuf must be in the socklen_t range')
    end

    a:close()
    b:close()
end

function testcase.recvmsg_eof()
    -- After peer close, recvmsg() on a stream socket returns 0 values
    -- (EOF) to match recv()'s convention.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    assert(a:close())
    -- test that recvmsg after peer close returns all nil (matches recv)
    local msg, err, again = b:recvmsg(8)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_nil(again)

    b:close()
end

function testcase.recvmsg_again()
    -- recvmsg() on a non-blocking stream socket with no pending data
    -- returns (nil, nil, true) to signal EAGAIN, mirroring recv().
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- test that recvmsg on a non-blocking socket with no pending data returns
    -- (nil, nil, true) so callers can distinguish EAGAIN from EOF.
    local msg, err, again = b:recvmsg(8)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)

    a:close()
    b:close()
end

function testcase.recvmsg_on_closed_socket()
    -- recvmsg() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err, again = s:recvmsg(1)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(again)
end
