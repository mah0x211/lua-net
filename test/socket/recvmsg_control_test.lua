local fileno = require('io.fileno')
local fopen = require('io.fopen')
local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')

local RECEIVED_MSG

function testcase.after_each()
    if RECEIVED_MSG then
        for _, cm in ipairs(RECEIVED_MSG.cmsgs or {}) do
            if cm.level == 'socket' and cm.type == 'rights' then
                if type(cm.data) == 'number' then
                    socket.close(cm.data)
                else
                    for _, fd in ipairs(cm.data) do
                        socket.close(fd)
                    end
                end
            end
        end
        RECEIVED_MSG = nil
    end
end

function testcase.recvmsg_reports_control_truncation()
    -- When the kernel drops part of the ancillary data because the caller's
    -- cmsg buffer was too small, it sets MSG_CTRUNC on msg_flags to warn
    -- the caller not to trust the delivered cmsg set.  Expose that
    -- indication through the returned msg table so callers can react
    -- (for example by refusing to consume half of an SCM_RIGHTS batch).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())

    local len = assert(a:sendmsg('x', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = {
                fileno(f),
                fileno(f),
                fileno(f),
                fileno(f),
            },
        },
    }))
    assert.equal(len, 1)

    -- 8 bytes is smaller than any well-formed SCM_RIGHTS cmsg, so the
    -- kernel truncates the ancillary data and sets MSG_CTRUNC.
    local msg = assert(b:recvmsg(1, 8))
    RECEIVED_MSG = msg
    assert.equal(msg.data, 'x')
    assert(msg.flags, 'recvmsg must report msg_flags')
    assert.is_true(msg.flags.ctrunc)

    f:close()
    a:close()
    b:close()
end

function testcase.recvmsg_reports_no_truncation_when_buffers_fit()
    -- The complement of recvmsg_reports_control_truncation: with cmsg
    -- buffers large enough to receive the full ancillary data, msg.flags
    -- omits both truncation flags.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())
    assert(f:write('received file'))
    assert(f:flush())

    assert(a:sendmsg('y', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = fileno(f),
        },
    }))

    local msg = assert(b:recvmsg(1, 128))
    RECEIVED_MSG = msg
    assert.equal(msg.data, 'y')
    assert(msg.flags, 'recvmsg must report msg_flags')
    -- No truncation flags should be present on the returned table.
    assert.is_nil(msg.flags.trunc)
    assert.is_nil(msg.flags.ctrunc)
    assert.equal(#msg.cmsgs, 1)
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'socket')
    assert.equal(cm.type, 'rights')
    assert.is_int(cm.data)
    -- fopen duplicates the fd; after_each retains ownership of the original.
    local received = assert(fopen(cm.data, 'r'))
    assert(received:seek('set', 0))
    assert.equal(received:read('*a'), 'received file')
    received:close()

    f:close()
    a:close()
    b:close()
end

function testcase.recvmsg_cmsg_socket_scm_timestamp()
    -- test that a SCM_TIMESTAMP cmsg delivered via SO_TIMESTAMP is exposed
    -- as { level='socket', type='timestamp', data={sec=..., usec=...} }
    -- by push_data()'s SCM_TIMESTAMP branch.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local prev, err = server:timestamp(true)
    assert.is_boolean(prev)
    assert.is_nil(err)
    local enabled
    enabled, err = server:timestamp()
    assert.is_true(enabled)
    assert.is_nil(err)
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    assert(client:sendmsg('t', sai))
    assert(server:recvable(1))
    local msg = assert(server:recvmsg(1, 256))
    assert.equal(msg.data, 't')
    assert(msg.cmsgs and #msg.cmsgs > 0, 'SCM_TIMESTAMP cmsg should be present')
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'socket')
    assert.equal(cm.type, 'timestamp')
    assert.is_table(cm.data)
    assert.is_int(cm.data.sec)
    assert.is_int(cm.data.usec)
    assert.greater_or_equal(cm.data.usec, 0)
    assert.less(cm.data.usec, 1000000)

    client:close()
    server:close()
end
