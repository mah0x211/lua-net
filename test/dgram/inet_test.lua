local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local errno_eai = require('errno.eai')
local socket = require('net.socket')
local inet = require('net.dgram.inet')

function testcase.new()
    -- test that create new instance of net.dgram.inet.Socket
    local s = assert(inet.new())
    assert.match(tostring(s), '^net.dgram.inet.Socket: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'dgram')
    assert.equal(s:protocol(), 'udp')
    s:close()
end

function testcase.bind()
    local s = assert(inet.new())
    local host = '127.0.0.1'

    -- test that bind to host and available port
    local _, _, ai = assert(s:bind(host, 0))
    assert.equal(ai:addr(), host)
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.equal(ai:addr(), host)
    assert.greater(ai:port(), 0)

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.new():bind('invalid hostname', 0)
    assert.equal(err.type, errno_eai.EAI_NONAME)
    _, err = inet.new():bind(host, 'invalid servname')
    assert(err.type == errno_eai.EAI_SERVICE or err.type == errno_eai.EAI_NONAME)

    -- test that returns an error that already in use
    _, err = inet.new():bind(host, ai:port())
    assert.equal(err.type, errno.EADDRINUSE)
    s:close()

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.new():bind(host, 0, {
            reuseaddr = 1,
        })
    end), 'reuseaddr must be boolean', false)

    assert.match(assert.throws(function()
        inet.new():bind(host, 0, {
            reuseport = 'foo',
        })
    end), 'reuseport must be boolean', false)
end

function testcase.bind_with_reuse_opts()
    -- opts.reuseaddr and opts.reuseport apply setsockopt before the bind
    -- syscall so a follow-up bind on the same host/port succeeds.
    local s1 = assert(inet.new())
    assert(s1:bind('127.0.0.1', 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    local addr = assert(s1:getsockname())
    assert.equal(addr:addr(), '127.0.0.1')
    local port = addr:port()
    assert.greater(port, 0)
    assert.is_true(s1:reuseaddr())
    assert.is_true(s1:reuseport())

    local s2 = assert(inet.new())
    assert(s2:bind('127.0.0.1', port, {
        reuseaddr = true,
        reuseport = true,
    }))
    addr = assert(s2:getsockname())
    assert.equal(addr:addr(), '127.0.0.1')
    assert.equal(addr:port(), port)
    assert.is_true(s2:reuseaddr())
    assert.is_true(s2:reuseport())
    s1:close()
    s2:close()
end

function testcase.connect()
    local s = assert(inet.new())
    local host = '127.0.0.1'
    assert(s:bind(host, 0))
    local port = assert(s:getsockname()):port()

    -- test that connect to peer
    local c = assert(inet.new())
    local _, connect_err, ai = assert(c:connect(host, port))
    assert.is_nil(connect_err)
    assert.equal(ai:addr(), host)
    assert.equal(ai:port(), port)
    ai = assert(c:getpeername())
    assert.equal(ai:addr(), host)
    assert.equal(ai:port(), port)
    c:close()
    s:close()

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.new():connect(host, 'invalid servname')
    assert(err.type == errno_eai.EAI_SERVICE or err.type == errno_eai.EAI_NONAME)
end

function testcase.wrap()
    -- wrap(fd) adopts an existing UDP fd and yields a net.dgram.inet.Socket.
    local raw = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local fd = raw:unwrap()
    local s, err = inet.wrap(fd)
    if not s then
        socket.close(fd)
    end
    assert(s, err)
    local wrapped_fd = s:fd()
    assert.match(tostring(s), '^net.dgram.inet.Socket: ', false)
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'dgram')
    s:close()
    -- Also reclaim the original fd if wrap failed to adopt it.
    local closed, close_err = socket.close(fd)
    assert.equal(wrapped_fd, fd)
    assert.is_false(closed)
    assert.equal(close_err.type, errno.EBADF)
end
