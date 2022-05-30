require('luacov')
require('nosigpipe')
local testcase = require('testcase')
local errno = require('errno')
local net = require('net')
local unix = require('net.dgram.unix')

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

function testcase.new()
    -- test that create new instance of net.dgram.unix.Socket
    local s = assert(unix.new())
    assert.match(tostring(s), '^net.dgram.unix.Socket: ', false)
    assert(not s.nonblock, 'nonblocking mode')
    assert.equal(s:family(), net.AF_UNIX)
    assert.equal(s:socktype(), net.SOCK_DGRAM)
    assert.equal(s:protocol(), 0)
    s:close()
end

function testcase.bind()
    local s = assert(unix.new())

    -- test that bind to pathanme
    local _, _, ai = assert(s:bind(PATHNAME))
    assert.equal(ai:addr(), PATHNAME)
    s:close()

    -- test that returns an error that name too long
    local _, err = s:bind('./long-name-' .. string.rep('0', 500) .. '.sock')
    assert.equal(err.type, errno.ENAMETOOLONG)

    -- test that returns an error that already in use
    local s2 = assert(unix.new())
    _, err = s2:bind(PATHNAME)
    assert.equal(err.type, errno.EADDRINUSE)
    s2:close()
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
    local _, err = c:connect('./long-name-' .. string.rep('0', 500) .. '.sock')
    assert.equal(err.type, errno.ENAMETOOLONG)

    -- test that returns an error that already in use
    c = assert(unix.new())
    _, err = c:connect(PATHNAME)
    assert.equal(err.type, errno.ECONNREFUSED)
    c:close()
end

function testcase.pair()
    -- test that create new pair instance of net.dgram.unix.Socket
    local sp = assert(unix.pair(PATHNAME))
    assert.equal(#sp, 2)
    for _, s in ipairs(sp) do
        assert.match(tostring(s), '^net.dgram.unix.Socket: ', false)
        s:close()
    end
end
