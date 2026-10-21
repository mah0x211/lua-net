local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local errno = require('errno')
local error_is = require('error').is

function testcase.send_again()
    -- send() surfaces EAGAIN via (0, nil, true) once the send buffer
    -- is full.  We shrink the buffer to drive the branch quickly.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(a:sndbuf(512))

    -- Fill the send buffer.  send() may report `again` with a partial write
    -- (n > 0) once the buffer starts blocking, and subsequently returns
    -- (0, nil, true) when no byte can be written at all.
    local chunk = string.rep('x', 1024)
    local n, err, again
    local sent = 0
    -- Safety bound; stop at the first no-progress EAGAIN.
    for _ = 1, 4096 do
        n, err, again = a:send(chunk)
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

function testcase.send_when_peer_closed()
    -- Sending after the Unix peer is closed returns EPIPE / ECONNRESET.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(b:close())

    local sent, err, again = a:send('x')
    assert.is_nil(sent)
    assert(error_is(err, errno.EPIPE, errno.ECONNRESET))
    assert.is_nil(again)

    a:close()
end

function testcase.send_recv_round_trip()
    -- Check empty-queue EAGAIN, full send and reads that preserve the tail.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    local msg, err, again = b:recv(16)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)

    local payload = 'helloworld'
    local n
    n, err, again = a:send(payload)
    assert.equal(n, #payload)
    assert.is_nil(err)
    assert.is_false(again)
    assert(b:recvable(1))
    msg, err, again = b:recv(5)
    assert.equal(msg, 'hello')
    assert.is_nil(err)
    assert.is_nil(again)
    msg, err, again = b:recv(5)
    assert.equal(msg, 'world')
    assert.is_nil(err)
    assert.is_nil(again)
    a:close()
    b:close()
end

function testcase.send_empty_payload()
    -- send('') is rejected as an invalid (empty) payload.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local rv, err = socks[1]:send('')
    assert.is_nil(rv)
    assert.equal(err.type, errno.EINVAL)
    socks[1]:close()
    socks[2]:close()
end

function testcase.send_on_closed_socket()
    -- send() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:send('x')
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.recv_when_peer_closed()
    -- EOF returns no values, unlike EAGAIN's (nil, nil, true).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(a:close())

    -- recv_lua should see EOF (rv == 0) and return nil (no error) so that
    -- callers can distinguish EOF from EAGAIN.
    local rv, err, again = b:recv(8)
    assert.is_nil(rv)
    assert.is_nil(err)
    assert.is_nil(again)

    b:close()
end

function testcase.recv_dgram()
    -- run recv_lua's default (successful) branch on a dgram socket.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    local n, err, again = client:sendto('hello', sai)
    assert.equal(n, 5)
    assert.is_nil(err)
    assert.is_false(again)
    assert(server:recvable(1))
    local msg
    msg, err, again = server:recv(8)
    assert.equal(msg, 'hello')
    assert.is_nil(err)
    assert.is_nil(again)

    client:close()
    server:close()
end

function testcase.recv_zero_length()
    -- recv(0) is rejected as an invalid length.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local rv, err = socks[1]:recv(0)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EINVAL)
    socks[1]:close()
    socks[2]:close()
end

function testcase.recv_dgram_again()
    -- recv() on a fresh non-blocking dgram socket with no data returns
    -- (nil, nil, true) rather than blocking.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local msg, err, again = d:recv(1)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)
    d:close()
end

function testcase.recv_on_closed_socket()
    -- recv() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:recv(1)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end
