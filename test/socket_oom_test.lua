local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local newstate = require('newstate')
local socket = require('net.socket')

function testcase.close_releases_fd_under_memory_limit()
    local L = assert(newstate.new())
    local ok, closed, fd = L:dostring([[
        local socket = require('net.socket')
        local memlimit = require('memlimit')
        local s = assert(socket.new_inet({socktype = 'stream'}))
        assert(s:addgcfn(nil, function() error(42) end))
        local fd = s:fd()
        local close = s.close
        collectgarbage('stop')
        local _, limited = memlimit.maxsize(memlimit.used())
        assert(limited)
        local closed = pcall(close, s)
        memlimit.maxsize(0)
        collectgarbage('restart')
        return closed, fd
    ]])
    assert.is_true(ok)
    assert.is_true(closed)
    -- newstate transfers numbers as lua_Number; restore the integer subtype.
    local success, err = socket.close(math.floor(fd))
    assert.is_false(success)
    assert.equal(err.type, errno.EBADF)
end

function testcase.gc_releases_fd_under_memory_limit()
    local L = assert(newstate.new())
    local ok, closed, fd = L:dostring([[
        local socket = require('net.socket')
        local memlimit = require('memlimit')
        local s = assert(socket.new_inet({socktype = 'stream'}))
        assert(s:addgcfn(nil, function() error(42) end))
        local fd = s:fd()
        local finalize = debug.getmetatable(s).__gc
        collectgarbage('stop')
        local _, limited = memlimit.maxsize(memlimit.used())
        assert(limited)
        local closed = pcall(finalize, s)
        memlimit.maxsize(0)
        collectgarbage('restart')
        return closed, fd
    ]])
    assert.is_true(ok)
    assert.is_true(closed)
    local success, err = socket.close(math.floor(fd))
    assert.is_false(success)
    assert.equal(err.type, errno.EBADF)
end

function testcase.vm_shutdown_releases_fd_under_memory_limit()
    local ok, fd, limited
    do
        local L = assert(newstate.new())
        ok, fd, limited = L:dostring([[
        local socket = require('net.socket')
        -- Load memlimit before the socket: its allocator must remain active
        -- until the socket's finalizer runs during VM shutdown.
        local memlimit = require('memlimit')
        s = assert(socket.new_inet({socktype = 'stream'}))
        assert(s:addgcfn(nil, function() error(42) end))
        local fd = s:fd()
        collectgarbage('stop')
        local _, limited = memlimit.maxsize(memlimit.used())
        return fd, limited
        ]])
    end
    assert.is_true(ok)
    assert.is_true(limited)
    collectgarbage('collect')
    local success, err = socket.close(math.floor(fd))
    assert.is_false(success)
    assert.equal(err.type, errno.EBADF)
end
