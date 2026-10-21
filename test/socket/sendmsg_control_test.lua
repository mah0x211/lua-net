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
    assert.is_int(cm.data)
    local received = assert(fopen(cm.data, 'r'))
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
    assert.is_table(cm.data)
    assert.equal(#cm.data, 2)
    for i, expected in ipairs({
        'first file',
        'second file',
    }) do
        assert.is_int(cm.data[i])
        local received = assert(fopen(cm.data[i], 'r'))
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
    assert.is_int(cm.data)
    local received = assert(fopen(cm.data, 'r'))
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
        assert.is_int(cm.data)
        local received = assert(fopen(cm.data, 'r'))
        assert(received:seek('set', 0))
        assert.equal(received:read('*a'), 'nil payload')
        received:close()
        f:close()
        a:close()
        b:close()
    end
end

function testcase.sendmsg_cmsg_ip_tos_udp()
    -- A per-message TOS must reach the peer, not just serialize successfully.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local previous, opt_err = server:ip_recvtos(true)
    assert.is_boolean(previous)
    assert.is_nil(opt_err)
    local enabled
    enabled, opt_err = server:ip_recvtos()
    assert.is_true(enabled)
    assert.is_nil(opt_err)
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    local tos_bytes = string.char(16, 0, 0, 0)
    assert.equal(client:sendmsg('b', sai), 1)
    assert(server:recvable(1))
    local baseline = assert(server:recvmsg(1, 128))
    assert.equal(baseline.data, 'b')
    assert.not_equal(baseline.cmsgs[1].data:byte(1), 16)
    local len, err, again = client:sendmsg('q', sai, {
        {
            level = 'ip',
            type = 'tos',
            data = tos_bytes,
        },
    })
    assert.equal(len, 1)
    assert.is_nil(err)
    assert.is_false(again)

    assert(server:recvable(1))
    local msg = assert(server:recvmsg(1, 128))
    assert.equal(msg.data, 'q')
    assert(msg.cmsgs and #msg.cmsgs > 0, 'received TOS cmsg should be present')
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'ip')
    assert(type(cm.type) == 'string' or type(cm.type) == 'number',
           'cm.type must be string or number')
    assert.is_string(cm.data)
    assert.equal(cm.data:byte(1), 16)
    assert.equal(cm.data:sub(2), string.rep('\0', #cm.data - 1))

    client:close()
    server:close()
end

if OS == 'Linux' then
    function testcase.sendmsg_cmsg_ip_ttl_udp()
        -- Receive a per-message TTL distinct from the socket default.
        local server = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'dgram',
            protocol = 'udp',
        }))
        local previous, opt_err = server:ip_recvttl(true)
        assert.is_boolean(previous)
        assert.is_nil(opt_err)
        local enabled
        enabled, opt_err = server:ip_recvttl()
        assert.is_true(enabled)
        assert.is_nil(opt_err)
        local sai = assert(server:getsockname())
        local client = assert(socket.new_inet({
            socktype = 'dgram',
            protocol = 'udp',
        }))

        local ttl_bytes = string.char(37, 0, 0, 0)
        assert.equal(client:sendmsg('b', sai), 1)
        assert(server:recvable(1))
        local baseline = assert(server:recvmsg(1, 128))
        assert.equal(baseline.data, 'b')
        assert.not_equal(baseline.cmsgs[1].data:byte(1), 37)
        local len, err, again = client:sendmsg('p', sai, {
            {
                level = 'ip',
                type = 'ttl',
                data = ttl_bytes,
            },
        })
        assert.equal(len, 1)
        assert.is_nil(err)
        assert.is_false(again)

        assert(server:recvable(1))
        local msg = assert(server:recvmsg(1, 128))
        assert.equal(msg.data, 'p')
        assert(msg.cmsgs and #msg.cmsgs > 0,
               'received TTL cmsg should be present')
        local cm = msg.cmsgs[1]
        assert.equal(cm.level, 'ip')
        assert.equal(cm.type, 'ttl')
        assert.is_string(cm.data)
        assert.equal(cm.data:byte(1), 37)
        assert.equal(cm.data:sub(2), string.rep('\0', #cm.data - 1))

        client:close()
        server:close()
    end
end

function testcase.sendmsg_cmsg_ipv6_hoplimit_udp()
    -- Receive a per-message IPv6 hoplimit distinct from the socket default.
    local server = assert(socket.bind_inet('::1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local previous, opt_err = server:ipv6_recvhoplimit(true)
    assert.is_boolean(previous)
    assert.is_nil(opt_err)
    local enabled
    enabled, opt_err = server:ipv6_recvhoplimit()
    assert.is_true(enabled)
    assert.is_nil(opt_err)
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    local hop_bytes = string.char(37, 0, 0, 0)
    assert.equal(client:sendmsg('b', sai), 1)
    assert(server:recvable(1))
    local baseline = assert(server:recvmsg(1, 128))
    assert.equal(baseline.data, 'b')
    assert.not_equal(baseline.cmsgs[1].data, hop_bytes)
    local len, err, again = client:sendmsg('h', sai, {
        {
            level = 'ipv6',
            type = 'hoplimit',
            data = hop_bytes,
        },
    })
    assert.equal(len, 1)
    assert.is_nil(err)
    assert.is_false(again)

    assert(server:recvable(1))
    local msg = assert(server:recvmsg(1, 128))
    assert.equal(msg.data, 'h')
    assert.equal(#msg.cmsgs, 1)
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'ipv6')
    assert.equal(cm.type, 'hoplimit')
    assert.equal(cm.data, hop_bytes)

    client:close()
    server:close()
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
            if type(cm.data) == 'number' then
                fds[#fds + 1] = cm.data
            else
                assert.is_table(cm.data)
                for _, fd in ipairs(cm.data) do
                    fds[#fds + 1] = fd
                end
            end
        end
        assert.equal(#fds, 2)
        for i, expected in ipairs({
            'first entry',
            'second entry',
        }) do
            assert.is_int(fds[i])
            local received = assert(fopen(fds[i], 'r'))
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
