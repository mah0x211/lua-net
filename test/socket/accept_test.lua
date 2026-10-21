local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local ACCEPTED_FD

function testcase.after_each()
    if ACCEPTED_FD then
        socket.close(ACCEPTED_FD)
        ACCEPTED_FD = nil
    end
end

function testcase.accept_on_closed_socket()
    -- accept() on a closed socket should return nil + EBADF (or similar).
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local sock, err = s:accept()
    assert.is_nil(sock)
    assert(err)
end

function testcase.accept_when_no_pending()
    -- accept() and acceptfd() on a listening socket with no pending
    -- connection return (nil, nil, true) to indicate EAGAIN (the socket is
    -- non-blocking by default), distinguishing it from EOF/error.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:listen())
    local rv, err, again = server:acceptfd()
    assert.is_nil(rv)
    assert.is_nil(err)
    assert.is_true(again)
    rv, err, again = server:accept()
    assert.is_nil(rv)
    assert.is_nil(err)
    assert.is_true(again)
    server:close()
end

function testcase.accept_with_addr()
    -- accept(true) additionally returns the peer's address as a fourth
    -- return value, wrapped in a net.addrinfo userdata.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen())
    local ai = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:recvable(1))

    local peer, err, again, peer_ai = server:accept(true)
    assert(peer, err)
    assert.is_nil(again)
    local client_ai = assert(client:getsockname())
    assert.equal(peer_ai:family(), 'inet')
    assert.equal(peer_ai:addr(), client_ai:addr())
    assert.equal(peer_ai:port(), client_ai:port())

    peer:close()
    client:close()
    server:close()
end

function testcase.accept()
    -- accept() returns the peer socket once a client has connected.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen())
    local ai = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:recvable(1))
    local peer, err = server:accept()
    assert(peer, err)
    assert.equal(assert(peer:getsockname()):port(), ai:port())
    local client_ai = assert(client:getsockname())
    local peer_ai = assert(peer:getpeername())
    assert.equal(peer_ai:family(), 'inet')
    assert.equal(peer_ai:addr(), client_ai:addr())
    assert.equal(peer_ai:port(), client_ai:port())
    peer:close()
    client:close()
    server:close()
end

function testcase.acceptfd_on_non_listening()
    -- acceptfd() on an unbound, non-listening socket returns an error.
    local unlisten = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = unlisten:acceptfd()
    assert.is_nil(rv)
    assert(err)
    unlisten:close()
end

function testcase.acceptfd()
    -- acceptfd() returns the raw accepted fd, which can then be adopted
    -- via socket.wrap().
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(0))
    local ai = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:recvable(1))
    local afd = assert(server:acceptfd())
    ACCEPTED_FD = afd
    local wrapped = assert(socket.wrap(afd))
    ACCEPTED_FD = nil
    local client_ai = assert(client:getsockname())
    local peer_ai = assert(wrapped:getpeername())
    assert.equal(peer_ai:family(), 'inet')
    assert.equal(peer_ai:addr(), client_ai:addr())
    assert.equal(peer_ai:port(), client_ai:port())
    wrapped:close()
    client:close()
    server:close()
end

function testcase.acceptfd_with_addr()
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:listen())
    local addr = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', addr:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:recvable(1))

    local fd, err, again, peer_addr = server:acceptfd(true)
    ACCEPTED_FD = fd
    assert.is_number(fd)
    assert.is_nil(err)
    assert.is_nil(again)
    local peer = assert(socket.wrap(fd))
    ACCEPTED_FD = nil
    local client_addr = assert(client:getsockname())
    assert.equal(peer_addr:family(), 'inet')
    assert.equal(peer_addr:addr(), client_addr:addr())
    assert.equal(peer_addr:port(), client_addr:port())
    assert(client:send('hello'))
    assert(peer:recvable(1))
    assert.equal(peer:recv(5), 'hello')

    peer:close()
    client:close()
    fd, err, again = server:acceptfd(true)
    assert.is_nil(fd)
    assert.is_nil(err)
    assert.is_true(again)
    collectgarbage('collect')
    assert(server:getsockname())
    server:close()
end

function testcase.acceptfd_on_closed_socket()
    -- acceptfd() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:acceptfd()
    assert.is_nil(rv)
    assert(err)
end
