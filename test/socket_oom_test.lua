local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local newstate = require('newstate')
local socket = require('net.socket')
local fork = require('testcase.fork')
local exit = require('testcase.exit').exit

function testcase.addgcfn_oom_is_caught_by_caller()
    local proc = assert(fork())
    if proc:is_child() then
        local success, err = pcall(function()
            local L = assert(newstate.new())
            local ok, registered, result, calls, existing_calls = L:dostring([[
                local socket = require('net.socket')
                local memlimit = require('memlimit')
                local s = assert(socket.new_inet({socktype = 'stream'}))
                local calls = 0
                local existing_calls = 0
                assert(s:addgcfn(nil, function()
                    existing_calls = existing_calls + 1
                end))
                local callback = function() calls = calls + 1 end
                local padding = string.rep('a', memlimit.minsize())
                collectgarbage('collect')
                collectgarbage('collect')
                collectgarbage('stop')
                local _, limited = memlimit.maxsize(memlimit.used())
                assert(limited)
                local registered, result = pcall(s.addgcfn, s, nil, callback)
                memlimit.maxsize(0)
                collectgarbage('restart')
                assert(s:close())
                return registered, result, calls, existing_calls, #padding
            ]])
            assert(ok, registered)
            assert.is_false(registered)
            assert.equal(result, 'not enough memory')
            assert.equal(calls, 0)
            assert.equal(existing_calls, 1)
        end)
        if not success then
            io.stderr:write(tostring(err), '\n')
        end
        exit(success and 0 or 1)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.addgcfn_oom_does_not_register_callback()
    local proc = assert(fork())
    if proc:is_child() then
        local success, err = pcall(function()
            local failures = 0
            local successes = 0
            for headroom = 96, 2048, 16 do
                do
                    local L = assert(newstate.new())
                    local ok, registered, result, calls, retry_calls =
                        L:dostring([[
                        local headroom = ...
                        local socket = require('net.socket')
                        local memlimit = require('memlimit')
                        local s = assert(socket.new_inet({socktype = 'stream'}))
                        local calls = 0
                        local retry_calls = 0
                        local callback = function() calls = calls + 1 end
                        local padding = string.rep('a', memlimit.minsize())
                        collectgarbage('collect')
                        collectgarbage('collect')
                        collectgarbage('stop')
                        local _, limited = memlimit.maxsize(memlimit.used() + headroom)
                        assert(limited)
                        local registered, result = pcall(s.addgcfn, s, nil, callback)
                        memlimit.maxsize(0)
                        collectgarbage('restart')
                        if registered then
                            assert(s:delgcfn(result))
                        end
                        local handle = assert(s:addgcfn(nil, callback))
                        assert(s:delgcfn(handle))
                        assert(not s:delgcfn(handle))
                        assert(s:addgcfn(nil, function()
                            retry_calls = retry_calls + 1
                        end))
                        assert(s:close())
                        return registered, result, calls, retry_calls, #padding
                    ]], headroom)
                    assert(ok, registered)
                    assert.equal(calls, 0)
                    assert.equal(retry_calls, 1)
                    if registered then
                        assert.is_string(result)
                        successes = successes + 1
                    else
                        -- Lua 5.2+ reports stack growth OOM as a stack error.
                        assert(result == 'not enough memory' or
                                   result:find('too many arguments to addgcfn',
                                               1, true))
                        failures = failures + 1
                    end
                end
                collectgarbage('collect')
            end
            assert.greater(failures, 0)
            assert.greater(successes, 0)
        end)
        if not success then
            io.stderr:write(tostring(err), '\n')
        end
        exit(success and 0 or 1)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.addgcfn_stack_growth_oom_preserves_callbacks()
    local proc = assert(fork())
    if proc:is_child() then
        local success, err = pcall(function()
            local failures = 0
            local successes = 0
            for n = 0, 64 do
                for _, headroom in ipairs({
                    0,
                    128,
                    4096,
                }) do
                    do
                        local L = assert(newstate.new())
                        local ok, registered, result, calls = L:dostring([[
                            local n, headroom = ...
                            local socket = require('net.socket')
                            local memlimit = require('memlimit')
                            local s = assert(socket.new_inet({socktype = 'stream'}))
                            local calls = 0
                            local callback = function() calls = calls + 1 end
                            for _ = 1, n do
                                assert(s:addgcfn(nil, callback))
                            end
                            local padding = string.rep('a', memlimit.minsize())
                            collectgarbage('collect')
                            collectgarbage('collect')
                            collectgarbage('stop')
                            local _, limited = memlimit.maxsize(memlimit.used() + headroom)
                            assert(limited)
                            local registered, result = pcall(s.addgcfn, s, nil, callback)
                            memlimit.maxsize(0)
                            collectgarbage('restart')
                            if registered then
                                assert(s:delgcfn(result))
                            end
                            assert(s:close())
                            return registered, result, calls, #padding
                        ]], n, headroom)
                        assert(ok, registered)
                        assert.equal(calls, n)
                        if registered then
                            assert.is_string(result)
                            successes = successes + 1
                        else
                            assert(result == 'not enough memory' or
                                       result:find(
                                           'too many arguments to addgcfn', 1,
                                           true))
                            failures = failures + 1
                        end
                    end
                    collectgarbage('collect')
                end
            end
            assert.greater(failures, 0)
            assert.greater(successes, 0)
        end)
        if not success then
            io.stderr:write(tostring(err), '\n')
        end
        exit(success and 0 or 1)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

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
