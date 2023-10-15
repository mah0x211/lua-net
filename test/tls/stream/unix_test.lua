require('luacov')
local testcase = require('testcase')
local fork = require('testcase.fork')
local assert = require('assert')
local errno = require('errno')
local exec = require('exec').execvp
local net = require('net')
local config = require('net.tls.config')
local unix = require('net.stream.unix')

local SERVER_CONFIG
local CLIENT_CONFIG
local TESTFILE
local PATHNAME

function testcase.before_all()
    local p = assert(exec('openssl', {
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-x509',
        '-days',
        '1',
        '-keyout',
        'cert.key',
        '-out',
        'cert.pem',
        '-subj',
        '/C=US/CN=www.example.com',
    }))

    for line in p.stderr:lines() do
        print(line)
    end

    local res = assert(p:waitpid())
    if res.exit ~= 0 then
        error('failed to generate cert files')
    end

    SERVER_CONFIG = config.new()
    assert(SERVER_CONFIG:set_keypair_file('cert.pem', 'cert.key'))
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
    os.remove('cert.pem')
    os.remove('cert.key')
end

function testcase.server_new()
    -- test that create new instance of net.stream.unix.Server
    local s, _, ai = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert.match(tostring(s), '^net.tls.stream.unix.Server: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), net.AF_UNIX)
    assert.equal(s:socktype(), net.SOCK_STREAM)
    assert.equal(s:protocol(), 0)
    assert(s:close())

    -- test that returns an error that already in use
    local _, err = unix.server.new(PATHNAME, SERVER_CONFIG)
    assert.equal(err.type, errno.EADDRINUSE)

    -- test that returns an error that name too long
    _, err = unix.server.new('./long-name-' .. string.rep('0', 500) .. '.sock',
                             SERVER_CONFIG)
    assert.equal(err.type, errno.ENAMETOOLONG)

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
    assert(c:isnonblock(), 'nonblocking mode')
    assert.equal(c:family(), net.AF_UNIX)
    assert.equal(c:socktype(), net.SOCK_STREAM)
    assert.equal(c:protocol(), 0)
    assert(c:close())

    -- test that returns an error that name too long
    local _, err = unix.client.new('./long-name-' .. string.rep('0', 500) ..
                                       '.sock', {
        tlscfg = CLIENT_CONFIG,
    })
    assert.equal(err.type, errno.ENAMETOOLONG)

    -- test that returns an error that not found
    _, err = unix.client.new('./unknown-socket', {
        tlscfg = CLIENT_CONFIG,
    })
    assert.equal(err.type, errno.ENOENT)
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

function testcase.write_read()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local msg = 'hello ' .. os.time()

    -- test that communicates with write and read
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(unix.client.new(PATHNAME, {
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:write(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    local rcv = assert(peer:read())
    assert.equal(rcv, msg)
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.send_recv()
    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())
    local msg = 'hello ' .. os.time()

    -- test that communicates with send and recv
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(unix.client.new(PATHNAME, {
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:send(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)
    peer:close()
    s:close()
    assert(p:wait())
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
    local fsize = f:seek('end')

    local s = assert(unix.server.new(PATHNAME, SERVER_CONFIG))
    assert(s:listen())

    -- test that communicates with sendfile and recv
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(unix.client.new(PATHNAME, {
            tlscfg = CLIENT_CONFIG,
        }))
        local remain = fsize
        local offset = 0

        repeat
            local sent, err, timeout = c:sendfile(f, remain, offset, 1024 * 8)
            if err and not timeout then
                error(err)
            end
            -- update next params
            offset = assert.less_or_equal(offset + sent, fsize)
            remain = assert.greater_or_equal(remain - sent, 0)
        until not timeout

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    local total = 0
    tbl = {}
    -- repeat until all sent data has been received
    while total < fsize do
        local data = assert(peer:recv())
        total = total + #data
        tbl[#tbl + 1] = data
    end
    assert.equal(total, fsize)
    assert.equal(table.concat(tbl), msg)

    peer:close()
    s:close()
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
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = c:recvmsg()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

    len, err = peer:sendmsg()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = peer:recvmsg()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

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
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = c:readv()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

    len, err = peer:writev()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = peer:readv()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

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
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = c:recvfd()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

    len, err = peer:sendfd()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)
    len, err = peer:recvfd()
    assert.is_nil(len)
    assert.equal(err.type, errno.EOPNOTSUPP)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

