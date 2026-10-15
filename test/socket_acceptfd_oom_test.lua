local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local newstate = require('newstate')
-- Keep the native module loaded while the isolated states are collected.
require('net.socket')

function testcase.acceptfd_with_addr_oom_closes_accepted_fd()
    local L = assert(newstate.new())
    assert(L:loadstring([[
        local budget = ...
        local socket = require('net.socket')
        local memlimit = require('memlimit')
        local server = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
        }))
        assert(server:listen())
        local addr = assert(server:getsockname())
        local client = assert(socket.connect_inet('127.0.0.1', addr:port(), {
            socktype = 'stream',
            protocol = 'tcp',
        }))
        assert(server:recvable(1))
        local padding = string.rep('a', memlimit.minsize())
        -- Reserve and release the lowest available descriptor. No other
        -- descriptor is opened before acceptfd(), which must reuse it.
        local probe = assert(socket.new_inet({socktype = 'stream'}))
        local expected_fd = probe:fd()
        assert(probe:close())
        local function invoke()
            local before
            if budget then
                local _, limited = memlimit.maxsize(memlimit.used() + budget)
                assert(limited)
            else
                before = memlimit.used()
            end
            local fd, _, _, peer_addr = server:acceptfd(true)
            local allocated = before and (memlimit.used() - before)
            return fd, allocated, peer_addr
        end
        collectgarbage('collect')
        collectgarbage('collect')
        collectgarbage('stop')
        if budget then
            collectgarbage('restart')
        end
        local success, message, allocated = pcall(invoke)
        memlimit.maxsize(0)
        collectgarbage('restart')
        collectgarbage('collect')

        if success then
            assert(socket.close(message))
        end

        -- Also close the descriptor on the unfixed implementation so that
        -- a failing regression test does not itself leave it open.
        local closed, close_error = socket.close(expected_fd)
        local pending, _, again = server:acceptfd()
        if pending then
            assert(socket.close(pending))
        end
        assert(client:getsockname())
        client:close()
        server:close()
        return success, message, closed,
            close_error and close_error.type.code, pending, again, allocated, #padding
    ]]))
    local lower = 0
    local upper
    local budget
    while true do
        local ok, success, message, closed, close_error, pending, again,
              allocated = L:run(budget)
        assert(ok, string.format('test VM failed: budget=%s status=%s error=%s',
                                 tostring(budget), tostring(message),
                                 tostring(success)))
        assert.is_false(closed)
        assert.equal(close_error, errno.EBADF.code)
        if success then
            assert.is_number(message)
            assert.is_nil(pending)
            assert.is_true(again)
            if budget then
                upper = budget
            else
                assert.greater(allocated, 0)
                upper = allocated
            end
        else
            assert.equal(message, 'not enough memory')
            if not pending then
                assert.is_true(again)
                break
            end
            lower = budget
        end
        assert(upper - lower > 1,
               'no allocation budget produced OOM after accepting the connection')
        budget = math.floor((lower + upper) / 2)
    end
end
