local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local socket = require('net.socket')

local uname = assert(io.popen('uname -s'))
local OS = assert(uname:read('*l'))
assert(uname:close())

function testcase.new_inet_opts_all()
    -- Apply the stream-level options that are writable across supported
    -- kernels.  SO_SNDLOWAT is intentionally exercised by the failure-path
    -- tests because Linux exposes it but rejects attempts to change it.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
        debug = false,
        dontroute = false,
        keepalive = true,
        oobinline = true,
        reuseaddr = true,
        reuseport = true,
        timestamp = false,
        tcpcork = false,
        tcpnodelay = true,
        linger = 5,
        rcvbuf = 4096,
        rcvlowat = 1,
        sndbuf = 4096,
        tcpkeepalive = 60,
        tcpkeepcnt = 3,
        tcpkeepintvl = 30,
        rcvtimeo = 0.5,
        sndtimeo = 0.5,
    }))
    assert.is_false(s:debug())
    assert.is_false(s:dontroute())
    assert.is_true(s:keepalive())
    assert.is_true(s:oobinline())
    assert.is_true(s:reuseaddr())
    assert.is_true(s:reuseport())
    assert.is_false(s:timestamp())
    assert.is_false(s:tcpcork())
    assert.is_true(s:tcpnodelay())
    assert.equal(s:linger(), 5)
    assert.equal(s:rcvlowat(), 1)
    assert.equal(s:tcpkeepalive(), 60)
    assert.equal(s:tcpkeepcnt(), 3)
    assert.equal(s:tcpkeepintvl(), 30)
    assert.equal(s:rcvtimeo(), 0.5)
    assert.equal(s:sndtimeo(), 0.5)

    -- Compare normalized buffer sizes with the direct setter path instead
    -- of assuming the kernel returns the requested byte count unchanged.
    local reference = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(reference:rcvbuf(4096))
    assert(reference:sndbuf(4096))
    assert.equal(s:rcvbuf(), assert(reference:rcvbuf()))
    assert.equal(s:sndbuf(), assert(reference:sndbuf()))
    reference:close()
    s:close()

    -- dgram + multicast opts on IPv4.  mcastif is covered separately because
    -- loopback interface names differ between BSD/macOS and Linux.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
        broadcast = true,
        mcastloop = true,
        mcastttl = 4,
    }))
    assert.is_true(d:broadcast())
    assert.is_true(d:mcastloop())
    assert.equal(d:mcastttl(), 4)
    d:close()

    -- These IPv6 multicast options do not require a bind or route.
    local d6 = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
        mcastloop = true,
        mcastttl = 4,
    }))
    assert.is_true(d6:mcastloop())
    assert.equal(d6:mcastttl(), 4)
    d6:close()
end

function testcase.new_inet_opts_type_errors()
    -- opts value-type mismatches drive the cfg_check_* type-check branches.
    local err = assert.throws(function()
        socket.new_inet({
            socktype = 'stream',
            reuseaddr = 'yes',
        })
    end)
    assert.match(err, 'opts.reuseaddr', false)

    err = assert.throws(function()
        socket.new_inet({
            socktype = 'dgram',
            broadcast = 1,
        })
    end)
    assert.match(err, 'broadcast', false)
    assert.match(err, 'boolean', false)

    err = assert.throws(function()
        socket.new_inet({
            socktype = 'stream',
            rcvbuf = 'not-a-number',
        })
    end)
    assert.match(err, 'rcvbuf', false)
    assert.match(err, 'integer', false)

    err = assert.throws(function()
        socket.new_inet({
            socktype = 'stream',
            sndtimeo = 'not-a-number',
        })
    end)
    assert.match(err, 'sndtimeo', false)
    assert.match(err, 'number', false)

    err = assert.throws(function()
        socket.new_inet({
            socktype = 'dgram',
            protocol = 'udp',
            mcastif = 42,
        })
    end)
    assert.match(err, 'mcastif', false)
    assert.match(err, 'string', false)
end

function testcase.new_inet_setsockopt_failures()
    local ss, serr
    -- TCP-only options on a dgram socket surface an error at
    -- sockopts_apply().
    for _, name in ipairs({
        'tcpcork',
        'tcpnodelay',
    }) do
        ss, serr = socket.new_inet({
            socktype = 'dgram',
            protocol = 'udp',
            [name] = true,
        })
        assert.is_nil(ss)
        assert(serr)
    end

    -- mcastif with an unknown but well-formed interface name fails
    -- inside sockopts_set_mcastif for both AF_INET (SIOCGIFADDR) and
    -- AF_INET6 (if_nametoindex); malformed names are covered by
    -- mcast_ifname_validation.
    ss, serr = socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
        mcastif = '__nosuchif__',
    })
    assert.is_nil(ss)
    assert(serr)

    ss, serr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
        mcastif = '__nosuchif__',
    })
    assert.is_nil(ss)
    assert(serr)
end

if OS == 'Linux' then
    function testcase.new_inet_normalizes_negative_sndbuf()
        -- Linux treats negative buffer sizes as unsigned and caps them.
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            sndbuf = -1,
        })
        assert(s)
        assert.is_nil(err)
        local value
        value, err = s:sndbuf()
        assert.greater(value, 0)
        assert.is_nil(err)
        local reference = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        assert(reference:sndbuf(-1))
        assert.equal(value, assert(reference:sndbuf()))
        reference:close()
        s:close()
    end

    function testcase.new_inet_normalizes_negative_rcvbuf()
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            rcvbuf = -999999,
        })
        assert(s)
        assert.is_nil(err)
        local value
        value, err = s:rcvbuf()
        assert.greater(value, 0)
        assert.is_nil(err)
        local reference = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        assert(reference:rcvbuf(-999999))
        assert.equal(value, assert(reference:rcvbuf()))
        reference:close()
        s:close()
    end

    function testcase.new_inet_rejects_negative_sndlowat()
        -- Linux rejects SO_SNDLOWAT setters regardless of the value.
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            sndlowat = -1,
        })
        assert.is_nil(s)
        assert(error_is(err, errno.ENOPROTOOPT))
    end

    function testcase.new_inet_normalizes_negative_rcvlowat()
        -- Fix the receive buffer so TCP's low-water cap is half its size.
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            rcvbuf = 4096,
            rcvlowat = -1,
        })
        assert(s)
        assert.is_nil(err)
        local bufsize
        bufsize, err = s:rcvbuf()
        assert.greater(bufsize, 0)
        assert.is_nil(err)
        local value
        value, err = s:rcvlowat()
        assert.equal(value, bufsize / 2)
        assert.is_nil(err)
        s:close()
    end
elseif OS == 'Darwin' then
    function testcase.new_inet_rejects_negative_sndbuf()
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            sndbuf = -1,
        })
        assert.is_nil(s)
        assert(error_is(err, errno.EINVAL))
    end

    function testcase.new_inet_rejects_negative_rcvbuf()
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            rcvbuf = -999999,
        })
        assert.is_nil(s)
        assert(error_is(err, errno.EINVAL))
    end

    function testcase.new_inet_rejects_negative_sndlowat()
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            sndlowat = -1,
        })
        assert.is_nil(s)
        assert(error_is(err, errno.EINVAL))
    end

    function testcase.new_inet_rejects_negative_rcvlowat()
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            rcvlowat = -1,
        })
        assert.is_nil(s)
        assert(error_is(err, errno.EINVAL))
    end
end

if OS == 'Linux' or OS == 'Darwin' then
    function testcase.new_inet_rejects_negative_tcpkeepalive()
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            tcpkeepalive = -1,
        })
        assert.is_nil(s)
        assert(error_is(err, errno.EINVAL))
    end

    function testcase.new_inet_rejects_negative_tcpkeepcnt()
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            tcpkeepcnt = -1,
        })
        assert.is_nil(s)
        assert(error_is(err, errno.EINVAL))
    end

    function testcase.new_inet_rejects_negative_tcpkeepintvl()
        local s, err = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            tcpkeepintvl = -1,
        })
        assert.is_nil(s)
        assert(error_is(err, errno.EINVAL))
    end
else
    print('SKIP negative constructor option tests (unverified OS: ' .. OS .. ')')
end
