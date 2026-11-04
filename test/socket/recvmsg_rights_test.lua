local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local errno = require('errno')
local fileno = require('io.fileno')
local fopen = require('io.fopen')
local readdir = require('testcase.readdir')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local uname = assert(io.popen('uname -s'))
local OS = assert(uname:read('*l'))
assert(uname:close())

local function isolated(fn)
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            collectgarbage('collect')
            collectgarbage('collect')
            fn()
        end)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

local function count_fds()
    local n = 0
    readdir('/dev/fd', function(name)
        if tonumber(name) then
            n = n + 1
        end
    end)
    return n
end

function testcase.recvmsg_rights_peek_get_and_close_preserve_ownership()
    isolated(function()
        local pair = assert(socket.pair({socktype = 'stream'}))
        local a, b = pair[1], pair[2]
        local first, second = assert(io.tmpfile()), assert(io.tmpfile())
        assert(first:write('first'))
        assert(first:flush())
        assert(second:write('second'))
        assert(second:flush())
        local before = count_fds()
        assert(a:sendmsg('x', nil, {{
            level = 'socket', type = 'rights',
            data = {fileno(first), fileno(second)},
        }}))
        local fd
        do
            local msg = assert(b:recvmsg(1, 256))
            assert.equal(msg.data, 'x')
            local q = msg.cmsgs[1].data
            assert.is_userdata(q)
            assert.equal(q:len(), 2)
            assert.equal(count_fds(), before + 2)
            local borrowed = assert(q:peek())
            assert.equal(q:peek(), borrowed)
            assert.equal(q:len(), 2)
            fd = assert(q:get())
            assert.equal(fd, borrowed)
            local file = assert(fopen(fd, 'r'))
            assert(file:seek('set', 0))
            assert.equal(file:read('*a'), 'first')
            assert(file:close())
            local remaining = assert(q:peek())
            file = assert(fopen(remaining, 'r'))
            assert(file:seek('set', 0))
            assert.equal(file:read('*a'), 'second')
            assert(file:close())
            assert.is_nil(q:close())
            assert.equal(q:len(), 0)
            assert.is_nil(q:get())
            assert.is_nil(q:peek())
            assert.is_nil(q:close())
            assert.equal(count_fds(), before + 1)
            local closed, err = socket.close(remaining)
            assert.is_false(closed)
            assert.equal(err.type, errno.EBADF)
        end
        collectgarbage('collect')
        -- The extracted FD remains owned by the caller after queue GC.
        local file = assert(fopen(fd, 'r'))
        assert(file:seek('set', 0))
        assert.equal(file:read('*a'), 'first')
        assert(file:close())
        assert(socket.close(fd))
        assert.equal(count_fds(), before)
        first:close()
        second:close()
        a:close()
        b:close()
    end)
end

function testcase.recvmsg_rights_queue_owns_large_batch()
    isolated(function()
        local pair = assert(socket.pair({socktype = 'dgram'}))
        local a, b = pair[1], pair[2]
        local f = assert(io.tmpfile())
        local capacity = OS == 'Linux' and 253 or 254
        local fds = {}
        for i = 1, capacity do fds[i] = fileno(f) end
        local before = count_fds()
        assert(a:sendmsg('x', nil, {{
            level = 'socket', type = 'rights', data = fds,
        }}))
        do
            local msg = assert(b:recvmsg(1, 4096))
            assert.is_nil(msg.flags.ctrunc)
            assert.equal(msg.cmsgs[1].data:len(), capacity)
            assert.equal(count_fds(), before + capacity)
        end
        collectgarbage('collect')
        assert.equal(count_fds(), before)
        f:close()
        a:close()
        b:close()
    end)
end

function testcase.recvmsg_rights_gc_preserves_extracted_fd()
    isolated(function()
        local pair = assert(socket.pair({socktype = 'stream'}))
        local a, b = pair[1], pair[2]
        local f = assert(io.tmpfile())
        assert(f:write('claimed fd'))
        assert(f:flush())
        local before = count_fds()
        assert(a:sendmsg('x', nil, {{
            level = 'socket', type = 'rights', data = {fileno(f), fileno(f)},
        }}))
        local fd
        do
            local msg = assert(b:recvmsg(1, 256))
            assert.equal(msg.cmsgs[1].data:len(), 2)
            fd = assert(msg.cmsgs[1].data:get())
            assert.equal(msg.cmsgs[1].data:len(), 1)
            assert.equal(count_fds(), before + 2)
        end
        collectgarbage('collect')
        assert.equal(count_fds(), before + 1)
        local file = assert(fopen(fd, 'r'))
        assert(file:seek('set', 0))
        assert.equal(file:read('*a'), 'claimed fd')
        assert(file:close())
        assert(socket.close(fd))
        assert.equal(count_fds(), before)
        f:close()
        a:close()
        b:close()
    end)
end

function testcase.recvmsg_rights_gc_closes_discarded_and_error_results()
    isolated(function()
        local pair = assert(socket.pair({socktype = 'dgram'}))
        local a, b = pair[1], pair[2]
        local f = assert(io.tmpfile())
        local before = count_fds()
        assert(a:sendmsg('x', nil, {{
            level = 'socket', type = 'rights', data = {fileno(f), fileno(f)},
        }}))
        do
            local msg = assert(b:recvmsg(1, 256))
            assert.equal(msg.cmsgs[1].data:len(), 2)
            assert.equal(count_fds(), before + 2)
        end
        collectgarbage('collect')
        assert.equal(count_fds(), before)
        assert(a:sendmsg('x', nil, {{
            level = 'socket', type = 'rights', data = {fileno(f), fileno(f)},
        }}))
        local ok, err = pcall(function()
            local received = assert(b:recvmsg(1, 256))
            assert.equal(received.cmsgs[1].data:len(), 2)
            assert.equal(count_fds(), before + 2)
            error('discard after recvmsg', 0)
        end)
        assert.is_false(ok)
        assert.equal(err, 'discard after recvmsg')
        collectgarbage('collect')
        assert.equal(count_fds(), before)
        f:close()
        a:close()
        b:close()
    end)
end

-- Linux supplies timestamps for UNIX datagrams; Darwin does not.
if OS == 'Linux' then
    function testcase.recvmsg_rights_queue_preserves_other_control_messages()
        isolated(function()
            local pair = assert(socket.pair({socktype = 'dgram'}))
            local a, b = pair[1], pair[2]
            local previous, err = b:timestamp(true)
            assert.is_boolean(previous)
            assert.is_nil(err)
            assert.is_true(b:timestamp())
            local f = assert(io.tmpfile())
            assert(f:write('mixed control'))
            assert(f:flush())
            local before = count_fds()
            assert(a:sendmsg('x', nil, {{
                level = 'socket', type = 'rights', data = fileno(f),
            }}))
            local msg = assert(b:recvmsg(1, 256))
            assert.equal(msg.data, 'x')
            assert.is_nil(msg.flags.ctrunc)
            local rights, timestamps = 0, 0
            for _, cm in ipairs(msg.cmsgs) do
                assert.equal(cm.level, 'socket')
                if cm.type == 'rights' then
                    assert.is_userdata(cm.data)
                    assert.equal(cm.data:len(), 1)
                    local file = assert(fopen(cm.data:peek(), 'r'))
                    assert(file:seek('set', 0))
                    assert.equal(file:read('*a'), 'mixed control')
                    assert(file:close())
                    rights = rights + cm.data:len()
                    assert.is_nil(cm.data:close())
                else
                    assert.equal(cm.type, 'timestamp')
                    assert.is_table(cm.data)
                    assert.is_int(cm.data.sec)
                    assert.is_int(cm.data.usec)
                    timestamps = timestamps + 1
                end
            end
            assert.equal(rights, 1)
            assert.equal(timestamps, 1)
            assert.equal(count_fds(), before)
            f:close()
            a:close()
            b:close()
        end)
    end
end
