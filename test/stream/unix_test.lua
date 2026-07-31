require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local fileno = require('io.fileno')
local fopen = require('io.fopen')
local error_is = require('error').is
local errno = require('errno')
local iovec = require('iovec')
local unix = require('net.stream.unix')

local PATHNAME
local TESTFILE

function testcase.before_all()
    PATHNAME = './' .. os.time() .. '.sock'
    TESTFILE = './' .. os.time() .. '.txt'
end

function testcase.after_each()
    os.remove(PATHNAME)
end

function testcase.after_all()
    os.remove(PATHNAME)
    os.remove(TESTFILE)
end

function testcase.server_new()
    -- test that create new instance of net.stream.unix.Server
    local s, _, ai = assert(unix.server.new(PATHNAME))
    assert.match(tostring(s), '^net.stream.unix.Server: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'auto')
    s:close()

    -- test that returns an error that already in use
    local _, err = unix.server.new(PATHNAME)
    assert.not_nil(error_is(err, errno.EADDRINUSE))

    -- test that returns an error that name too long
    _, err = unix.server.new('./long-name-' .. string.rep('0', 500) .. '.sock')
    assert.not_nil(error_is(err, errno.ENAMETOOLONG))
end

function testcase.client_new()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())

    -- test that create new instance of net.stream.unix.Client
    local c, _, _, ai = assert(unix.client.new(PATHNAME))
    assert.match(tostring(c), '^net.stream.unix.Client: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(c:isnonblock(), 'nonblocking mode')
    assert.equal(c:family(), 'unix')
    assert.equal(c:socktype(), 'stream')
    assert.equal(c:protocol(), 'auto')
    assert(c:close())

    -- test that returns an error that name too long
    local _, err = unix.client.new('./long-name-' .. string.rep('0', 500) ..
                                       '.sock')
    assert.not_nil(error_is(err, errno.ENAMETOOLONG))

    -- test that returns an error that not found
    _, err = unix.client.new('./unknown-socket')
    assert.not_nil(error_is(err, errno.ENOENT))

    s:close()
end

function testcase.accept()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME))

    -- test that accept connection as a net.stream.unix.Socket
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.unix.Socket: ', false)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.write_read()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME))
    local peer = assert(s:accept())

    -- test that communicates with wrote and read
    local msg = 'hello ' .. os.time()
    assert(c:write(msg))
    local rcv = assert(peer:read())
    assert.equal(rcv, msg)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.send_recv()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME))
    local peer = assert(s:accept())

    -- test that communicates with send and recv
    local msg = 'hello ' .. os.time()
    assert(c:send(msg))
    local rcv = assert(peer:recv(nil, 'peek'))
    assert.equal(rcv, msg)
    rcv = assert(peer:recv())
    assert.equal(rcv, msg)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.sendfile_recv()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME))
    local peer = assert(s:accept())

    -- test that communicates with sendfile and recv
    local msg = 'hello ' .. os.time()
    local f = assert(io.open(TESTFILE, 'w+'))
    assert(f:write(msg))
    assert(f:flush())
    assert(c:sendfile(f, f:seek('end')))
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.sendmsg_recvmsg()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.unix.Socket: ', false)

    -- test that communicates with sendmsg and recvmsg using the new
    -- (msg:string) API.  cmsg / addr are not used on connected unix streams.
    assert.equal(assert(c:sendmsg('hello')), 5)
    local msg = assert(peer:recvmsg(5))
    assert.equal(msg.data, 'hello')

    assert.equal(assert(c:sendmsg('world')), 5)
    msg = assert(peer:recvmsg(5))
    assert.equal(msg.data, 'world')

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.writev_readv()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.unix.Socket: ', false)

    -- test that communicates with writev and readv message
    local iov_w = iovec.new()
    iov_w:add('hello')
    iov_w:add('world')
    local iov_r = iovec.new()
    iov_r:addn(5)
    assert(c:writev(iov_w))
    -- writev did not consume message
    assert(iov_w:bytes(), 10)
    local n = assert(peer:readv(iov_r))
    assert.equal(n, 5)
    assert.equal(iov_r:concat(), iov_w:get(1))
    n = assert(peer:readv(iov_r))
    assert.equal(n, 5)
    assert.equal(iov_r:concat(), iov_w:get(2))

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.sendfd_recvfd()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.unix.Socket: ', false)

    -- test that send fd to server
    local msg = 'hello ' .. os.time()
    local f = assert(io.open(TESTFILE, 'w+'))
    assert(f:write(msg))
    assert(f:flush())
    assert(c:sendfd(fileno(f)))
    f:close()

    -- test that recv fd from peer
    local fd = assert(peer:recvfd())
    f = assert(fopen(fd, 'r'))
    f:seek('set', 0)
    assert.equal(f:read('*a'), msg)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.pair()
    -- test that create new pair instance of net.stream.unix.Socket
    local sp = assert(unix.pair(PATHNAME))
    assert.equal(#sp, 2)
    for _, s in ipairs(sp) do
        assert.match(tostring(s), '^net.stream.unix.Socket: ', false)
        s:close()
    end
end

function testcase.shutdown_directions()
    local sp = assert(unix.pair())
    assert(sp[1]:closer())
    assert(sp[1]:close())
    assert(sp[2]:close())

    sp = assert(unix.pair())
    assert(sp[1]:closew())
    assert(sp[1]:close())
    assert(sp[2]:close())

    sp = assert(unix.pair())
    assert(sp[1]:close(true, true))
    assert(sp[2]:close())
end
