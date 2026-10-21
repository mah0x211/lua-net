local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local errno = require('errno')
local error_is = require('error').is

function testcase.write_again()
    -- write() surfaces EAGAIN via (0, nil, true) once the send buffer
    -- is full. Shrink the send buffer to reach that state quickly.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(a:sndbuf(512))

    local chunk = string.rep('x', 1024)
    local n, err, again
    local sent = 0
    -- Safety bound; stop as soon as a write makes no progress with EAGAIN.
    for _ = 1, 4096 do
        n, err, again = a:write(chunk)
        assert.is_nil(err)
        assert.is_int(n)
        assert.greater_or_equal(n, 0)
        assert.less_or_equal(n, #chunk)
        assert.equal(again, n < #chunk)
        if again and n == 0 then
            break
        end
        sent = sent + n
    end
    assert.greater(sent, 0)
    assert.is_true(again)
    assert.equal(n, 0)

    a:close()
    b:close()
end

function testcase.write_when_peer_closed()
    -- A write after the Unix peer is closed returns EPIPE / ECONNRESET.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(b:close())
    local sent, err, again = a:write('x')
    assert.is_nil(sent)
    assert(error_is(err, errno.EPIPE, errno.ECONNRESET))
    assert.is_nil(again)

    a:close()
end

function testcase.write_read_round_trip()
    -- Check empty-queue EAGAIN, full write and reads that preserve the tail.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    local msg, err, again = b:read(16)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)
    local payload = 'helloworld'
    local n
    n, err, again = a:write(payload)
    assert.equal(n, #payload)
    assert.is_nil(err)
    assert.is_false(again)
    assert(b:recvable(1))
    msg, err, again = b:read(5)
    assert.equal(msg, 'hello')
    assert.is_nil(err)
    assert.is_nil(again)
    msg, err, again = b:read(5)
    assert.equal(msg, 'world')
    assert.is_nil(err)
    assert.is_nil(again)
    a:close()
    b:close()
end

function testcase.write_empty_payload()
    -- An empty payload is rejected (write requires at least one byte).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local rv, err = a:write('')
    assert.is_nil(rv)
    assert.equal(err.type, errno.EINVAL)
    a:close()
    socks[2]:close()
end

function testcase.write_on_closed_socket()
    -- write() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:write('x')
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.read_zero_length()
    -- read(0) is rejected as an invalid length.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local rv, err = socks[1]:read(0)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EINVAL)
    socks[1]:close()
    socks[2]:close()
end

function testcase.read_when_peer_closed()
    -- EOF returns no values, unlike EAGAIN's (nil, nil, true).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    assert(b:close())
    local msg, err, again = a:read(4)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_nil(again)
    a:close()
end

function testcase.read_on_closed_socket()
    -- read() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:read(1)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end
