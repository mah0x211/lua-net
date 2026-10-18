local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local newstate = require('newstate')
local socket = require('net.socket')
local fork = require('testcase.fork')
local exit = require('testcase.exit').exit

function testcase.recvfd_oom_does_not_consume_descriptors()
    local L = assert(newstate.new())
    local ok, result, message, count = L:dostring([[
        local socket = require('net.socket')
        local memlimit = require('memlimit')
        local pair = assert(socket.pair({socktype = 'stream'}))
        assert(pair[1]:sendfd(pair[1]:fd()))
        local padding = string.rep('a', memlimit.minsize())
        collectgarbage('collect')
        collectgarbage('stop')
        local _, limited = memlimit.maxsize(memlimit.used())
        assert(limited)
        local success, message = pcall(pair[2].recvfd, pair[2])
        memlimit.maxsize(0)
        collectgarbage('restart')
        local q = assert(pair[2]:recvfd())
        local count = q:len()
        q:close()
        pair[1]:close()
        pair[2]:close()
        return success, message, count, #padding
    ]])
    assert(ok, result)
    assert.is_false(result)
    assert.equal(message, 'not enough memory')
    assert.equal(count, 1)
end

function testcase.addgcfn_oom_preserves_callbacks_and_allows_retry()
    local proc = assert(fork())
    if proc:is_child() then
        local success, err = pcall(function()
            local L = assert(newstate.new())
            assert(L:loadstring([[
                local budget = ...
                local socket = require('net.socket')
                local memlimit = require('memlimit')
                local s = assert(socket.new_inet({socktype = 'stream'}))
                local calls = 0
                local existing_calls = 0
                local retry_calls = 0
                assert(s:addgcfn(nil, function()
                    existing_calls = existing_calls + 1
                end))
                local callback = function() calls = calls + 1 end
                local padding = string.rep('a', memlimit.minsize())
                local function invoke()
                    local before
                    if budget then
                        local _, limited = memlimit.maxsize(memlimit.used() + budget)
                        assert(limited)
                    else
                        before = memlimit.used()
                    end
                    local handle = assert(s:addgcfn(nil, callback))
                    return handle, before and (memlimit.used() - before)
                end
                collectgarbage('collect')
                collectgarbage('collect')
                collectgarbage('stop')
                local registered, result, allocated = pcall(invoke)
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
                return registered, result, allocated, calls, existing_calls,
                    retry_calls, #padding
            ]]))
            local budget
            while true do
                local ok, registered, result, allocated, calls, existing_calls,
                      retry_calls = L:run(budget)
                assert(ok, registered)
                assert.equal(calls, 0)
                assert.equal(existing_calls, 1)
                assert.equal(retry_calls, 1)
                if not registered then
                    -- Stack growth OOM can also be reported as a stack error.
                    assert(result == 'not enough memory' or
                               result:find('too many arguments to addgcfn', 1,
                                           true))
                    break
                end
                assert.is_string(result)
                local upper = budget or allocated
                assert.greater(upper, 0)
                budget = math.floor(upper / 2)
            end
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
    local L = assert(newstate.new())
    assert(L:loadstring([[
        local budget = ...
        require('error')
        local errno = require('errno')
        require('net.addrinfo')
        -- Call the native initializer directly to isolate its retry
        -- from require's own failed-load bookkeeping.
        local loaders = package.searchers or package.loaders
        local open = assert(loaders[3]('net.socket'))
        local registry = debug.getregistry()
        local memlimit = require('memlimit')
        local padding = string.rep('a', memlimit.minsize())
        local function invoke()
            local before
            if budget then
                local _, limited = memlimit.maxsize(memlimit.used() + budget)
                assert(limited)
            else
                before = memlimit.used()
            end
            local module = open()
            return module, before and (memlimit.used() - before)
        end
        collectgarbage('collect')
        collectgarbage('collect')
        -- Finalize the previous trial's sockets before removing their
        -- registered metatable: __gc checks userdata against that table.
        registry['net.socket'] = nil
        -- Reclaim the detached table too, so an OOM-triggered collection
        -- cannot fund the next initialization from the previous trial.
        collectgarbage('collect')
        collectgarbage('stop')
        local success, result, allocated = pcall(invoke)
        memlimit.maxsize(0)
        collectgarbage('restart')
        local err = not success and result or nil
        local before = registry['net.socket']
        -- A completed metatable followed by a module-table OOM is not
        -- evidence that an incomplete metatable can be repaired.
        local partial = not success and before ~= nil and
            (type(before.__gc) ~= 'function' or
             type(before.__tostring) ~= 'function' or
             type(before.__index) ~= 'table')
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
        return success, err, partial, before ~= nil, allocated, #padding
    ]]))
    local lower = 0
    local upper
    local budget
    while true do
        local ok, success, err, partial, created, allocated = L:run(budget)
        assert(ok, success)
        if success then
            upper = budget or allocated
        else
            assert.equal(err, 'not enough memory')
            if partial then
                break
            elseif created then
                upper = budget
            else
                lower = budget
            end
        end
        assert(upper - lower > 1,
               'no allocation budget produced an incomplete socket metatable')
        budget = math.floor((lower + upper) / 2)
    end
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
