local testcase = require('testcase')
local assert = require('assert')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')
local errno = require('errno')

local loopback_ifname = require('test.socket_helpers').loopback_ifname

function testcase.mcastjoin_wrong_family()
    -- Passing an IPv6 group to an IPv4 socket (and vice versa) surfaces
    -- EAFNOSUPPORT from mcast4group_lua / mcast6group_lua.
    local d4 = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp4 = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp6 = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d4:mcastjoin(grp6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    -- the EAFNOSUPPORT must attribute to the invoked method; the context
    -- must not leak the internal C function name
    assert.match(err, 'mcastjoin', false)
    assert.not_match(err, '_lua', false)
    d4:close()

    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastjoin(grp4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    assert.match(err, 'mcastjoin', false)
    assert.not_match(err, '_lua', false)
    d6:close()
end

function testcase.mcastjoin_invalid_ifname()
    -- An unknown but well-formed interface name surfaces an error via
    -- SIOCGIFADDR (IPv4) or if_nametoindex (IPv6); malformed names are
    -- covered by mcast_ifname_validation.
    local d4 = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp4 = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d4:mcastjoin(grp4, '__nosuchif__')
    assert.is_false(ok)
    assert.equal(err.op, 'ioctl')
    d4:close()

    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp6 = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastjoin(grp6, '__nosuchif__')
    assert.is_false(ok)
    assert.equal(err.op, 'if_nametoindex')
    d6:close()
end

function testcase.mcastjoin_on_stream_socket()
    -- mcastjoin() on a SOCK_STREAM socket surfaces ESOCKTNOSUPPORT.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = s:mcastjoin(grp)
    assert.is_false(ok)
    assert.equal(err.type, errno.ESOCKTNOSUPPORT)
    s:close()
end

function testcase.mcastjoin_on_af_unix()
    -- mcastjoin() on an AF_UNIX dgram socket surfaces EAFNOSUPPORT.
    local unix = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = unix:mcastjoin(grp)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    unix:close()
end

function testcase.mcastjoin_on_closed_socket()
    -- mcastjoin() on a closed AF_INET dgram socket surfaces EBADF via
    -- setsockopt.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert(d:close())
    local ok, err = d:mcastjoin(grp)
    assert.is_false(ok)
    assert.equal(err.type, errno.EBADF)
end

function testcase.mcastleave_v4()
    -- Complete each join/leave cycle before using the other interface form:
    -- the default interface may itself be loopback. A second leave must fail.
    local lo = assert(loopback_ifname())
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d:mcastjoin(grp)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastleave(grp)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastleave(grp)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')

    ok, err = d:mcastjoin(grp, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastleave(grp, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastleave(grp, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    d:close()
end

function testcase.mcastleave_v6()
    -- mcastleave() on an IPv6 dgram socket maps to IPV6_LEAVE_GROUP.
    -- The kernel resolves the plain form to the default multicast
    -- interface, which may differ from the interface the group was
    -- joined on, so leave the loopback membership with the explicit
    -- interface name only.
    local lo = assert(loopback_ifname())
    local d = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d:mcastjoin(grp, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastleave(grp, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastleave(grp, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    d:close()
end

function testcase.mcastleave_wrong_family()
    -- Passing an IPv6 group to an IPv4 socket (and vice versa) surfaces
    -- EAFNOSUPPORT from mcast4group_lua / mcast6group_lua.
    local d4 = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp4 = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp6 = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d4:mcastleave(grp6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d4:close()

    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastleave(grp4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d6:close()
end

function testcase.mcastleave_invalid_ifname()
    -- An unknown but well-formed interface name surfaces an error via
    -- SIOCGIFADDR (IPv4) or if_nametoindex (IPv6); malformed names are
    -- covered by mcast_ifname_validation.
    local d4 = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp4 = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d4:mcastleave(grp4, '__nosuchif__')
    assert.is_false(ok)
    assert.equal(err.op, 'ioctl')
    d4:close()

    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp6 = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastleave(grp6, '__nosuchif__')
    assert.is_false(ok)
    assert.equal(err.op, 'if_nametoindex')
    d6:close()
end

function testcase.mcastleave_on_stream_socket()
    -- mcastleave() on a SOCK_STREAM socket surfaces ESOCKTNOSUPPORT.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = s:mcastleave(grp)
    assert.is_false(ok)
    assert.equal(err.type, errno.ESOCKTNOSUPPORT)
    s:close()
end

function testcase.mcastleave_on_af_unix()
    -- mcastleave() on an AF_UNIX dgram socket surfaces EAFNOSUPPORT.
    local unix = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = unix:mcastleave(grp)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    unix:close()
end

function testcase.mcastleave_on_closed_socket()
    -- mcastleave() on a closed AF_INET dgram socket surfaces EBADF via
    -- setsockopt.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert(d:close())
    local ok, err = d:mcastleave(grp)
    assert.is_false(ok)
    assert.equal(err.type, errno.EBADF)
end
