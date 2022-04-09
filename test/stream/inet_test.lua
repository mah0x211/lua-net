require('luacov')
require('nosigpipe')
local io = io
local testcase = require('testcase')
local net = require('net')
local inet = require('net.stream.inet')
local msghdr = require('net.msghdr')

local TESTFILE

function testcase.before_all()
    TESTFILE = './' .. os.time() .. '.txt'
end

function testcase.after_all()
    os.remove(TESTFILE)
end

function testcase.server_new()
    local host = '127.0.0.1'

    -- test that create new net.stream.inet.Server
    local s, _, ai = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert.match(tostring(s), '^net.stream.inet.Server: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(not s.nonblock, 'nonblocking mode')
    assert.equal(s:family(), net.AF_INET)
    assert.equal(s:socktype(), net.SOCK_STREAM)
    assert.equal(s:protocol(), net.IPPROTO_TCP)
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.greater(ai:port(), 0)
    s:close()

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.server.new('invalid hostname', 0)
    assert.match(err, 'not known')
    _, err = inet.server.new(host, 'invalid servname')
    assert(err, 'server created with invalid servname')

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.server.new(host, 0, {
            reuseaddr = 1,
        })
    end), 'reuseaddr must be boolean', false)

    assert.match(assert.throws(function()
        inet.server.new(host, 0, {
            reuseport = 'foo',
        })
    end), 'reuseport must be boolean', false)
end

function testcase.client_new()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    local sai = assert(s:getsockname())
    local port = assert(sai:port())

    -- NOTE: it returns a connection refused error on linux platform
    -- test that timedout
    -- local c, err, timeout, ai = inet.client.new(host, port, 100)
    -- assert.is_nil(c)
    -- assert.is_true(timeout)
    -- assert.is_nil(err)
    -- assert.is_nil(ai)

    -- test that return client
    assert(s:listen())
    local c, err, timeout, ai = assert(inet.client.new(host, port, {
        deadline = 100,
    }))
    assert.match(tostring(c), '^net.stream.inet.Client: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(not c.nonblock, 'c.nonblock is not false')
    assert.equal(c:family(), net.AF_INET)
    assert.equal(c:socktype(), net.SOCK_STREAM)
    assert.equal(c:protocol(), net.IPPROTO_TCP)
    c:close()
    s:close()

    -- test that returns error that refuse
    c, err, timeout = inet.client.new(host, port, {
        deadline = 100,
    })
    assert.is_nil(c)
    assert.match(err, 'refused')
    assert.is_nil(timeout)

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            deadline = 'foo',
        })
    end), 'deadline must be uint', false)
end

function testcase.accept()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port))

    -- test that accept connection as a net.stream.inet.Socket
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.inet.Socket: ', false)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.send_recv()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.inet.Socket: ', false)

    -- test that communicates with send and recv
    local msg = 'hello'
    assert(c:send(msg))
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.sendfile_recv()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.inet.Socket: ', false)

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
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.inet.Socket: ', false)

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

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.writev_readv()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.stream.inet.Socket: ', false)

    -- test that communicates with writev and readv message
    local mhw = msghdr.new()
    mhw:add('hello')
    mhw:add('world')
    local mhr = msghdr.new()
    mhr:addn(5)
    assert(c:writev(mhw.iov))
    -- writev did not consume message
    assert(mhw:bytes(), 10)
    local n = assert(peer:readv(mhr.iov))
    assert.equal(n, 5)
    assert.equal(mhr:concat(), mhw:get(1))
    n = assert(peer:readv(mhr.iov))
    assert.equal(n, 5)
    assert.equal(mhr:concat(), mhw:get(2))

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

