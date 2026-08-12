require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local unix = require('net.dgram.unix')

local PATHNAME

function testcase.before_each()
    -- os.tmpname() gives a per-test unique path so parallel or repeated
    -- runs cannot collide via a shared os.time() second.
    PATHNAME = os.tmpname()
    os.remove(PATHNAME)
end

function testcase.after_each()
    os.remove(PATHNAME)
end

function testcase.new()
    -- test that create new instance of net.dgram.unix.Socket
    local s = assert(unix.new())
    assert.match(tostring(s), '^net.dgram.unix.Socket: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'dgram')
    assert.equal(s:protocol(), 'auto')
    s:close()
end

function testcase.bind()
    local s = assert(unix.new())

    -- test that bind to pathanme
    local _, _, ai = assert(s:bind(PATHNAME))
    assert.equal(ai:addr(), PATHNAME)

    -- test that returns an error that name too long
    local _, err = s:bind('./long-name-' .. string.rep('0', 500) .. '.sock')
    assert.equal(err.type, errno.ENAMETOOLONG)

    -- test that returns an error that already in use
    local s2 = assert(unix.new())
    _, err = s2:bind(PATHNAME)
    assert.equal(err.type, errno.EADDRINUSE)
    s2:close()
    s:close()
end

function testcase.connect()
    local s = assert(unix.new())
    assert(s:bind(PATHNAME))

    -- test that connect to pathanme
    local c = assert(unix.new())
    local _, _, _, cai = assert(c:connect(PATHNAME))
    assert.equal(cai:addr(), PATHNAME)
    c:close()
    s:close()

    -- test that returns an error that name too long
    local c2 = assert(unix.new())
    local _, err = c2:connect('./long-name-' .. string.rep('0', 500) .. '.sock')
    assert.equal(err.type, errno.ENAMETOOLONG)
    c2:close()

    -- test that connect to an unbound path is refused
    local c3 = assert(unix.new())
    _, err = c3:connect(PATHNAME)
    assert.equal(err.type, errno.ECONNREFUSED)
    c3:close()
end

function testcase.pair()
    -- test that create new pair instance of net.dgram.unix.Socket
    local sp = assert(unix.pair())
    assert.equal(#sp, 2)
    for _, s in ipairs(sp) do
        assert.match(tostring(s), '^net.dgram.unix.Socket: ', false)
        s:close()
    end
end

function testcase.wrap()
    -- wrap(fd) adopts an existing AF_UNIX dgram fd.
    local raw = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local fd = raw:unwrap()
    local s = assert(unix.wrap(fd))
    assert.match(tostring(s), '^net.dgram.unix.Socket: ', false)
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'dgram')
    s:close()
end
