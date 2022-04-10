require('luacov')
require('nosigpipe')
local testcase = require('testcase')
local net = require('net')
local config = require('net.tls.config')
local unix = require('net.stream.unix')

local SERVER_CONFIG
local CLIENT_CONFIG
local TESTFILE
local PATHNAME

function testcase.before_all()
    SERVER_CONFIG = config.new()
    assert(SERVER_CONFIG:set_keypair_file('../cert.pem', '../cert.key'))
    CLIENT_CONFIG = config.new()
    CLIENT_CONFIG:insecure_noverifycert()
    CLIENT_CONFIG:insecure_noverifyname()

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
    local s, _, ai = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert.match(tostring(s), '^net.tls.stream.unix.Server: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(not s.nonblock, 'nonblocking mode')
    assert.equal(s:family(), net.AF_UNIX)
    assert.equal(s:socktype(), net.SOCK_STREAM)
    assert.equal(s:protocol(), 0)
    assert(s:close())

    -- test that returns an error that already in use
    local _, err = unix.server.new(PATHNAME, SERVER_CONFIG)
    assert.match(err, ' already ')

    -- test that returns an error that name too long
    _, err = unix.server.new('./long-name-' .. string.rep('0', 500) .. '.sock',
                             SERVER_CONFIG)
    assert.match(err, 'too long')

    -- test that throws an error
    err = assert.throws(function()
        unix.server.new(PATHNAME, {})
    end)
    assert.match(err, '(libtls.config expected')
end

function testcase.client_new()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())

    -- test that create new instance of net.stream.unix.Client
    local c, _, _, ai = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    assert.match(tostring(c), '^net.tls.stream.unix.Client: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(not c.nonblock, 'nonblocking mode')
    assert.equal(c:family(), net.AF_UNIX)
    assert.equal(c:socktype(), net.SOCK_STREAM)
    assert.equal(c:protocol(), 0)
    assert(c:close())

    -- test that returns an error that name too long
    local _, err = unix.client.new('./long-name-' .. string.rep('0', 500) ..
                                       '.sock', {
        tlscfg = CLIENT_CONFIG,
    })
    assert.match(err, 'too long')

    -- test that returns an error that not found
    _, err = unix.client.new('./unknown-socket', {
        tlscfg = CLIENT_CONFIG,
    })
    assert.match(err, 'directory')
    assert(s:close())

    -- test that throws an error
    err = assert.throws(function()
        unix.client.new(PATHNAME, {
            tlscfg = {},
        })
    end)
    assert.match(err, '(libtls.config expected')
end

function testcase.accept()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))

    -- test that accept connection as a net.stream.unix.Socket
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

local function do_handshake(s1, s2)
    -- NOTE: change to non-blocking mode for handshaking in the same process.
    -- handshake required before send and recv in the same process.
    local pair = {
        s1,
        s2,
    }
    s1.sock:nonblock(true)
    s2.sock:nonblock(true)
    for _ = 1, 5 do
        for _, s in ipairs(pair) do
            local ok, err = s:handshake()
            if ok then
                s1.sock:nonblock(false)
                s2.sock:nonblock(false)
                return true
            elseif err then
                return false, err
            end
        end
    end

    return false, 'failed to handshake()'
end

function testcase.send_recv()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())

    -- handshake required before send and recv in the same process.
    assert(do_handshake(c, peer))

    -- test that communicates with send and recv
    local msg = 'hello ' .. os.time()
    assert(c:send(msg))
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)

    assert(peer:close())
    -- assert(c:close())
    assert(s:close())
end

function testcase.sendfile_recv()
    -- create large file
    local f = assert(io.open(TESTFILE, 'w+'))
    local tbl = {}
    math.randomseed(os.time())
    for _ = 1, 64 do
        local tok = tostring(math.random())
        tbl[#tbl + 1] = tok .. string.rep(' ', 1024 - #tok)
    end
    local msg = table.concat(tbl)
    assert(f:write(msg))
    assert(f:flush())

    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())

    -- handshake required before send and recv in the same process.
    assert(do_handshake(c, peer))

    -- test that communicates with sendfile and recv
    c.sock:nonblock(true)
    local size = f:seek('end')
    local remain = size
    local offset = 0
    local total = 0
    tbl = {}
    repeat
        local sent, err, timeout = c:sendfile(f, remain, offset, 1024 * 8)
        assert(not err, err)

        -- update next params
        offset = assert.less_or_equal(offset + sent, size)
        remain = assert.greater_or_equal(remain - sent, 0)

        -- repeat until all sent data has been received
        while sent > 0 do
            local data = assert(peer:recv())
            sent = assert.greater_or_equal(sent - #data, 0)
            total = total + #data
            tbl[#tbl + 1] = data
        end
    until not timeout
    assert.equal(size, total)
    assert.equal(table.concat(tbl), msg)

    assert(peer:close())
    c:close()
    assert(s:close())
end

function testcase.sendmsg_recvmsg()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)

    -- test that sendmsg and recvmsg are not supported
    local len, err = c:sendmsg()
    assert.is_nil(len)
    assert.match(err, 'not supported')
    len, err = c:recvmsg()
    assert.is_nil(len)
    assert.match(err, 'not supported')

    len, err = peer:sendmsg()
    assert.is_nil(len)
    assert.match(err, 'not supported')
    len, err = peer:recvmsg()
    assert.is_nil(len)
    assert.match(err, 'not supported')

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.writev_readv()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)

    -- test that writev and readv are not supported
    local len, err = c:writev()
    assert.is_nil(len)
    assert.match(err, 'not supported')
    len, err = c:readv()
    assert.is_nil(len)
    assert.match(err, 'not supported')

    len, err = peer:writev()
    assert.is_nil(len)
    assert.match(err, 'not supported')
    len, err = peer:readv()
    assert.is_nil(len)
    assert.match(err, 'not supported')

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.sendfd_recvfd()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local c = assert(unix.client.new(PATHNAME, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.unix.Socket: ', false)

    -- test that sendfd and recvfd are not supported
    local len, err = c:sendfd()
    assert.is_nil(len)
    assert.match(err, 'not supported')
    len, err = c:recvfd()
    assert.is_nil(len)
    assert.match(err, 'not supported')

    len, err = peer:sendfd()
    assert.is_nil(len)
    assert.match(err, 'not supported')
    len, err = peer:recvfd()
    assert.is_nil(len)
    assert.match(err, 'not supported')

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

