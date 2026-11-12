local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')

local SOCK
local TTLS = {0, 1, 4, 127, 128, 254, 255}
local INVALID_TTLS = {-2147483648, -2, 256, 257, 511, 2147483647}

function testcase.after_each()
    if SOCK then
        SOCK:close()
        SOCK = nil
    end
end

function testcase.ipv4_constructor_preserves_multicast_values()
    for _, ttl in ipairs(TTLS) do
        for _, loop in ipairs({false, true}) do
            SOCK = assert(socket.new_inet({
                socktype = 'dgram',
                protocol = 'udp',
                mcastttl = ttl,
                mcastloop = loop,
            }))
            assert.equal(SOCK:mcastttl(), ttl)
            assert.equal(SOCK:mcastloop(), loop)
            assert(SOCK:close())
            SOCK = nil
        end
    end
end

function testcase.ipv4_setter_preserves_multicast_values()
    SOCK = assert(socket.new_inet({socktype = 'dgram', protocol = 'udp'}))
    local previous = assert(SOCK:mcastttl())
    for _, ttl in ipairs(TTLS) do
        local old, err = SOCK:mcastttl(ttl)
        assert.is_nil(err)
        assert.equal(old, previous)
        assert.equal(SOCK:mcastttl(), ttl)
        previous = ttl
    end
    previous = SOCK:mcastloop()
    for _, loop in ipairs({false, true, false, true}) do
        local old, err = SOCK:mcastloop(loop)
        assert.is_nil(err)
        assert.equal(old, previous)
        assert.equal(SOCK:mcastloop(), loop)
        previous = loop
    end
end

function testcase.ipv4_constructor_rejects_out_of_range_ttl()
    for _, ttl in ipairs(INVALID_TTLS) do
        local err
        SOCK, err = socket.new_inet({
            socktype = 'dgram',
            protocol = 'udp',
            mcastttl = ttl,
        })
        assert.is_nil(SOCK)
        assert.equal(err.type, errno.EINVAL)
    end
end

function testcase.ipv4_setter_rejects_out_of_range_ttl_without_changes()
    SOCK = assert(socket.new_inet({socktype = 'dgram', protocol = 'udp'}))
    local _, err = SOCK:mcastttl(200)
    assert.is_nil(err)
    for _, ttl in ipairs(INVALID_TTLS) do
        local old
        old, err = SOCK:mcastttl(ttl)
        assert.is_nil(old)
        assert.equal(err.type, errno.EINVAL)
        assert.equal(SOCK:mcastttl(), 200)
    end
end
