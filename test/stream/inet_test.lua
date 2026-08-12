require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local error = require('error')
local errno = require('errno')
local errno_eai = require('errno.eai')
local iovec = require('iovec')
local inet = require('net.stream.inet')

local HOST = '127.0.0.1'
local SERVER, CLIENT, PEER
local TESTFILE

function testcase.before_each()
    TESTFILE = os.tmpname()
    os.remove(TESTFILE)
end

function testcase.after_each()
    if PEER then
        PEER:close()
        PEER = nil
    end
    if CLIENT then
        CLIENT:close()
        CLIENT = nil
    end
    if SERVER then
        SERVER:close()
        SERVER = nil
    end
    os.remove(TESTFILE)
end

-- open_pair sets SERVER, CLIENT, PEER so after_each closes them.  The
-- caller may still close explicitly to observe close-side errors.
local function open_pair()
    SERVER = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(SERVER:listen())
    local port = assert(SERVER:getsockname()):port()
    CLIENT = assert(inet.client.new(HOST, port))
    PEER = assert(SERVER:accept())
    return SERVER, CLIENT, PEER
end

function testcase.server_new()
    -- test that create new net.stream.inet.Server
    local s, _, ai = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert.match(tostring(s), '^net.stream.inet.Server: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'tcp')
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.greater(ai:port(), 0)
    s:close()

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.server.new('invalid hostname', 0)
    assert.not_nil(error.is(err, errno_eai.EAI_NONAME))
    _, err = inet.server.new(HOST, 'invalid servname')
    assert(error.is(err, errno_eai.EAI_SERVICE) or
               error.is(err, errno_eai.EAI_NONAME))

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.server.new(HOST, 0, {
            reuseaddr = 1,
        })
    end), 'reuseaddr must be boolean', false)

    assert.match(assert.throws(function()
        inet.server.new(HOST, 0, {
            reuseport = 'foo',
        })
    end), 'reuseport must be boolean', false)
end

function testcase.client_new()
    local s = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    local port = assert(s:getsockname()):port()

    -- test that return client
    assert(s:listen())
    local c, err, timeout, ai = assert(inet.client.new(HOST, port, {
        deadline = 0.1,
    }))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.match(tostring(c), '^net.stream.inet.Client: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(c:isnonblock(), 'c:isnonblock() is not false')
    assert.equal(c:family(), 'inet')
    assert.equal(c:socktype(), 'stream')
    assert.equal(c:protocol(), 'tcp')
    c:close()
    s:close()

    -- test that returns error that refuse
    c, err, timeout = inet.client.new(HOST, port, {
        deadline = 0.1,
    })
    assert.is_nil(c)
    assert.not_nil(error.is(err, errno.ECONNREFUSED))
    assert.is_nil(timeout)

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.client.new(HOST, port, {
            deadline = 'foo',
        })
    end), 'deadline must be finite number', false)
end

function testcase.accept()
    local _, _, peer = open_pair()
    assert.match(tostring(peer), '^net.stream.inet.Socket: ', false)
end

function testcase.write_read()
    local _, c, peer = open_pair()
    -- write from client, read on the accepted peer.
    assert(c:write('hello'))
    assert.equal(assert(peer:read()), 'hello')
end

function testcase.send_recv()
    local _, c, peer = open_pair()
    -- send from client, recv on the accepted peer.
    assert(c:send('hello'))
    assert.equal(assert(peer:recv()), 'hello')
end

function testcase.sendfile_recv()
    local _, c, peer = open_pair()
    local f = assert(io.open(TESTFILE, 'w+'))
    assert(f:write('hello'))
    assert(f:flush())
    assert(c:sendfile(f, f:seek('end')))
    assert.equal(assert(peer:recv()), 'hello')
end

function testcase.sendmsg_recvmsg()
    local _, c, peer = open_pair()
    -- new (msg:string) API; cmsg / addr are not used on connected TCP.
    assert.equal(assert(c:sendmsg('hello')), 5)
    assert.equal(assert(peer:recvmsg(5)).data, 'hello')

    assert.equal(assert(c:sendmsg('world')), 5)
    assert.equal(assert(peer:recvmsg(5)).data, 'world')
end

function testcase.writev_readv()
    local _, c, peer = open_pair()
    local iov_w = iovec.new()
    iov_w:add('hello')
    iov_w:add('world')
    local iov_r = iovec.new()
    iov_r:addn(5)
    assert(c:writev(iov_w))
    -- writev did not consume message
    assert(iov_w:bytes(), 10)
    assert.equal(assert(peer:readv(iov_r)), 5)
    assert.equal(iov_r:concat(), iov_w:get(1))
    assert.equal(assert(peer:readv(iov_r)), 5)
    assert.equal(iov_r:concat(), iov_w:get(2))
end
