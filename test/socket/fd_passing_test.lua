local fileno = require('io.fileno')
local fopen = require('io.fopen')
local testcase = require('testcase')
local assert = require('assert')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')
local errno = require('errno')

local TMPPATHS = {}

--- Tracked tmpname(): the path is removed by after_each even when a
--- test fails midway, so no unix socket or temp file is left behind.
--- @return string path
local function tmpname()
    local path = os.tmpname()
    TMPPATHS[#TMPPATHS + 1] = path
    return path
end

function testcase.after_each()
    for i = #TMPPATHS, 1, -1 do
        os.remove(TMPPATHS[i])
        TMPPATHS[i] = nil
    end
end

function testcase.sendfd_recvfd_round_trip()
    -- Basic SCM_RIGHTS round-trip: sending a file descriptor over a unix
    -- stream socketpair transfers the fd to the peer.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())
    assert(f:write('passed file'))
    assert(f:flush())
    local n, err, again = a:sendfd(fileno(f))
    assert.equal(n, 0)
    assert.is_nil(err)
    assert.is_nil(again)
    assert(b:recvable(1))
    local q
    q, err, again = b:recvfd()
    assert.is_userdata(q)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(q:len(), 1)
    -- fopen duplicates the borrowed fd; the queue still owns the original.
    local received = assert(fopen(assert(q:peek()), 'r'))
    assert.is_nil(q:close())
    assert(received:seek('set', 0))
    assert.equal(received:read('*a'), 'passed file')
    received:close()
    f:close()
    a:close()
    b:close()
end

function testcase.sendfd_with_destination_addr()
    -- On unix dgram sockets a destination addrinfo is honored: the
    -- msghdr's msg_name / msg_namelen are populated from ai_addr /
    -- ai_addrlen.
    local path_a = tmpname()
    os.remove(path_a)
    local path_b = tmpname()
    os.remove(path_b)
    local ai_a = assert(addrinfo.unix(path_a, {
        socktype = 'dgram',
    }))
    local ai_b = assert(addrinfo.unix(path_b, {
        socktype = 'dgram',
    }))
    local da = assert(socket.bind_unix(ai_a))
    local db = assert(socket.bind_unix(ai_b))
    local f = assert(io.tmpfile())
    local n, err, again = da:sendfd(fileno(f), ai_b)
    assert.equal(n, 0)
    assert.is_nil(err)
    assert.is_nil(again)
    assert(db:recvable(1))
    local q
    q, err, again = db:recvfd()
    assert.is_userdata(q)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(q:len(), 1)
    assert.is_nil(q:close())
    f:close()
    da:close()
    db:close()
    os.remove(path_a)
    os.remove(path_b)
end

function testcase.sendfd_again()
    -- Fill the send buffer to drive sendfd_lua's EAGAIN branch.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(a:sndbuf(512))
    local f = assert(io.tmpfile())
    local n, err, again
    local sent = 0
    for _ = 1, 1024 do
        n, err, again = a:sendfd(fileno(f))
        assert.equal(n, 0)
        assert.is_nil(err)
        if again then
            break
        end
        assert.is_nil(again)
        sent = sent + 1
    end
    assert.greater(sent, 0)
    assert.is_true(again)
    assert.equal(n, 0)
    f:close()
    a:close()
    b:close()
end

function testcase.sendfd_on_closed_socket()
    -- sendfd() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:sendfd(0)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.recvfd_again()
    -- No pending data: recvfd returns (nil, nil, true) to signal EAGAIN,
    -- matching recv's convention.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local rfd, err, again = b:recvfd()
    assert.is_nil(rfd)
    assert.is_nil(err)
    assert.is_true(again)
    a:close()
    b:close()
end

function testcase.recvfd_when_peer_closed()
    -- After peer close, recvfd on stream returns 0 values (EOF).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    a:close()
    local rfd, err, again = b:recvfd()
    assert.is_nil(rfd)
    assert.is_nil(err)
    assert.is_nil(again)
    b:close()
end

function testcase.recvfd_non_scm_rights_discarded()
    -- A message that does NOT carry SCM_RIGHTS makes recvfd take the
    -- "discard received messages" branch and return (nil, nil, true).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert.equal(b:write('X'), 1)
    -- without the message on the wire, recvfd would return EAGAIN and
    -- the discard branch would never run
    assert(a:recvable(1))
    local rfd, err, again = a:recvfd()
    assert.is_nil(rfd)
    assert.is_nil(err)
    assert.is_true(again)
    local ready, poll_err, timeout = a:recvable(0)
    assert.is_false(ready)
    assert.is_nil(poll_err)
    assert.is_true(timeout)
    a:close()
    b:close()
end

function testcase.recvfd_on_closed_socket()
    -- recvfd() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:recvfd()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end
