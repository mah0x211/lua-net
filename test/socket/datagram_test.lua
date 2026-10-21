local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')

function testcase.sendto_rejects_empty_payload()
    -- An empty payload is rejected before sending a datagram.
    local sai = assert(addrinfo.inet('127.0.0.1', 65535, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    local rv, err = client:sendto('', sai)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    client:close()
end

function testcase.sendto_on_closed_socket()
    -- sendto() on a closed socket returns (nil, err) via EBADF.
    local sai = assert(addrinfo.inet('127.0.0.1', 65535, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:sendto('x', sai)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EBADF)
end

function testcase.recvfrom_stream_eof()
    -- A stream peer closing without sending data produces EOF, not EAGAIN.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    a:close()

    local rv, err, again, ai = b:recvfrom(8)
    assert.is_nil(rv)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.is_nil(ai)

    b:close()
end

function testcase.recvfrom_dgram()
    -- Verify EAGAIN before sending, then the send count, payload and source
    -- address of a datagram sent to an explicit destination.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    -- again path (nothing pending on the server yet)
    local msg, err, again = server:recvfrom(16)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)

    -- success path
    local sent, send_err, send_again = client:sendto('hi', sai)
    assert.equal(sent, 2)
    assert.is_nil(send_err)
    assert.is_false(send_again)
    assert(server:recvable(1))
    local rmsg, rerr, ragain, rai = server:recvfrom(16)
    assert.equal(rmsg, 'hi')
    assert.is_nil(rerr)
    assert.is_nil(ragain)
    local client_ai = assert(client:getsockname())
    assert.greater(client_ai:port(), 0)
    assert.equal(rai:family(), 'inet')
    assert.equal(rai:addr(), '127.0.0.1')
    assert.equal(rai:port(), client_ai:port())

    client:close()
    server:close()
end

function testcase.recvfrom_stream_no_addr()
    -- On a connected SOCK_STREAM socket, recvfrom() succeeds but the peer
    -- address is anonymous (slen == 0), so recvfrom_lua takes the "no
    -- addrinfo" branch and returns only the data.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    assert(b:send('hi'))
    assert(a:recvable(1))
    local msg, err, again, ai = a:recvfrom(8)
    assert.equal(msg, 'hi')
    assert.is_nil(err)
    assert.is_nil(again)
    assert.is_nil(ai)

    a:close()
    b:close()
end

function testcase.recvfrom_zero_length()
    -- recvfrom(0) is rejected as an invalid length.
    local pair_socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local rv, rerr = pair_socks[1]:recvfrom(0)
    assert.is_nil(rv)
    assert(rerr)
    assert.equal(rerr.type, errno.EINVAL)
    pair_socks[1]:close()
    pair_socks[2]:close()
end

function testcase.recvfrom_on_closed_socket()
    -- recvfrom() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:recvfrom(1)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EBADF)
end
