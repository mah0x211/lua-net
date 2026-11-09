local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local socket = require('net.socket')

local uname = assert(io.popen('uname -s'))
local OS = assert(uname:read('*l'))
assert(uname:close())

if OS == 'Linux' then
    function testcase.sendmsg_rejects_invalid_credentials_length()
        local socks = assert(socket.pair({
            socktype = 'stream',
        }))
        local a = socks[1]
        local b = socks[2]

        -- SCM_CREDENTIALS requires a complete struct ucred payload.
        local len, err, again = a:sendmsg('c', nil, {
            {
                level = 'socket',
                type = 'credentials',
                data = '',
            },
        })
        assert.is_nil(len)
        assert(error_is(err, errno.EINVAL))
        assert.is_nil(again)

        a:close()
        b:close()
    end
end

function testcase.sendmsg_cmsg_invalid_arguments()
    -- cmsg entries must be tables with a valid `level`, `type`, and
    -- `data` field.  Malformed entries surface a Lua error.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- test that a non-table cmsg entry raises
    local err = assert.throws(function()
        a:sendmsg('x', nil, {
            'not a table',
        })
    end)
    assert.match(err, 'must be a table', false)

    -- test that a non-string level raises
    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 1,
                type = 'rights',
                data = 0,
            },
        })
    end)
    assert.match(err, 'level must be a string', false)

    -- test that an unknown level raises
    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'unknownlevel',
                type = 'rights',
                data = 0,
            },
        })
    end)
    assert.match(err, 'unknown level', false)

    -- test that a non-string type raises
    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 1,
                data = 0,
            },
        })
    end)
    assert.match(err, 'type must be a string', false)

    -- test that an unknown type for the given level raises
    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'unknowntype',
                data = 0,
            },
        })
    end)
    assert.match(err, 'unknown type', false)

    -- test that SCM_RIGHTS data with a wrong type raises
    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = 'not an fd',
            },
        })
    end)
    assert.match(err, 'SCM_RIGHTS requires integer fd', false)

    -- test that non-integer entries in the fd table raise
    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = {
                    'not fd',
                },
            },
        })
    end)
    assert.match(err, 'must be integer fd', false)

    -- test that too many fds in a single SCM_RIGHTS entry raises
    local fds = {}
    for i = 1, 300 do
        fds[i] = i
    end
    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = fds,
            },
        })
    end)
    assert.match(err, 'too many fds', false)

    -- test that a non-string data raises when the (level, type) pair is not
    -- SCM_RIGHTS (i.e., the raw-string branch of write_cmsg_entry)
    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'ip',
                type = 'ttl',
                data = 42,
            },
        })
    end)
    assert.match(err, 'string expected', false)

    a:close()
    b:close()
end

function testcase.sendmsg_cmsg_supports_control_block_beyond_stack_cap()
    -- write_cmsg_entry historically wrote each cmsg entry into a fixed
    -- 4 KiB stack control buffer inside sendmsg_lua, so a raw cmsg whose
    -- CMSG_SPACE exceeded 4 KiB failed with a client-side "buffer
    -- overflow" Lua error.  Ancillary data is now assembled as a Lua
    -- string per entry and concatenated, so a >4 KiB raw cmsg is passed
    -- through to sendmsg(2) instead of being rejected before the call.
    -- The kernel is free to accept or reject the oversized cmsg (a wrong-
    -- size IP_TTL typically surfaces EINVAL); what matters is that no
    -- Lua exception with the old "buffer overflow" message is raised.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- Kernel acceptance is not the oracle, but either outcome must return
    -- a length or an error without raising a Lua exception.
    local ok, len, err = pcall(a.sendmsg, a, 'x', nil, {
        {
            level = 'ip',
            type = 'ttl',
            data = string.rep('x', 5000),
        },
    })
    assert.is_true(ok)
    assert(len or err)

    a:close()
    b:close()
end

function testcase.sendmsg_cmsg_invalid_unknown_type_on_tcp_level()
    -- When `level` has no symbolic type map (e.g. IPPROTO_TCP), any
    -- `type` name is unknown and cmsg parsing raises a Lua error.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- test that a type name is rejected when the level has no symbolic map
    -- (level='tcp' does not have a type map, so any type name is unknown).
    local err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'tcp',
                type = 'unknown',
                data = 'raw',
            },
        })
    end)
    assert.match(err, 'unknown type', false)

    a:close()
    b:close()
end
