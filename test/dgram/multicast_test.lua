local testcase = require('testcase')
local assert = require('assert')
local inet = require('net.dgram.inet')
local socket = require('net.socket')
local loopback_ifname = require('test.socket_helpers').loopback_ifname

local SOCK

function testcase.after_each()
    if SOCK then
        SOCK:close()
        SOCK = nil
    end
end

local function check_getter(raw)
    local fd = assert(raw:unwrap())
    local sock, err = inet.wrap(fd)
    if not sock then
        socket.close(fd)
    end
    SOCK = assert(sock, err)
    local ifname = assert(loopback_ifname())
    local _, set_err = SOCK:mcastif(ifname)
    assert.is_nil(set_err)
    local first, first_err = SOCK:mcastif()
    local second, second_err = SOCK:mcastif()
    assert.is_nil(first_err)
    assert.is_nil(second_err)
    assert.equal(first, ifname)
    assert.equal(second, ifname)
end

function testcase.mcastif_ipv4_getter_preserves_interface()
    check_getter(assert(socket.new_inet({socktype = 'dgram', protocol = 'udp'})))
end

function testcase.mcastif_ipv6_getter_preserves_interface()
    check_getter(assert(socket.new_inet6({socktype = 'dgram', protocol = 'udp'})))
end

function testcase.mcastif_explicit_nil_resets_interface()
    SOCK = assert(inet.new())
    local ifname = assert(loopback_ifname())
    local _, err = SOCK:mcastif(ifname)
    assert.is_nil(err)
    local previous, reset_err = SOCK:mcastif(nil)
    assert.equal(previous, ifname)
    assert.is_nil(reset_err)
    local current, get_err = SOCK:mcastif()
    assert.is_nil(current)
    assert.is_nil(get_err)
end
