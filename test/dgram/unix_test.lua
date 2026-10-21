local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local unix = require('net.dgram.unix')

local PATHNAME

local TMPPATHS = {}

--- Tracked tmpname(): the path is removed by after_each even when a
--- test fails midway, so no unix socket or temp file is left behind.
--- @return string path
local function tmpname()
    local path = os.tmpname()
    TMPPATHS[#TMPPATHS + 1] = path
    return path
end

function testcase.before_each()
    -- tmpname() gives a per-test unique path so parallel or repeated
    -- runs cannot collide via a shared os.time() second.
    PATHNAME = tmpname()
    os.remove(PATHNAME)
end

function testcase.after_each()
    for i = #TMPPATHS, 1, -1 do
        os.remove(TMPPATHS[i])
        TMPPATHS[i] = nil
    end

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
    assert.equal(assert(s:getsockname()):addr(), PATHNAME)

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
    local _, connect_err, timeout, cai = assert(c:connect(PATHNAME))
    assert.is_nil(connect_err)
    assert.is_nil(timeout)
    assert.equal(cai:addr(), PATHNAME)
    assert.equal(assert(c:getpeername()):addr(), PATHNAME)
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
    -- Bound a broken pair's receive without delaying normal queued I/O.
    sp[2]:rcvtimeo(0.1)
    assert.equal(sp[1]:send('pair'), 4)
    assert.equal(sp[2]:recv(4), 'pair')
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
    local s, err = unix.wrap(fd)
    if not s then
        socket.close(fd)
    end
    assert(s, err)
    local wrapped_fd = s:fd()
    assert.match(tostring(s), '^net.dgram.unix.Socket: ', false)
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'dgram')
    s:close()
    local closed, close_err = socket.close(fd)
    assert.equal(wrapped_fd, fd)
    assert.is_false(closed)
    assert.equal(close_err.type, errno.EBADF)
end
