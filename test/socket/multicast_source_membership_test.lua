local testcase = require('testcase')
local assert = require('assert')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')
local errno = require('errno')

local loopback_ifname = require('test.socket_helpers').loopback_ifname

function testcase.mcastjoinsrc_wrong_family()
    -- Either grp or src with a family that does not match the socket
    -- surfaces EAFNOSUPPORT from mcast4srcgroup_lua / mcastsrcgroup_lua.
    local d4 = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp4 = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src4 = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp6 = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src6 = assert(addrinfo.inet6('::1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    -- IPv4 socket + IPv6 grp / src
    local ok, err = d4:mcastjoinsrc(grp6, src4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    ok, err = d4:mcastjoinsrc(grp4, src6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d4:close()

    -- IPv6 socket + IPv4 grp / src
    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastjoinsrc(grp4, src6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    ok, err = d6:mcastjoinsrc(grp6, src4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d6:close()
end

function testcase.mcastjoinsrc_invalid_ifname()
    -- An unknown interface name surfaces an error via SIOCGIFADDR (IPv4).
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d:mcastjoinsrc(grp, src, '__nosuchif__')
    assert.is_false(ok)
    assert.equal(err.op, 'ioctl')
    d:close()
end

function testcase.mcastjoinsrc_on_stream_socket()
    -- mcastjoinsrc() on a SOCK_STREAM socket surfaces ESOCKTNOSUPPORT.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = s:mcastjoinsrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.ESOCKTNOSUPPORT)
    s:close()
end

function testcase.mcastjoinsrc_on_af_unix()
    -- mcastjoinsrc() on an AF_UNIX dgram socket surfaces EAFNOSUPPORT.
    local unix = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = unix:mcastjoinsrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    unix:close()
end

function testcase.mcastjoinsrc_on_closed_socket()
    -- mcastjoinsrc() on a closed AF_INET dgram socket surfaces EBADF.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert(d:close())
    local ok, err = d:mcastjoinsrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.EBADF)
end

function testcase.mcastleavesrc_v4()
    -- Complete each source membership cycle before testing the other
    -- interface form; the default interface may itself be loopback.
    local lo = assert(loopback_ifname())
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d:mcastjoinsrc(grp, src)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastjoinsrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    ok, err = d:mcastleavesrc(grp, src)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastleavesrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')

    ok, err = d:mcastjoinsrc(grp, src, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastjoinsrc(grp, src, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    ok, err = d:mcastleavesrc(grp, src, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastleavesrc(grp, src, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    d:close()
end

function testcase.mcastleavesrc_v6()
    -- mcastleavesrc() on an IPv6 dgram socket maps to setsockopt
    -- MCAST_LEAVE_SOURCE_GROUP.
    local lo = assert(loopback_ifname())
    local d = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet6('::1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    -- Leaving a source requires a source membership on the same interface.
    local ok, err = d:mcastjoinsrc(grp, src, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    -- A duplicate source membership on the same interface must fail.
    ok, err = d:mcastjoinsrc(grp, src, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    ok, err = d:mcastleavesrc(grp, src, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    -- The source membership has already been removed.
    ok, err = d:mcastleavesrc(grp, src, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    d:close()
end

function testcase.mcastleavesrc_wrong_family()
    -- Either grp or src with a family that does not match the socket
    -- surfaces EAFNOSUPPORT from mcast4srcgroup_lua / mcastsrcgroup_lua.
    local d4 = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp4 = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src4 = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp6 = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src6 = assert(addrinfo.inet6('::1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    -- IPv4 socket + IPv6 grp / src
    local ok, err = d4:mcastleavesrc(grp6, src4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    ok, err = d4:mcastleavesrc(grp4, src6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d4:close()

    -- IPv6 socket + IPv4 grp / src
    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastleavesrc(grp4, src6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    ok, err = d6:mcastleavesrc(grp6, src4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d6:close()
end

function testcase.mcastleavesrc_invalid_ifname()
    -- An unknown interface name surfaces an error via SIOCGIFADDR (IPv4).
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d:mcastleavesrc(grp, src, '__nosuchif__')
    assert.is_false(ok)
    assert.equal(err.op, 'ioctl')
    d:close()
end

function testcase.mcastleavesrc_on_stream_socket()
    -- mcastleavesrc() on a SOCK_STREAM socket surfaces ESOCKTNOSUPPORT.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = s:mcastleavesrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.ESOCKTNOSUPPORT)
    s:close()
end

function testcase.mcastleavesrc_on_af_unix()
    -- mcastleavesrc() on an AF_UNIX dgram socket surfaces EAFNOSUPPORT.
    local unix = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = unix:mcastleavesrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    unix:close()
end

function testcase.mcastleavesrc_on_closed_socket()
    -- mcastleavesrc() on a closed AF_INET dgram socket surfaces EBADF.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert(d:close())
    local ok, err = d:mcastleavesrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.EBADF)
end
