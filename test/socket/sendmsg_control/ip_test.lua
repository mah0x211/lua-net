local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')

local uname = assert(io.popen('uname -s'))
local OS = assert(uname:read('*l'))
assert(uname:close())

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
