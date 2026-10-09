local testcase = require('testcase')
local assert = require('assert')
local fileno = require('io.fileno')
local fopen = require('io.fopen')
local readdir = require('testcase.readdir')
local socket = require('net.socket')
local errno = require('errno')

local resources = {}

local function keep(value)
    resources[#resources + 1] = value
    return value
end

function testcase.after_each()
    for i = #resources, 1, -1 do
        resources[i]:close()
        resources[i] = nil
    end
end

local function pair(socktype)
    local socks = assert(socket.pair({
        socktype = socktype,
    }))
    return keep(socks[1]), keep(socks[2])
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

function testcase.recvfd_returns_scm_rights()
    local a, b = pair('stream')
    local f = keep(assert(io.tmpfile()))
    assert(a:sendfd(fileno(f)))
    local q, err, again = b:recvfd()
    assert.is_userdata(q)
    keep(q)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(q:len(), 1)
    assert.is_nil(q:close())
    assert.equal(q:len(), 0)
    assert.is_nil(q:peek())
    assert.is_nil(q:get())
    assert.is_nil(q:close())
end

function testcase.peek_preserves_get_transfers_in_order()
    for _, socktype in ipairs({
        'stream',
        'dgram',
    }) do
        local a, b = pair(socktype)
        local first = keep(assert(io.tmpfile()))
        local second = keep(assert(io.tmpfile()))
        assert(first:write('first'))
        assert(first:flush())
        assert(second:write('second'))
        assert(second:flush())
        assert(a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = {
                    fileno(first),
                    fileno(second),
                },
            },
        }))
        local q = keep(assert(b:recvfd()))
        assert.equal(q:len(), 2)
        local peeked = assert(q:peek())
        assert.equal(q:peek(), peeked)
        assert.equal(q:len(), 2)
        local fd = assert(q:get())
        assert.equal(fd, peeked)
        assert.equal(q:len(), 1)
        local f1 = keep(assert(fopen(fd, 'r')))
        local f2 = keep(assert(fopen(assert(q:get()), 'r')))
        assert.equal(q:len(), 0)
        assert.is_nil(q:get())
        assert.is_nil(q:peek())
        assert.is_nil(q:close())
        assert(f1:seek('set', 0))
        assert(f2:seek('set', 0))
        assert.equal(f1:read('*a'), 'first')
        assert.equal(f2:read('*a'), 'second')
    end
end

function testcase.close_releases_only_unclaimed_fds()
    local a, b = pair('stream')
    local f = keep(assert(io.tmpfile()))
    local before = count_fds()
    assert(a:sendmsg('x', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = {
                fileno(f),
                fileno(f),
                fileno(f),
            },
        },
    }))
    local q = keep(assert(b:recvfd()))
    assert.equal(q:len(), 3)
    assert.equal(count_fds(), before + 3)
    local fd = assert(q:get())
    assert.is_nil(q:close())
    assert.equal(count_fds(), before + 1)
    assert.equal(q:len(), 0)
    assert.is_nil(q:close())
    assert(socket.close(fd))
    assert.equal(count_fds(), before)
end

function testcase.gc_releases_only_unclaimed_fds()
    local a, b = pair('dgram')
    local f = keep(assert(io.tmpfile()))
    local before = count_fds()
    assert(a:sendmsg('x', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = {
                fileno(f),
                fileno(f),
            },
        },
    }))
    local fd
    do
        local q = assert(b:recvfd())
        assert.equal(q:len(), 2)
        fd = assert(q:get())
    end
    collectgarbage('collect')
    assert.equal(count_fds(), before + 1)
    assert(socket.close(fd))
    assert.equal(count_fds(), before)
end

function testcase.close_continues_after_descriptor_was_closed_externally()
    local a, b = pair('stream')
    local f = keep(assert(io.tmpfile()))
    local before = count_fds()
    assert(a:sendmsg('x', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = {
                fileno(f),
                fileno(f),
                fileno(f),
            },
        },
    }))
    local q = keep(assert(b:recvfd()))
    assert.equal(q:len(), 3)
    -- Deliberately violate the borrowing contract to exercise close failure.
    assert(socket.close(assert(q:peek())))
    local err = q:close()
    assert.equal(err.type, errno.EBADF)
    assert.equal(q:len(), 0)
    assert.is_nil(q:close())
    assert.equal(count_fds(), before)
end

function testcase.recvfd_receives_platform_capacity()
    local fp = io.open('/proc/version')
    local capacity = fp and 253 or 254
    if fp then
        fp:close()
    end
    for _, socktype in ipairs({
        'stream',
        'dgram',
    }) do
        local a, b = pair(socktype)
        local f = keep(assert(io.tmpfile()))
        local fds = {}
        for i = 1, capacity do
            fds[i] = fileno(f)
        end
        local before = count_fds()
        assert(a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = fds,
            },
        }))
        local q = keep(assert(b:recvfd()))
        assert.equal(q:len(), capacity)
        assert.equal(count_fds(), before + capacity)
        assert.is_nil(q:close())
        assert.equal(count_fds(), before)
    end
end

function testcase.recvfd_sets_cloexec_on_all_fds()
    local a, b = pair('stream')
    local f = keep(assert(io.tmpfile()))
    assert(a:sendmsg('x', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = {
                fileno(f),
                fileno(f),
            },
        },
    }))
    local q = keep(assert(b:recvfd()))
    assert.equal(q:len(), 2)
    for _ = 1, 2 do
        local fd = assert(q:get())
        local rv = os.execute(string.format(
                                  'test -e /dev/fd/%d && exit 1 || exit 0', fd))
        assert(socket.close(fd))
        assert(rv == true or rv == 0)
    end
end

function testcase.recvfd_rejects_peek_without_consuming_message()
    local a, b = pair('stream')
    local f = keep(assert(io.tmpfile()))
    assert(a:sendfd(fileno(f)))
    local err = assert.throws(b.recvfd, b, 'peek')
    assert.match(err, 'peek')
    local q = keep(assert(b:recvfd()))
    assert.equal(q:len(), 1)
    assert.is_nil(q:close())
end
