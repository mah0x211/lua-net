local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local error_is = require('error').is

function testcase.sendmsg_dgram_after_peer_close()
    -- This is a connected Unix datagram pair, not an unconnected UDP send.
    local socks = assert(socket.pair({
        socktype = 'dgram',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(b:close())
    local rv, err, again, succeeded = a:sendmsg('x')
    assert.is_nil(rv)
    assert(error_is(err, errno.ECONNRESET, errno.ECONNREFUSED))
    assert.is_nil(again)
    assert.is_nil(succeeded)
    a:close()
end

function testcase.sendmsg_empty_input()
    -- sendmsg() with neither payload nor cmsg surfaces EINVAL.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- test that sending nothing (no data and no cmsg) returns EINVAL
    local len, err, again, succeeded = a:sendmsg()
    assert.is_nil(len)
    assert.equal(err.type, errno.EINVAL)
    assert.is_nil(again)
    assert.is_nil(succeeded)

    -- test that an empty cmsg table together with data still succeeds
    len, err, again, succeeded = a:sendmsg('z', nil, {})
    assert.equal(len, 1)
    assert.is_nil(err)
    assert.is_false(again)
    assert.is_true(succeeded)
    assert.equal(assert(b:recv(1)), 'z')

    a:close()
    b:close()
end

function testcase.sendmsg_when_peer_closed()
    -- Sending after the Unix stream peer is closed returns a terminal error.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    assert(b:close())
    local sent, err, again, succeeded = a:sendmsg('x')
    assert.is_nil(sent)
    assert(error_is(err, errno.EPIPE, errno.ECONNRESET))
    assert.is_nil(again)
    assert.is_nil(succeeded)

    a:close()
end

function testcase.sendmsg_again()
    -- Successful fragments report succeeded=true, even with a partial send.
    -- EAGAIN reports no success flag so the caller retains ancillary data.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(a:sndbuf(512))

    local chunk = string.rep('x', 1024)
    local n, err, again, succeeded
    local sent = 0
    -- Safety bound; stop at the first no-progress EAGAIN.
    for _ = 1, 4096 do
        n, err, again, succeeded = a:sendmsg(chunk)
        assert.is_nil(err)
        assert.is_int(n)
        assert.greater_or_equal(n, 0)
        assert.less_or_equal(n, #chunk)
        assert.equal(again, n < #chunk)
        if n == 0 then
            assert.is_nil(succeeded)
            break
        end
        assert.is_true(succeeded)
        sent = sent + n
    end
    assert.greater(sent, 0)
    assert.is_true(again)
    assert.equal(n, 0)

    a:close()
    b:close()
end

function testcase.sendmsg_on_closed_socket()
    -- sendmsg() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err, again, succeeded = s:sendmsg('x')
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(again)
    assert.is_nil(succeeded)
end
