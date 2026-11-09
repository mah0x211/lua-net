local fileno = require('io.fileno')
local fopen = require('io.fopen')
local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local socket = require('net.socket')

local uname = assert(io.popen('uname -s'))
local OS = assert(uname:read('*l'))
assert(uname:close())

local RECEIVED_MSG

function testcase.after_each()
    if RECEIVED_MSG then
        for _, cm in ipairs(RECEIVED_MSG.cmsgs or {}) do
            if cm.level == 'socket' and cm.type == 'rights' then
                cm.data:close()
            end
        end
        RECEIVED_MSG = nil
    end
end

function testcase.sendmsg_cmsg_socket_fd_passing()
    -- Round-trip a single file descriptor via SCM_RIGHTS ancillary data
    -- on a unix stream socketpair.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())
    assert(f:write('single file'))
    assert(f:flush())

    -- test that sendmsg with cmsg passes an fd via SCM_RIGHTS
    local len = assert(a:sendmsg('x', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = fileno(f),
        },
    }))
    assert.equal(len, 1)

    local msg = assert(b:recvmsg(1, 128))
    RECEIVED_MSG = msg
    assert.equal(msg.data, 'x')
    assert.equal(#msg.cmsgs, 1)
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'socket')
    assert.equal(cm.type, 'rights')
    assert.is_userdata(cm.data)
    assert.equal(cm.data:len(), 1)
    local received = assert(fopen(cm.data:peek(), 'r'))
    assert(received:seek('set', 0))
    assert.equal(received:read('*a'), 'single file')
    received:close()

    f:close()
    a:close()
    b:close()
end

function testcase.sendmsg_cmsg_socket_multiple_fds()
    -- Round-trip an array of file descriptors via SCM_RIGHTS in one
    -- ancillary data element (data = { fd1, fd2, ... }).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local files = {
        assert(io.tmpfile()),
        assert(io.tmpfile()),
    }
    assert(files[1]:write('first file'))
    assert(files[1]:flush())
    assert(files[2]:write('second file'))
    assert(files[2]:flush())

    -- test that sendmsg with a table of fds passes multiple fds via SCM_RIGHTS
    local len = assert(a:sendmsg('y', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = {
                fileno(files[1]),
                fileno(files[2]),
            },
        },
    }))
    assert.equal(len, 1)

    local msg = assert(b:recvmsg(1, 256))
    RECEIVED_MSG = msg
    assert.equal(msg.data, 'y')
    assert.equal(#msg.cmsgs, 1)
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'socket')
    assert.equal(cm.type, 'rights')
    assert.is_userdata(cm.data)
    assert.equal(cm.data:len(), 2)
    for _, expected in ipairs({
        'first file',
        'second file',
    }) do
        local received = assert(fopen(cm.data:peek(), 'r'))
        assert(socket.close(assert(cm.data:get())))
        assert(received:seek('set', 0))
        assert.equal(received:read('*a'), expected)
        received:close()
    end

    files[1]:close()
    files[2]:close()
    a:close()
    b:close()
end

function testcase.sendmsg_cmsg_socket_only_send()
    -- Unix datagrams can carry SCM_RIGHTS without a data payload.
    local socks = assert(socket.pair({
        socktype = 'dgram',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())
    assert(f:write('control only'))
    assert(f:flush())
    local rv, err, again, sent = a:sendmsg('', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = fileno(f),
        },
    })
    assert.equal(rv, 0)
    assert.is_nil(err)
    assert.is_false(again)
    assert.is_true(sent)
    assert(b:recvable(1))
    local msg = assert(b:recvmsg(1, 128))
    RECEIVED_MSG = msg
    assert.equal(msg.data, '')
    assert.equal(#msg.cmsgs, 1)
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'socket')
    assert.equal(cm.type, 'rights')
    assert.is_userdata(cm.data)
    assert.equal(cm.data:len(), 1)
    local received = assert(fopen(cm.data:peek(), 'r'))
    assert(received:seek('set', 0))
    assert.equal(received:read('*a'), 'control only')
    received:close()
    f:close()
    a:close()
    b:close()
end

if OS == 'Darwin' then
    function testcase.sendmsg_cmsg_nil_payload_rejects_missing_iov()
        -- XNU rejects msg_iovlen=0 before inspecting the control buffer.
        local socks = assert(socket.pair({
            socktype = 'dgram',
        }))
        local a, b = socks[1], socks[2]
        local f = assert(io.tmpfile())
        local n, err, again = a:sendmsg(nil, nil, {
            {
                level = 'socket',
                type = 'rights',
                data = fileno(f),
            },
        })
        assert.is_nil(n)
        assert(error_is(err, errno.EMSGSIZE))
        assert.is_nil(again)
        f:close()
        a:close()
        b:close()
    end
elseif OS == 'Linux' then
    function testcase.sendmsg_cmsg_nil_payload_delivers_rights()
        local socks = assert(socket.pair({
            socktype = 'dgram',
        }))
        local a, b = socks[1], socks[2]
        local f = assert(io.tmpfile())
        assert(f:write('nil payload'))
        assert(f:flush())
        local n, err, again, sent = a:sendmsg(nil, nil, {
            {
                level = 'socket',
                type = 'rights',
                data = fileno(f),
            },
        })
        assert.equal(n, 0)
        assert.is_nil(err)
        assert.is_false(again)
        assert.is_true(sent)
        assert(b:recvable(1))
        local msg = assert(b:recvmsg(1, 128))
        RECEIVED_MSG = msg
        assert.equal(msg.data, '')
        assert.equal(#msg.cmsgs, 1)
        local cm = msg.cmsgs[1]
        assert.equal(cm.level, 'socket')
        assert.equal(cm.type, 'rights')
        assert.is_userdata(cm.data)
        assert.equal(cm.data:len(), 1)
        local received = assert(fopen(cm.data:peek(), 'r'))
        assert(received:seek('set', 0))
        assert.equal(received:read('*a'), 'nil payload')
        received:close()
        f:close()
        a:close()
        b:close()
    end
end

if OS == 'Linux' then
    function testcase.sendmsg_cmsg_concatenates_multiple_entries()
        -- Both independent entries must arrive, even if the kernel merges
        -- their SCM_RIGHTS payloads into a single received cmsg.
        local socks = assert(socket.pair({
            socktype = 'stream',
        }))
        local a, b = socks[1], socks[2]
        local files = {
            assert(io.tmpfile()),
            assert(io.tmpfile()),
        }
        assert(files[1]:write('first entry'))
        assert(files[1]:flush())
        assert(files[2]:write('second entry'))
        assert(files[2]:flush())
        local len, err, again = a:sendmsg('m', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = fileno(files[1]),
            },
            {
                level = 'socket',
                type = 'rights',
                data = fileno(files[2]),
            },
        })
        assert.equal(len, 1)
        assert.is_nil(err)
        assert.is_false(again)

        local msg = assert(b:recvmsg(1, 256))
        RECEIVED_MSG = msg
        assert.equal(msg.data, 'm')
        local fds = {}
        for _, cm in ipairs(msg.cmsgs) do
            assert.equal(cm.level, 'socket')
            assert.equal(cm.type, 'rights')
            assert.is_userdata(cm.data)
            while cm.data:len() > 0 do
                fds[#fds + 1] = assert(cm.data:get())
            end
        end
        assert.equal(#fds, 2)
        for i, expected in ipairs({
            'first entry',
            'second entry',
        }) do
            assert.is_int(fds[i])
            local received = assert(fopen(fds[i], 'r'))
            assert(socket.close(fds[i]))
            assert(received:seek('set', 0))
            assert.equal(received:read('*a'), expected)
            received:close()
        end
        files[1]:close()
        files[2]:close()
        a:close()
        b:close()
    end
elseif OS == 'Darwin' then
    function testcase.sendmsg_cmsg_rejects_multiple_rights_entries()
        -- XNU requires one SCM_RIGHTS header to cover the control buffer.
        local socks = assert(socket.pair({
            socktype = 'stream',
        }))
        local a, b = socks[1], socks[2]
        local f = assert(io.tmpfile())
        local n, err, again = a:sendmsg('m', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = fileno(f),
            },
            {
                level = 'socket',
                type = 'rights',
                data = fileno(f),
            },
        })
        assert.is_nil(n)
        assert(error_is(err, errno.EINVAL))
        assert.is_nil(again)
        f:close()
        a:close()
        b:close()
    end
end
