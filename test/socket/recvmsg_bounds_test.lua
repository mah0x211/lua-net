local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local fileno = require('io.fileno')
local fopen = require('io.fopen')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local newstate = require('newstate')

function testcase.recvmsg_truncated_rights_stay_within_control_buffer()
    -- Isolate descriptor handling so a regression cannot close runner FDs.
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            local socks = assert(socket.pair({socktype = 'stream'}))
            local a, b = socks[1], socks[2]
            local f = assert(io.tmpfile())
            assert(f:write('bounded rights'))
            assert(f:flush())
            local rights = {}
            for i = 1, 8 do
                rights[i] = fileno(f)
            end
            -- Every supported ABI uses at least 12 header bytes and four
            -- bytes per descriptor. These bounds also cover larger headers.
            for _, case in ipairs({
                {size = 12, maxfds = 0},
                {size = 15, maxfds = 0},
                {size = 16, maxfds = 1},
                {size = 19, maxfds = 1},
                {size = 20, maxfds = 2},
            }) do
                assert.equal(a:sendmsg('x', nil, {{
                    level = 'socket',
                    type = 'rights',
                    data = rights,
                }}), 1)
                local msg, err, again = b:recvmsg(1, case.size)
                assert(msg, err)
                assert.is_nil(err)
                assert.is_nil(again)
                assert.equal(msg.data, 'x')
                assert.is_true(msg.flags.ctrunc)
                local fds = {}
                for _, cm in ipairs(msg.cmsgs or {}) do
                    assert.equal(cm.level, 'socket')
                    assert.equal(cm.type, 'rights')
                    if type(cm.data) == 'number' then
                        fds[#fds + 1] = cm.data
                    else
                        for _, fd in ipairs(cm.data) do
                            fds[#fds + 1] = fd
                        end
                    end
                end
                assert.less_or_equal(#fds, case.maxfds)
                for _, fd in ipairs(fds) do
                    -- The returned descriptor must identify the sent file.
                    local received = assert(fopen(fd, 'r'))
                    assert(received:seek('set', 0))
                    assert.equal(received:read('*a'), 'bounded rights')
                    assert(received:close())
                    assert(socket.close(fd))
                end
                -- These live descriptors must survive parsing and cleanup.
                assert(a:getsockname())
                assert(b:getsockname())
                assert(f:seek('set', 0))
                collectgarbage('collect')
            end
            f:close()
            a:close()
            b:close()
        end)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.recvmsg_truncated_rights_oom_closes_received_fd()
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            local L = assert(newstate.new())
            assert(L:loadstring([[
                local budget = ...
                local socket = require('net.socket')
                local memlimit = require('memlimit')
                local errno = require('errno')
                local pair = assert(socket.pair({socktype = 'stream'}))
                local a, b = pair[1], pair[2]
                local rights = {}
                for i = 1, 8 do rights[i] = a:fd() end
                assert(a:sendmsg('x', nil, {{
                    level = 'socket', type = 'rights', data = rights,
                }}))
                local padding = string.rep('a', memlimit.minsize())
                local probe = assert(socket.new_inet({socktype = 'stream'}))
                local received_fd = probe:fd()
                assert(probe:close())
                local function invoke()
                    local before
                    if budget then
                        local _, limited = memlimit.maxsize(memlimit.used() + budget)
                        assert(limited)
                    else
                        before = memlimit.used()
                    end
                    -- At most one complete FD fits, even with a 12-byte header.
                    local msg = b:recvmsg(1, 19)
                    return msg, before and (memlimit.used() - before)
                end
                local function close_rights(msg)
                    for _, cm in ipairs(msg.cmsgs or {}) do
                        if type(cm.data) == 'number' then
                            assert(socket.close(cm.data))
                        else
                            for _, fd in ipairs(cm.data) do
                                assert(socket.close(fd))
                            end
                        end
                    end
                end
                collectgarbage('collect')
                collectgarbage('collect')
                collectgarbage('stop')
                if budget then collectgarbage('restart') end
                local success, result, allocated = pcall(invoke)
                memlimit.maxsize(0)
                collectgarbage('restart')
                collectgarbage('collect')
                if success then
                    assert(result.data == 'x')
                    assert(result.flags.ctrunc)
                    close_rights(result)
                end
                -- Check only the first possible copied FD. Descriptors the
                -- kernel never copied into the buffer are outside our scope.
                local leaked, err = socket.close(received_fd)
                if not leaked then assert(err.type.code == errno.EBADF.code) end
                local pending, perr, again = b:recvmsg(1, 128)
                assert(not perr)
                if pending then
                    close_rights(pending)
                else
                    assert(again)
                end
                assert(a:getsockname())
                assert(b:getsockname())
                a:close()
                b:close()
                return success, success and 'ok' or result,
                    leaked == true, pending == nil, allocated, #padding
            ]]))
            local lower, upper, budget = 0
            while true do
                local ok, success, result, leaked, consumed, allocated = L:run(budget)
                assert(ok, result)
                assert.is_false(leaked)
                if success then
                    assert.equal(result, 'ok')
                    assert.is_true(consumed)
                    upper = budget or allocated
                    assert.greater(upper, 0)
                else
                    assert.equal(result, 'not enough memory')
                    if consumed then
                        break
                    end
                    lower = budget
                end
                assert.greater(upper - lower, 1,
                               'no budget caused OOM after recvmsg consumed data')
                budget = math.floor((lower + upper) / 2)
            end
        end)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end
