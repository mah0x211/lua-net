require('luacov')
require('nosigpipe')
local assert = require('assertex')
local testcase = require('testcase')
local net = require('net')
local unix = require('net.stream.unix')
local msghdr = require('net.msghdr')

local PATHNAME
function testcase.before_all()
    PATHNAME = './' .. os.time() .. '.sock'
end

function testcase.after_each()
    os.remove(PATHNAME)
end

function testcase.after_all()
    os.remove(PATHNAME)
end

function testcase.server_new()
    -- test that create new instance of net.stream.unix.Server
    local s, _, ai = assert(unix.server.new(PATHNAME))
    assert.match(tostring(s), '^net.stream.unix.Server: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(not s.nonblock, 'nonblocking mode')
    assert.equal(s:family(), net.AF_UNIX)
    assert.equal(s:socktype(), net.SOCK_STREAM)
    assert.equal(s:protocol(), 0)
    s:close()

    -- test that returns an error that already in use
    local _, err = unix.server.new(PATHNAME)
    assert.match(err, ' already ')

    -- test that returns an error that name too long
    _, err = unix.server.new('./long-name-' .. string.rep('0', 500) .. '.sock')
    assert.match(err, 'too long')
end

function testcase.client_new()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())

    -- test that create new instance of net.stream.unix.Client
    local c, _, _, ai = assert(unix.client.new(PATHNAME))
    assert.match(tostring(c), '^net.stream.unix.Client: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(not c.nonblock, 'nonblocking mode')
    assert.equal(c:family(), net.AF_UNIX)
    assert.equal(c:socktype(), net.SOCK_STREAM)
    assert.equal(c:protocol(), 0)
    assert(c:close())

    -- test that returns an error that name too long
    local _, err = unix.client.new('./long-name-' .. string.rep('0', 500) ..
                                       '.sock')
    assert.match(err, 'too long')

    -- test that returns an error that not found
    _, err = unix.client.new('./unknown-socket')
    assert.match(err, 'directory')

    s:close()
end

function testcase.accept_send_recv()
    local s = assert(unix.server.new(PATHNAME))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME))

    -- test that accept connection as a net.stream.unix.Socket
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.unix.Socket: ', false)

    -- test that communicates with send and recv
    local msg = 'hello'
    assert(c:send(msg))
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)

    -- test that communicates with sendmsg and recvmsg
    local mhw = msghdr.new()
    mhw:add('hello')
    mhw:add('world')
    local mhr = msghdr.new()
    mhr:addn(5)
    assert(c:sendmsg(mhw))
    -- sendmsg consume messages
    assert.equal(mhw:bytes(), 0)
    local n = assert(peer:recvmsg(mhr))
    assert.equal(n, 5)
    assert.equal(mhr:concat(), 'hello')
    n = assert(peer:recvmsg(mhr))
    assert.equal(n, 5)
    assert.equal(mhr:concat(), 'world')

    -- test that communicates with writev and readv message
    mhw = msghdr.new()
    mhw:add('hello')
    mhw:add('world')
    mhr = msghdr.new()
    mhr:addn(5)
    assert(c:writev(mhw.iov))
    -- writev did not consume message
    assert(mhw:bytes(), 10)
    n = assert(peer:readv(mhr.iov))
    assert.equal(n, 5)
    assert.equal(mhr:concat(), mhw:get(1))
    n = assert(peer:readv(mhr.iov))
    assert.equal(n, 5)
    assert.equal(mhr:concat(), mhw:get(2))

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

