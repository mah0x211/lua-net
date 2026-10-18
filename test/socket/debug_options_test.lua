local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local socket = require('net.socket')

local uname = assert(io.popen('uname -s'))
local OS = assert(uname:read('*l'))
assert(uname:close())

local EXTERNALLY_CLOSED_SOCKET

function testcase.after_each()
    if EXTERNALLY_CLOSED_SOCKET then
        -- The fd is already closed; discard stale ownership without closing
        -- a descriptor that may since have been reused.
        EXTERNALLY_CLOSED_SOCKET:unwrap()
        EXTERNALLY_CLOSED_SOCKET = nil
    end
end

function testcase.debug()
    -- Disabling SO_DEBUG does not require CAP_NET_ADMIN on Linux.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local prev, err = s:debug(false)
    assert.is_false(prev)
    assert.is_nil(err)
    local enabled
    enabled, err = s:debug()
    assert.is_false(enabled)
    assert.is_nil(err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    enabled, err = s:debug()
    assert.is_nil(enabled)
    assert(error_is(err, errno.EBADF))
    enabled, err = s:debug(true)
    assert.is_nil(enabled)
    assert(error_is(err, errno.EBADF))
end

if OS ~= 'Linux' then
    function testcase.debug_enable()
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        local prev, err = s:debug(true)
        assert.is_false(prev)
        assert.is_nil(err)
        local enabled
        enabled, err = s:debug()
        assert.is_true(enabled)
        assert.is_nil(err)
        prev, err = s:debug(false)
        assert.is_true(prev)
        assert.is_nil(err)
        enabled, err = s:debug()
        assert.is_false(enabled)
        assert.is_nil(err)
        s:close()
    end
else
    function testcase.debug_enable_denied()
        -- Linux tests run without CAP_NET_ADMIN.
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        local prev, err = s:debug(true)
        assert.is_nil(prev)
        assert(error_is(err, errno.EACCES))
        local enabled
        enabled, err = s:debug()
        assert.is_false(enabled)
        assert.is_nil(err)
        s:close()
    end
end
