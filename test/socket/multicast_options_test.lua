local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')

local loopback_ifname = require('test.socket_helpers').loopback_ifname

function testcase.new_inet_rejects_invalid_mcastif_with_mcastttl()
    local s, err = socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
        mcastttl = 4,
        mcastif = '__nosuchif__',
    })
    assert.is_nil(s)
    assert(err)
end

function testcase.new_inet6_rejects_invalid_mcastif_with_mcastttl()
    local s, err = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
        mcastttl = 4,
        mcastif = '__nosuchif__',
    })
    assert.is_nil(s)
    assert(err)
end

function testcase.mcastloop_v4()
    -- mcastloop() getter/setter on an IPv4 dgram socket.  The setter
    -- toggles IP_MULTICAST_LOOP via setsockopt.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local before, err = d:mcastloop()
    assert.is_boolean(before)
    assert.is_nil(err)
    local prev
    prev, err = d:mcastloop(false)
    assert.equal(prev, before)
    assert.is_nil(err)
    local value
    value, err = d:mcastloop()
    assert.is_false(value)
    assert.is_nil(err)
    prev, err = d:mcastloop(true)
    assert.is_false(prev)
    assert.is_nil(err)
    value, err = d:mcastloop()
    assert.is_true(value)
    assert.is_nil(err)
    d:close()
end

function testcase.mcastloop_v6()
    -- mcastloop() getter/setter on an IPv6 dgram socket.  The setter
    -- toggles IPV6_MULTICAST_LOOP via setsockopt.
    local d = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local before, err = d:mcastloop()
    assert.is_boolean(before)
    assert.is_nil(err)
    local prev
    prev, err = d:mcastloop(false)
    assert.equal(prev, before)
    assert.is_nil(err)
    local value
    value, err = d:mcastloop()
    assert.is_false(value)
    assert.is_nil(err)
    prev, err = d:mcastloop(true)
    assert.is_false(prev)
    assert.is_nil(err)
    value, err = d:mcastloop()
    assert.is_true(value)
    assert.is_nil(err)
    d:close()
end

function testcase.mcastloop_on_stream_socket()
    -- mcastloop() on a SOCK_STREAM socket takes the ESOCKTNOSUPPORT error
    -- branch because multicast options are only meaningful for datagram
    -- (or raw) sockets.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:mcastloop()
    assert.is_nil(rv)
    assert.equal(err.type, errno.ESOCKTNOSUPPORT)
    -- the error context must be the invoked method name, without the
    -- internal C function suffix
    assert.match(err, 'mcastloop', false)
    assert.not_match(err, '_lua', false)
    s:close()
end

function testcase.mcastloop_on_af_unix()
    -- mcastloop() on an AF_UNIX dgram socket takes the EAFNOSUPPORT error
    -- branch: SOCK_DGRAM passes the outer switch but the inner family
    -- dispatch has no AF_UNIX handler.
    local unix = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local rv, err = unix:mcastloop()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    unix:close()
end

function testcase.mcastloop_on_closed_socket()
    -- mcastloop() on a closed AF_INET dgram socket surfaces EBADF via
    -- getsockopt.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert(d:close())
    local rv, err = d:mcastloop()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.mcastttl_v4()
    -- mcastttl() getter/setter on an IPv4 dgram socket.  The setter
    -- writes IP_MULTICAST_TTL via setsockopt.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local before, err = d:mcastttl()
    assert.is_number(before)
    assert.is_nil(err)
    local prev
    prev, err = d:mcastttl(4)
    assert.equal(prev, before)
    assert.is_nil(err)
    local value
    value, err = d:mcastttl()
    assert.equal(value, 4)
    assert.is_nil(err)
    d:close()
end

function testcase.mcastttl_v6()
    -- mcastttl() on an IPv6 dgram socket writes IPV6_MULTICAST_HOPS.
    local d = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local before, err = d:mcastttl()
    assert.is_number(before)
    assert.is_nil(err)
    local prev
    prev, err = d:mcastttl(4)
    assert.equal(prev, before)
    assert.is_nil(err)
    local value
    value, err = d:mcastttl()
    assert.equal(value, 4)
    assert.is_nil(err)
    d:close()
end

function testcase.mcastttl_on_stream_socket()
    -- mcastttl() on a SOCK_STREAM socket takes the ESOCKTNOSUPPORT branch.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:mcastttl()
    assert.is_nil(rv)
    assert.equal(err.type, errno.ESOCKTNOSUPPORT)
    s:close()
end

function testcase.mcastttl_on_af_unix()
    -- mcastttl() on an AF_UNIX dgram socket takes the EAFNOSUPPORT branch.
    local unix = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local rv, err = unix:mcastttl()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    unix:close()
end

function testcase.mcastttl_on_closed_socket()
    -- mcastttl() on a closed AF_INET dgram socket surfaces EBADF.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert(d:close())
    local rv, err = d:mcastttl()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.mcastif_v4()
    -- mcastif() getter/setter on an IPv4 dgram socket.  It maps to
    -- IP_MULTICAST_IF: the setter accepts an interface name (resolved
    -- via SIOCGIFADDR) or nil to restore default interface selection.
    local ifname = assert(loopback_ifname())
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local value, err = d:mcastif() -- no interface configured yet
    assert.is_nil(value)
    assert.is_nil(err)
    local prev
    prev, err = d:mcastif(ifname)
    assert.is_nil(prev)
    assert.is_nil(err)
    value, err = d:mcastif()
    assert.equal(value, ifname)
    assert.is_nil(err)
    prev, err = d:mcastif(nil) -- restore default interface selection
    assert.equal(prev, ifname)
    assert.is_nil(err)
    value, err = d:mcastif()
    assert.is_nil(value)
    assert.is_nil(err)
    d:close()
end

function testcase.mcastif_v6()
    -- mcastif() on an IPv6 dgram socket maps to IPV6_MULTICAST_IF: the
    -- setter accepts an interface name (resolved via if_nametoindex).
    -- macOS rejects interface index 0, so the nil setter is not exercised.
    local ifname = assert(loopback_ifname())
    local d = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local value, err = d:mcastif()
    assert.is_nil(value)
    assert.is_nil(err)
    local prev
    prev, err = d:mcastif(ifname)
    assert.is_nil(prev)
    assert.is_nil(err)
    value, err = d:mcastif()
    assert.equal(value, ifname)
    assert.is_nil(err)
    d:close()
end

function testcase.mcastif_invalid_ifname()
    -- An unknown but well-formed interface name surfaces an error via
    -- SIOCGIFADDR (IPv4) or if_nametoindex (IPv6); malformed names are
    -- covered by mcast_ifname_validation.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local rv, err = d:mcastif('__nosuchif__')
    assert.is_nil(rv)
    assert.equal(err.op, 'ioctl')
    d:close()

    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    rv, err = d6:mcastif('__nosuchif__')
    assert.is_nil(rv)
    assert.equal(err.op, 'if_nametoindex')
    d6:close()
end

function testcase.mcastif_on_stream_socket()
    -- mcastif() on a SOCK_STREAM socket takes the ESOCKTNOSUPPORT branch.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:mcastif('lo0')
    assert.is_nil(rv)
    assert.equal(err.type, errno.ESOCKTNOSUPPORT)
    s:close()
end

function testcase.mcastif_on_af_unix()
    -- mcastif() on an AF_UNIX dgram socket takes the EAFNOSUPPORT branch.
    local unix = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local rv, err = unix:mcastif()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EAFNOSUPPORT)
    unix:close()
end

function testcase.mcastif_on_closed_socket()
    -- Both getter and setter on a closed AF_INET dgram socket surface
    -- EBADF via getsockopt.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert(d:close())
    local rv, err = d:mcastif()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = d:mcastif('lo0')
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.mcast_ifname_validation()
    -- an interface name must be shorter than IFNAMSIZ (16 bytes) and must
    -- not contain an embedded NUL; both used to be silently truncated,
    -- and an embedded NUL redirected the operation to the prefix interface
    local lo = assert(loopback_ifname())
    local long = string.rep('a', 16)

    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))

    local rv, err = d:mcastif(long)
    assert.is_nil(rv)
    assert.not_nil(error_is(err, errno.EINVAL))
    rv, err = d:mcastif(lo .. '\0evil')
    assert.is_nil(rv)
    assert.not_nil(error_is(err, errno.EINVAL))

    local ok
    ok, err = d:mcastjoin(grp, long)
    assert.is_false(ok)
    assert.not_nil(error_is(err, errno.EINVAL))
    ok, err = d:mcastjoin(grp, lo .. '\0evil')
    assert.is_false(ok)
    assert.not_nil(error_is(err, errno.EINVAL))
    d:close()

    -- the same validation applies to the construction opts
    local s, serr = socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
        mcastif = long,
    })
    assert.is_nil(s)
    assert.not_nil(error_is(serr, errno.EINVAL))
    s, serr = socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
        mcastif = lo .. '\0evil',
    })
    assert.is_nil(s)
    assert.not_nil(error_is(serr, errno.EINVAL))

    -- AF_INET6 rejects malformed names before calling if_nametoindex.
    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    rv, err = d6:mcastif(long)
    assert.is_nil(rv)
    assert.not_nil(error_is(err, errno.EINVAL))
    local grp6 = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastjoin(grp6, lo .. '\0evil')
    assert.is_false(ok)
    assert.not_nil(error_is(err, errno.EINVAL))
    d6:close()
end
