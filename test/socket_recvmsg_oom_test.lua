local testcase = require('testcase')
local assert = require('assert')
local newstate = require('newstate')
-- Keep the native module loaded while the isolated states are collected.
require('net.socket')

function testcase.recvmsg_oom_closes_all_received_fds()
    local L = assert(newstate.new())
    assert(L:loadstring([[
        local nfd, budget, sender_path, receiver_path = ...
        local socket = require('net.socket')
        local errno = require('errno')
        local memlimit = require('memlimit')
        local pair = {
            assert(socket.bind_unix(sender_path, {socktype = 'dgram'})),
            assert(socket.bind_unix(receiver_path, {socktype = 'dgram'})),
        }
        pair[2]:timestamp(true)
        assert(pair[2]:timestamp())
        local receiver_addr = assert(pair[2]:getsockname())
        local function close_received_fds(msg)
            local count = 0
            for _, cm in ipairs(msg.cmsgs) do
                if cm.level == 'socket' and cm.type == 'rights' then
                    if type(cm.data) == 'number' then
                        assert(socket.close(cm.data))
                        count = count + 1
                    else
                        for _, fd in ipairs(cm.data) do
                            assert(socket.close(fd))
                            count = count + 1
                        end
                    end
                end
            end
            return count
        end
        local fds = {}
        for i = 1, nfd do
            fds[i] = pair[1]:fd()
        end
        assert(pair[1]:sendmsg('x', receiver_addr, {{
            level = 'socket',
            type = 'rights',
            data = fds,
        }}))
        local padding = string.rep('a', memlimit.minsize())
        -- recvmsg() must reuse these lowest available descriptors.
        local probes = {}
        local expected_fds = {}
        for i = 1, nfd do
            probes[i] = assert(socket.new_inet({socktype = 'stream'}))
            expected_fds[i] = probes[i]:fd()
        end
        for _, probe in ipairs(probes) do
            assert(probe:close())
        end
        local function invoke()
            local before
            if budget then
                local _, limited = memlimit.maxsize(memlimit.used() + budget)
                assert(limited)
            else
                before = memlimit.used()
            end
            local msg = pair[2]:recvmsg(1, 256)
            return msg, before and (memlimit.used() - before)
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

        local checked, leaked, consumed = pcall(function()
            if success then
                assert(message.data == 'x')
                assert(message.addr:addr() == sender_path)
                assert(close_received_fds(message) == nfd)
            end

            -- Close any leaked descriptors before reporting a failure.
            local leaked = 0
            for _, fd in ipairs(expected_fds) do
                local closed, err = socket.close(fd)
                if closed then
                    leaked = leaked + 1
                else
                    assert(err.type.code == errno.EBADF.code)
                end
            end
            local pending, _, again = pair[2]:recvmsg(1, 256)
            if pending then
                assert(close_received_fds(pending) == nfd)
            else
                assert(again)
            end
            assert(pair[1]:sendmsg('alive', receiver_addr))
            assert(pair[2]:recvable(1))
            assert(pair[2]:recv(5) == 'alive')
            return leaked, pending == nil
        end)
        if not checked then
            -- recvmsg transfers raw descriptor ownership on success. Even
            -- a failed assertion must not leave those descriptors open.
            for _, fd in ipairs(expected_fds) do
                socket.close(fd)
            end
        end
        pair[1]:close()
        pair[2]:close()
        if not checked then
            error(leaked, 0)
        end
        return success, success and 'ok' or message, leaked,
            consumed, allocated, #padding
    ]]))
    for _, nfd in ipairs({
        1,
        3,
    }) do
        local lower = 0
        local upper
        local budget
        while true do
            local sender_path = os.tmpname()
            local receiver_path = os.tmpname()
            os.remove(sender_path)
            os.remove(receiver_path)
            local ok, success, message, leaked, consumed, allocated = L:run(nfd,
                                                                            budget,
                                                                            sender_path,
                                                                            receiver_path)
            os.remove(sender_path)
            os.remove(receiver_path)
            assert(ok,
                   string.format(
                       'test VM failed: nfd=%d budget=%s status=%s error=%s',
                       nfd, tostring(budget), tostring(message),
                       tostring(success)))
            assert.equal(leaked, 0)
            if success then
                assert.equal(message, 'ok')
                assert.is_true(consumed)
                if budget then
                    upper = budget
                else
                    assert.greater(allocated, 0)
                    upper = allocated
                end
            else
                assert.equal(message, 'not enough memory')
                if consumed then
                    break
                end
                lower = budget
            end
            assert(upper - lower > 1,
                   'no allocation budget produced OOM after receiving descriptors')
            budget = math.floor((lower + upper) / 2)
        end
    end
end
