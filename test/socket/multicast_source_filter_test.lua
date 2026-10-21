local testcase = require('testcase')
local assert = require('assert')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')
local errno = require('errno')

local loopback_ifname = require('test.socket_helpers').loopback_ifname

function testcase.mcastblocksrc_wrong_family()
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
    local ok, err = d4:mcastblocksrc(grp6, src4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    ok, err = d4:mcastblocksrc(grp4, src6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d4:close()

    -- IPv6 socket + IPv4 grp / src
    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastblocksrc(grp4, src6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    ok, err = d6:mcastblocksrc(grp6, src4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d6:close()
end

function testcase.mcastblocksrc_invalid_ifname()
    -- An unknown interface fails before the source-filter setsockopt.
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
    local ok, err = d:mcastblocksrc(grp, src, '__nosuchif__')
    assert.is_false(ok)
    assert.equal(err.op, 'ioctl')
    d:close()

    local d6 = assert(socket.new_inet6({
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
    ok, err = d6:mcastblocksrc(grp6, src6, '__nosuchif__')
    assert.is_false(ok)
    assert.equal(err.op, 'if_nametoindex')
    d6:close()
end

function testcase.mcastblocksrc_on_stream_socket()
    -- mcastblocksrc() on a SOCK_STREAM socket surfaces ESOCKTNOSUPPORT.
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
    local ok, err = s:mcastblocksrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.ESOCKTNOSUPPORT)
    s:close()
end

function testcase.mcastblocksrc_on_af_unix()
    -- mcastblocksrc() on an AF_UNIX dgram socket surfaces EAFNOSUPPORT.
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
    local ok, err = unix:mcastblocksrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    unix:close()
end

function testcase.mcastblocksrc_on_closed_socket()
    -- mcastblocksrc() on a closed AF_INET dgram socket surfaces EBADF.
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
    local ok, err = d:mcastblocksrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.EBADF)
end

function testcase.mcastunblocksrc_v4()
    -- Block/unblock a source on an any-source multicast membership using
    -- IP_BLOCK_SOURCE / IP_UNBLOCK_SOURCE; verify both state transitions.
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
    -- IP_UNBLOCK_SOURCE requires an active block filter for the same
    -- (grp, src) on the same interface, so each form joins and blocks
    -- first; separate groups avoid the duplicate membership error on
    -- Linux
    local grp2 = assert(addrinfo.inet('239.0.0.2', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d:mcastjoin(grp)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastblocksrc(grp, src)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastblocksrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    ok, err = d:mcastunblocksrc(grp, src)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastunblocksrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')

    ok, err = d:mcastjoin(grp2, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastblocksrc(grp2, src, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastblocksrc(grp2, src, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    ok, err = d:mcastunblocksrc(grp2, src, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastunblocksrc(grp2, src, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    d:close()
end

function testcase.mcastunblocksrc_v6()
    -- mcastunblocksrc() on an IPv6 dgram socket maps to setsockopt
    -- MCAST_UNBLOCK_SOURCE.
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
    -- Unblocking requires a membership and an active block on the interface.
    local ok, err = d:mcastjoin(grp, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    ok, err = d:mcastblocksrc(grp, src, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    -- Blocking an already blocked source must fail.
    ok, err = d:mcastblocksrc(grp, src, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    ok, err = d:mcastunblocksrc(grp, src, lo)
    assert.is_true(ok)
    assert.is_nil(err)
    -- The block has already been removed.
    ok, err = d:mcastunblocksrc(grp, src, lo)
    assert.is_false(ok)
    assert.equal(err.op, 'setsockopt')
    d:close()
end

function testcase.mcastunblocksrc_wrong_family()
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
    local ok, err = d4:mcastunblocksrc(grp6, src4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    ok, err = d4:mcastunblocksrc(grp4, src6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d4:close()

    -- IPv6 socket + IPv4 grp / src
    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastunblocksrc(grp4, src6)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    ok, err = d6:mcastunblocksrc(grp6, src4)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    d6:close()
end

function testcase.mcastunblocksrc_invalid_ifname()
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
    local ok, err = d:mcastunblocksrc(grp, src, '__nosuchif__')
    assert.is_false(ok)
    assert.equal(err.op, 'ioctl')
    d:close()
end

function testcase.mcastunblocksrc_on_stream_socket()
    -- mcastunblocksrc() on a SOCK_STREAM socket surfaces ESOCKTNOSUPPORT.
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
    local ok, err = s:mcastunblocksrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.ESOCKTNOSUPPORT)
    s:close()
end

function testcase.mcastunblocksrc_on_af_unix()
    -- mcastunblocksrc() on an AF_UNIX dgram socket surfaces EAFNOSUPPORT.
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
    local ok, err = unix:mcastunblocksrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    unix:close()
end

function testcase.mcastunblocksrc_on_closed_socket()
    -- mcastunblocksrc() on a closed AF_INET dgram socket surfaces EBADF.
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
    local ok, err = d:mcastunblocksrc(grp, src)
    assert.is_false(ok)
    assert.equal(err.type, errno.EBADF)
end
