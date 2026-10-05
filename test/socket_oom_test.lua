local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local newstate = require('newstate')
local socket = require('net.socket')

function testcase.luaopen_net_socket_repairs_metatable_after_oom()
    local failures = 0
    local successes = 0
    local partials = 0
    for headroom = 0, 32768, 256 do
        do
            local L = assert(newstate.new())
            local ok, success, err, partial = L:dostring([[
                local headroom = ...
                require('error')
                local errno = require('errno')
                require('net.addrinfo')
                -- Call the native initializer directly to isolate its retry
                -- from require's own failed-load bookkeeping.
                local loaders = package.searchers or package.loaders
                local open = assert(loaders[3]('net.socket'))
                local registry = debug.getregistry()
                assert(registry['net.socket'] == nil)
                local memlimit = require('memlimit')
                local padding = string.rep('a', memlimit.minsize())
                collectgarbage('collect')
                collectgarbage('collect')
                collectgarbage('stop')
                local _, limited = memlimit.maxsize(memlimit.used() + headroom)
                assert(limited)
                local success, result = pcall(open)
                memlimit.maxsize(0)
                collectgarbage('restart')
                local err = not success and result or nil
                local before = registry['net.socket']
                local partial = not success and before ~= nil
                local socket = open()
                local mt = registry['net.socket']
                assert(before == nil or before == mt)
                assert(type(mt.__gc) == 'function')
                assert(type(mt.__tostring) == 'function')
                assert(type(mt.__index) == 'table')
                local s = assert(socket.new_inet({socktype = 'stream'}))
                assert(type(tostring(s)) == 'string')
                assert(s:close())
                s = assert(socket.new_inet({socktype = 'stream'}))
                local fd = s:fd()
                mt.__gc(s)
                local closed, close_err = socket.close(fd)
                assert(not closed and close_err.type == errno.EBADF)
                return success, err, partial, #padding
            ]], headroom)
            assert(ok, success)
            if success then
                successes = successes + 1
            else
                assert.equal(err, 'not enough memory')
                failures = failures + 1
            end
            partials = partials + (partial and 1 or 0)
        end
        collectgarbage('collect')
    end
    assert.greater(failures, 0)
    assert.greater(successes, 0)
    assert.greater(partials, 0)
end

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
