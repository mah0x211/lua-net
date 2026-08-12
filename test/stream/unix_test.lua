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
local SERVER, CLIENT, PEER

function testcase.before_each()
    -- os.tmpname yields a fresh path per test so runs never collide.
    PATHNAME = os.tmpname()
    os.remove(PATHNAME)
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
    os.remove(PATHNAME)
    os.remove(TESTFILE)
end

-- open_pair sets SERVER/CLIENT/PEER so after_each closes them.
local function open_pair()
    SERVER = assert(unix.server.new(PATHNAME))
    assert(SERVER:listen())
    CLIENT = assert(unix.client.new(PATHNAME))
    PEER = assert(SERVER:accept())
    return SERVER, CLIENT, PEER
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
    local _, _, peer = open_pair()
    assert.match(tostring(peer), '^net.stream.unix.Socket: ', false)
end

function testcase.write_read()
    local _, c, peer = open_pair()
    assert(c:write('hello'))
    assert.equal(assert(peer:read()), 'hello')
end

function testcase.send_recv()
    local _, c, peer = open_pair()
    assert(c:send('hello'))
    -- peek does not consume the datagram, so a subsequent recv sees the
    -- same bytes.
    assert.equal(assert(peer:recv(nil, 'peek')), 'hello')
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
    -- new (msg:string) API; cmsg / addr are not used on connected unix.
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

function testcase.sendfd_recvfd()
    local _, c, peer = open_pair()
    -- send an open fd from client, recv it on peer, verify contents.
    local f = assert(io.open(TESTFILE, 'w+'))
    assert(f:write('hello'))
    assert(f:flush())
    assert(c:sendfd(fileno(f)))
    f:close()

    local fd = assert(peer:recvfd())
    f = assert(fopen(fd, 'r'))
    f:seek('set', 0)
    assert.equal(f:read('*a'), 'hello')
end

function testcase.pair()
    -- unix stream pair does not need a filesystem path.
    local sp = assert(unix.pair())
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
