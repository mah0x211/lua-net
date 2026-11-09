local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local inet = require('net.dgram.inet')
local socket = require('net.socket')

local SOCKETS = {}

local function new_socket()
    local sock = assert(inet.new())
    SOCKETS[#SOCKETS + 1] = sock
    return sock
end

function testcase.after_each()
    for i = #SOCKETS, 1, -1 do
        SOCKETS[i]:close()
        SOCKETS[i] = nil
    end
end

function testcase.timeouts_preserve_exact_lua_values()
    local sock = new_socket()
    for _, name in ipairs({ 'rcvtimeo', 'sndtimeo' }) do
        assert.equal(sock[name](sock), 0)
        local sec = 0.123456789
        local old, err = sock[name](sock, sec)
        assert.equal(old, 0)
        assert.is_nil(err)
        assert.equal(sock[name](sock), sec)
        assert.equal(sock[name](sock, 0), sec)
        assert.equal(sock[name](sock), 0)
    end
end

function testcase.timeouts_accept_large_finite_lua_values()
    local sock = new_socket()
    for _, name in ipairs({ 'rcvtimeo', 'sndtimeo' }) do
        local old, err = sock[name](sock, 1e300)
        assert.equal(old, 0)
        assert.is_nil(err)
        assert.equal(sock[name](sock), 1e300)
    end
end

function testcase.timeouts_are_independent_per_socket_and_direction()
    local first, second = new_socket(), new_socket()
    assert.equal(first:rcvtimeo(1.25), 0)
    assert.equal(first:sndtimeo(2.5), 0)
    assert.equal(second:rcvtimeo(3.75), 0)
    assert.equal(first:rcvtimeo(), 1.25)
    assert.equal(first:sndtimeo(), 2.5)
    assert.equal(second:rcvtimeo(), 3.75)
    assert.equal(second:sndtimeo(), 0)
end

function testcase.invalid_timeout_does_not_change_stored_value()
    local sock = new_socket()
    for _, name in ipairs({ 'rcvtimeo', 'sndtimeo' }) do
        assert.equal(sock[name](sock, 0.5), 0)
        for _, bad in ipairs({ '1', false, {}, math.huge, -math.huge, 0 / 0 }) do
            assert.match(assert.throws(function()
                sock[name](sock, bad)
            end), 'sec must be finite-number', true)
            assert.equal(sock[name](sock), 0.5)
        end
        local value, err = sock[name](sock, -1)
        assert.is_nil(value)
        assert.equal(err.type, errno.EINVAL)
        assert.equal(sock[name](sock), 0.5)
    end
end

function testcase.wrap_starts_with_unset_lua_timeouts()
    local raw = assert(socket.new_inet({ socktype = 'dgram', protocol = 'udp' }))
    local fd = assert(raw:unwrap())
    local wrapped, err = inet.wrap(fd)
    if not wrapped then
        socket.close(fd)
    end
    assert(wrapped, err)
    SOCKETS[#SOCKETS + 1] = wrapped
    assert.equal(wrapped:rcvtimeo(), 0)
    assert.equal(wrapped:sndtimeo(), 0)
    assert.equal(wrapped:get_rcvtimeo(), 330)
    assert.equal(wrapped:get_sndtimeo(), 960)
end

function testcase.timeout_values_remain_available_after_close()
    local sock = new_socket()
    assert.equal(sock:rcvtimeo(1.25), 0)
    assert.equal(sock:sndtimeo(2.5), 0)
    assert(sock:close())
    assert.equal(sock:rcvtimeo(), 1.25)
    assert.equal(sock:sndtimeo(), 2.5)
    assert.equal(sock:rcvtimeo(0), 1.25)
    assert.equal(sock:sndtimeo(0), 2.5)
end
