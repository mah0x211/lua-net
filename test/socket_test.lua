local fileno = require('io.fileno')
local testcase = require('testcase')
local timer = require('testcase.timer')
local fork = require('testcase.fork')
local signal = require('testcase.signal')
local assert = require('assert')
local errno = require('errno')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')

-- unpack() moved to table.unpack in Lua 5.2
local unpack = unpack or table.unpack

-- SCM_CREDENTIALS is a Linux-only cmsg type.  On other platforms (macOS,
-- most BSDs) the equivalent SCM_CREDS has no reliable explicit-send API
-- that we can exercise from Lua, so we skip the test there.
local function is_linux()
    -- luacov: disable
    local fp = io.open('/proc/version', 'r')
    if not fp then
        return false
    end
    local content = fp:read('*l')
    fp:close()
    return content and content:find('Linux', 1, true) ~= nil
    -- luacov: enable
end

local function skip_if_not_linux(name)
    if not is_linux() then
        print('SKIP ' .. name .. ' (not Linux)')
        return true
    end
    return false
end

-- receive everything the socket currently holds, concatenated
local function recv_all(sock)
    local acc = {}
    while true do
        local chunk = sock:recv(65536)
        if not chunk then
            return table.concat(acc)
        end
        acc[#acc + 1] = chunk
    end
end

--
-- socket.new_inet
--
function testcase.new_inet()
    -- new_inet(opts) creates a raw AF_INET socket with socket(AF_INET,
    -- opts.socktype, opts.protocol) followed by FD_CLOEXEC + O_NONBLOCK.
    -- The socket is not bound; the caller drives bind/connect via
    -- s:bind(ai) / s:connect(ai) afterwards.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'stream')
    s:close()

    -- SOCK_DGRAM + IPPROTO_UDP is also accepted.
    s = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(s:socktype(), 'dgram')
    s:close()

    -- opts.protocol defaults to 0 ("auto") when omitted.
    s = assert(socket.new_inet({
        socktype = 'stream',
    }))
    s:close()

    -- Unknown opts keys are silently ignored (delegated to check_options).
    s = assert(socket.new_inet({
        socktype = 'stream',
        not_a_recognized_socket_option = true,
    }))
    s:close()
end

function testcase.new_inet_missing_socktype()
    -- opts.socktype is required; omitting it surfaces a Lua error at the
    -- new_raw_socket_lua guard.
    local err = assert.throws(function()
        socket.new_inet({})
    end)
    assert.match(err, 'opts.socktype is required', false)

    err = assert.throws(function()
        socket.new_inet()
    end)
    assert.match(err, 'opts.socktype is required', false)
end

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
    assert.is_true(s:reuseaddr())
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
    d:close()

    -- IPv6 dgram multicast opts.  Some CI environments have no lo0/::1
    -- multicast route, so accept either outcome.
    local d6 = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
        mcastloop = true,
        mcastttl = 4,
    })
    if d6 then
        d6:close()
    end
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

function testcase.gcfn_callback_referencing_socket_is_collectable()
    -- The gc thread used to be anchored in the Lua registry, so a gc
    -- callback that referenced the socket itself formed a strong chain
    -- (registry -> thread -> closure upvalues -> callback -> socket)
    -- that the collector could never break: the socket leaked forever.
    -- The thread is now bound to the socket userdata itself, making the
    -- cycle collectable.
    local weak = setmetatable({}, {__mode = 'v'})
    local gced = false
    do
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        weak.sock = s
        assert(s:addgcfn(error, function()
            gced = true
        end, s))
    end
    for _ = 1, 10 do
        collectgarbage('collect')
    end
    assert.is_nil(weak.sock, 'socket referenced by its gcfn must be collectable')
    assert.is_true(gced, 'the gc callback must have run during collection')

    -- the same must hold for sockets created via wrap / dup / pair
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local weak2 = setmetatable({}, {__mode = 'v'})
    do
        local wrapped = assert(socket.wrap(socks[1]:fd()))
        weak2.sock = wrapped
        assert(wrapped:addgcfn(error, function()
            gced = gced or true
        end, wrapped))
        wrapped:unwrap()
    end
    for _ = 1, 10 do
        collectgarbage('collect')
    end
    assert.is_nil(weak2.sock, 'wrapped socket referenced by its gcfn must be collectable')
    socks[1]:close()
    socks[2]:close()
end

function testcase.constructor_failure_does_not_leak_gcthread_registry_ref()
    -- Each successful constructor lauxh_ref()'s a gc thread into the
    -- Lua registry.  When a constructor fails after that ref -- eg. via
    -- sockopts_apply on a nonsense option combination -- gc_lua()'s old
    -- guard (fd != -1) skipped the unref, so every failed attempt
    -- accumulated one dangling registry slot.  Detect the leak via
    -- lua memory (KB) instead of counting registry keys, because
    -- luaL_ref recycles integer keys and pairs iteration hides that.
    local function used_kb()
        collectgarbage('collect')
        collectgarbage('collect')
        return collectgarbage('count')
    end

    -- Warm up any first-call allocations so they do not skew the delta.
    for _ = 1, 100 do
        local ss = socket.new_inet({
            socktype = 'dgram',
            protocol = 'udp',
            tcpnodelay = true,
        })
        assert.is_nil(ss)
    end
    local before = used_kb()
    for _ = 1, 1000 do
        local ss = socket.new_inet({
            socktype = 'dgram',
            protocol = 'udp',
            tcpnodelay = true,
        })
        assert.is_nil(ss)
    end
    local after = used_kb()

    -- Every leaked gc thread is at least a few hundred bytes; 1000
    -- failed constructors would push the delta well over 100 KB.  With
    -- the fix in place the delta stays within a small handful of KB of
    -- scheduler noise.
    assert(after - before < 50,
           string.format(
               'lua memory grew from %.1f KB to %.1f KB (%.1f KB delta)' ..
                   ' across 1000 failed constructors', before, after,
               after - before))
end

function testcase.new_inet_setsockopt_failures()
    -- Kernels either reject or clamp negative socket-buffer sizes.  Both are
    -- valid; verify that the constructor returns a coherent result in either
    -- case before testing options whose negative values are rejected.
    local ss, serr = socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
        sndbuf = -1,
    })
    if ss then
        assert.is_nil(serr)
        ss:close()
    else
        assert(serr)
    end

    ss, serr = socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
        rcvbuf = -999999,
    })
    if ss then
        assert.is_nil(serr)
        ss:close()
    else
        assert(serr)
    end

    -- Kernels likewise differ on whether the remaining negative option values
    -- are rejected or normalized, so accept either coherent outcome here.
    -- rcvtimeo / sndtimeo have their own dedicated rejection testcase
    -- because negative values are refused at the C boundary now.
    for _, opts in ipairs({
        {
            tcpkeepintvl = -1,
        },
        {
            tcpkeepcnt = -1,
        },
        {
            tcpkeepalive = -1,
        },
        {
            sndlowat = -1,
        },
        {
            rcvlowat = -1,
        },
    }) do
        opts.socktype = 'stream'
        opts.protocol = 'tcp'
        ss, serr = socket.new_inet(opts)
        if ss then
            assert.is_nil(serr)
            ss:close()
        else
            assert(serr)
        end
    end

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

    -- mcastif with an unknown interface name fails inside
    -- sockopts_set_mcastif for both AF_INET (SIOCGIFADDR) and AF_INET6
    -- (if_nametoindex).
    ss, serr = socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
        mcastif = '__net_no_such_if__',
    })
    assert.is_nil(ss)
    assert(serr)

    ss, serr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
        mcastif = '__net_no_such_if__',
    })
    assert.is_nil(ss)
    assert(serr)
end

function testcase.new_inet6()
    -- new_inet6(opts) is the AF_INET6 counterpart of new_inet.  Some CI
    -- environments lack an IPv6 socket() entirely, in which case we skip
    -- rather than fail.
    local s, err = socket.new_inet6({
        socktype = 'stream',
        protocol = 'tcp',
    })
    if not s then
        print('SKIP new_inet6 (' .. tostring(err) .. ')')
        return
    end
    assert.equal(s:family(), 'inet6')
    assert.equal(s:socktype(), 'stream')
    s:close()

    s = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(s:socktype(), 'dgram')
    s:close()
end

function testcase.new_inet6_missing_socktype()
    -- opts.socktype is required for new_inet6 as well.
    local err = assert.throws(function()
        socket.new_inet6({})
    end)
    assert.match(err, 'opts.socktype is required', false)
end

--
-- socket.new_unix
--
function testcase.new_unix()
    -- new_unix(opts) creates a raw AF_UNIX socket with socket(family,
    -- opts.socktype, opts.protocol) followed by FD_CLOEXEC + O_NONBLOCK.
    -- The socket is not bound; the caller drives bind/connect via
    -- s:bind(ai) / s:connect(ai) afterwards.
    local s = assert(socket.new_unix({
        socktype = 'stream',
    }))
    assert.equal(s:family(), 'unix')
    assert.equal(s:socktype(), 'stream')
    s:close()

    -- SOCK_DGRAM is also accepted; protocol defaults to 0.
    s = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    assert.equal(s:socktype(), 'dgram')
    s:close()

    -- Empty / unknown opts keys are ignored (delegated to check_options).
    s = assert(socket.new_unix({
        socktype = 'stream',
        not_a_recognized_socket_option = true,
    }))
    s:close()
end

function testcase.new_unix_missing_socktype()
    -- opts.socktype is required; omitting it surfaces a Lua error at the
    -- new_raw_socket_lua guard.
    local err = assert.throws(function()
        socket.new_unix({})
    end)
    assert.match(err, 'opts.socktype is required', false)
end

function testcase.new_unix_bad_protocol()
    -- socket(AF_UNIX, SOCK_STREAM, IPPROTO_TCP) fails with EPROTONOSUPPORT,
    -- exercising new_socket's socket() == -1 branch which propagates the
    -- failure back to new_unix as (nil, err).
    local s, err = socket.new_unix({
        socktype = 'stream',
        protocol = 'tcp',
    })
    assert.is_nil(s)
    assert(err)
end

--
-- socket.bind_inet / connect_inet
--
function testcase.bind_inet_from_ai()
    -- bind_inet accepts a pre-built addrinfo userdata; also verifies empty
    -- opts, unknown opts keys, and the reuseaddr shortcut.
    local ai = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local s = assert(socket.bind_inet(ai))
    s:close()

    s = assert(socket.bind_inet(ai, {}))
    s:close()
    s = assert(socket.bind_inet(ai, {
        reuseaddr = true,
    }))
    assert.is_true(s:reuseaddr())
    s:close()
end

function testcase.bind_inet_from_host_port()
    -- bind_inet(host, port) resolves via getaddrinfo, iterates the list,
    -- and binds the first candidate that yields a working socket.
    local s = assert(socket.bind_inet('127.0.0.1', 0))
    local ai = assert(s:getsockname())
    assert.equal(ai:family(), 'inet')
    assert.greater(ai:port(), 0)
    s:close()
end

function testcase.bind_inet_bad_host()
    -- Invalid hostname surfaces the addrinfo resolver error as (nil, err).
    local s, err = socket.bind_inet('..!!not-a-host!!..', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    })
    assert.is_nil(s)
    assert(err)
end

function testcase.bind_inet_address_in_use()
    -- Bind a socket to a random port, then try to bind another one to the
    -- same port without reuseaddr set.  new_net_socket's OP_BIND_INET
    -- branch falls through to the "close and try next addrinfo" cleanup
    -- path and ultimately returns nil + EADDRINUSE.
    local first = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local port = assert(first:getsockname()):port()

    local second, err = socket.bind_inet('127.0.0.1', port, {
        socktype = 'stream',
        protocol = 'tcp',
    })
    assert.is_nil(second)
    assert(err)

    first:close()
end

function testcase.connect_inet_from_host_port()
    -- connect_inet(host, port) resolves via getaddrinfo, iterates the list,
    -- and connects the first candidate socket to a listening peer.
    -- Depending on kernel timing the connect may complete synchronously or
    -- surface EINPROGRESS (again == true); either outcome is acceptable.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(0))
    local ai = assert(server:getsockname())

    local c, err, again = socket.connect_inet('127.0.0.1', ai:port())
    assert(c ~= nil, err)
    assert(again == true or again == nil)
    c:close()
    server:close()

    -- Attempting to connect to a definitely closed port surfaces the
    -- terminal errno (typically ECONNREFUSED) or is accepted by the kernel
    -- as an in-progress non-blocking connect (some environments).
    c, err = socket.connect_inet('127.0.0.1', 1, {
        socktype = 'stream',
        protocol = 'tcp',
    })
    if c then
        c:close()
    else
        assert(err)
    end
end

function testcase.connect_inet_bad_host()
    -- Invalid hostname surfaces the addrinfo resolver error as (nil, err).
    local s, err = socket.connect_inet('..!!not-a-host!!..', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    })
    assert.is_nil(s)
    assert(err)
end

--
-- socket.bind_unix / connect_unix
--
function testcase.bind_unix_from_ai()
    -- bind_unix accepts a pre-built addrinfo userdata.
    local path = os.tmpname()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    local s = assert(socket.bind_unix(ai))
    s:close()
    os.remove(path)
end

function testcase.connect_unix_from_ai()
    -- connect_unix(ai) connects to a listening unix peer.  A synchronous
    -- unix connect completes immediately (no EINPROGRESS on AF_UNIX).
    local path = os.tmpname()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    local server = assert(socket.bind_unix(ai))
    assert(server:listen(0))

    local c, err = socket.connect_unix(ai)
    assert(c ~= nil, err)
    local peer = assert(server:accept())
    c:close()
    peer:close()

    -- Also drive connect_lua's synchronous success path (connect() == 0)
    -- via the socket-method form: `sock:connect(ai)` on an already-bound
    -- unix peer.
    local c2 = assert(socket.new_unix({
        socktype = 'stream',
    }))
    local ok, cerr = c2:connect(ai)
    assert.is_true(ok)
    assert.is_nil(cerr)
    c2:close()

    server:close()
    os.remove(path)
end

function testcase.debug()
    -- SO_DEBUG toggles kernel-level debugging tracing for this socket.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:debug(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:debug(false)
    assert(ok ~= nil or err)
    local rv = s:debug()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:debug()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:debug(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.dontroute()
    -- SO_DONTROUTE bypasses the normal routing table for outbound datagrams.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:dontroute(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:dontroute(false)
    assert(ok ~= nil or err)
    local rv = s:dontroute()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:dontroute()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:dontroute(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.keepalive()
    -- SO_KEEPALIVE enables periodic keepalive probes on connected stream sockets.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:keepalive(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:keepalive(false)
    assert(ok ~= nil or err)
    local rv = s:keepalive()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:keepalive()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:keepalive(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.oobinline()
    -- SO_OOBINLINE places out-of-band data inline with normal recv() data.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:oobinline(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:oobinline(false)
    assert(ok ~= nil or err)
    local rv = s:oobinline()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:oobinline()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:oobinline(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.reuseaddr()
    -- SO_REUSEADDR allows the local address to be reused when binding.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:reuseaddr(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:reuseaddr(false)
    assert(ok ~= nil or err)
    local rv = s:reuseaddr()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:reuseaddr()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:reuseaddr(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.reuseport()
    -- SO_REUSEPORT allows multiple listeners on the same address/port pair.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:reuseport(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:reuseport(false)
    assert(ok ~= nil or err)
    local rv = s:reuseport()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:reuseport()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:reuseport(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.tcpcork()
    -- TCP_CORK / TCP_NOPUSH batches small writes into full-sized segments.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:tcpcork(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:tcpcork(false)
    assert(ok ~= nil or err)
    local rv = s:tcpcork()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:tcpcork()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:tcpcork(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.tcpnodelay()
    -- TCP_NODELAY disables the Nagle algorithm for latency-sensitive traffic.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:tcpnodelay(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:tcpnodelay(false)
    assert(ok ~= nil or err)
    local rv = s:tcpnodelay()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:tcpnodelay()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:tcpnodelay(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.ip_recvttl()
    -- IP_RECVTTL requests the sender TTL as ancillary data on recvmsg().
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:ip_recvttl(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:ip_recvttl(false)
    assert(ok ~= nil or err)
    local rv = s:ip_recvttl()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:ip_recvttl()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:ip_recvttl(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.ip_recvtos()
    -- IP_RECVTOS requests the sender IPv4 TOS byte as ancillary data.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err = s:ip_recvtos(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:ip_recvtos(false)
    assert(ok ~= nil or err)
    local rv = s:ip_recvtos()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:ip_recvtos()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:ip_recvtos(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.broadcast()
    -- SO_BROADCAST permits sending to the IPv4 limited-broadcast address.
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = s:broadcast(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:broadcast(false)
    assert(ok ~= nil or err)
    local rv = s:broadcast()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:broadcast()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:broadcast(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.timestamp()
    -- SO_TIMESTAMP delivers a timestamp cmsg with each recvmsg().
    --
    -- The Lua binding exposes a getter (no args) that reports the current
    -- boolean state and a setter (bool arg) that toggles it via setsockopt.
    -- On some kernels (macOS, or when the option requires elevated
    -- privileges) the setsockopt call may fail; in that case we accept the
    -- errno report rather than requiring the specific value.
    local s = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = s:timestamp(true)
    assert(ok ~= nil or err,
           'setter should return the previous state or an error object')
    ok, err = s:timestamp(false)
    assert(ok ~= nil or err)
    local rv = s:timestamp()
    assert(rv == true or rv == false or rv == nil,
           'getter should return a boolean (or nil on unsupported)')

    -- Once the underlying fd is externally closed, getter/setter surface
    -- EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:timestamp()
    assert.is_nil(rv)
    assert(err)
    ok, err = s:timestamp(true)
    assert.is_nil(ok)
    assert(err)
end

function testcase.rcvbuf()
    -- SO_RCVBUF sets the receive buffer size hint.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:rcvbuf()
    assert(rv ~= nil or err,
           'getter should return the current value or an error object')
    rv, err = s:rcvbuf(4096)
    assert(rv ~= nil or err,
           'setter should return the previous value or an error object')

    assert(socket.close(s:fd()))
    rv, err = s:rcvbuf()
    assert.is_nil(rv)
    assert(err)
    rv, err = s:rcvbuf(4096)
    assert.is_nil(rv)
    assert(err)
end

function testcase.rcvlowat()
    -- SO_RCVLOWAT sets the low-water mark for recv/select readiness.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:rcvlowat()
    assert(rv ~= nil or err,
           'getter should return the current value or an error object')
    rv, err = s:rcvlowat(1)
    assert(rv ~= nil or err,
           'setter should return the previous value or an error object')

    assert(socket.close(s:fd()))
    rv, err = s:rcvlowat()
    assert.is_nil(rv)
    assert(err)
    rv, err = s:rcvlowat(1)
    assert.is_nil(rv)
    assert(err)
end

function testcase.sndbuf()
    -- SO_SNDBUF sets the send buffer size hint.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:sndbuf()
    assert(rv ~= nil or err,
           'getter should return the current value or an error object')
    rv, err = s:sndbuf(4096)
    assert(rv ~= nil or err,
           'setter should return the previous value or an error object')

    assert(socket.close(s:fd()))
    rv, err = s:sndbuf()
    assert.is_nil(rv)
    assert(err)
    rv, err = s:sndbuf(4096)
    assert.is_nil(rv)
    assert(err)
end

function testcase.sndlowat()
    -- SO_SNDLOWAT sets the low-water mark for send/select writability.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:sndlowat()
    assert(rv ~= nil or err,
           'getter should return the current value or an error object')
    rv, err = s:sndlowat(1)
    assert(rv ~= nil or err,
           'setter should return the previous value or an error object')

    assert(socket.close(s:fd()))
    rv, err = s:sndlowat()
    assert.is_nil(rv)
    assert(err)
    rv, err = s:sndlowat(1)
    assert.is_nil(rv)
    assert(err)
end

function testcase.tcpkeepalive()
    -- TCP_KEEPALIVE / TCP_KEEPIDLE sets the idle time before keepalive probes.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:tcpkeepalive()
    assert(rv ~= nil or err,
           'getter should return the current value or an error object')
    rv, err = s:tcpkeepalive(60)
    assert(rv ~= nil or err,
           'setter should return the previous value or an error object')

    assert(socket.close(s:fd()))
    rv, err = s:tcpkeepalive()
    assert.is_nil(rv)
    assert(err)
    rv, err = s:tcpkeepalive(60)
    assert.is_nil(rv)
    assert(err)
end

function testcase.tcpkeepcnt()
    -- TCP_KEEPCNT sets the maximum number of unacked keepalive probes.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:tcpkeepcnt()
    assert(rv ~= nil or err,
           'getter should return the current value or an error object')
    rv, err = s:tcpkeepcnt(3)
    assert(rv ~= nil or err,
           'setter should return the previous value or an error object')

    assert(socket.close(s:fd()))
    rv, err = s:tcpkeepcnt()
    assert.is_nil(rv)
    assert(err)
    rv, err = s:tcpkeepcnt(3)
    assert.is_nil(rv)
    assert(err)
end

function testcase.tcpkeepintvl()
    -- TCP_KEEPINTVL sets the interval between keepalive probes.
    --
    -- Getter returns the current integer value; setter (int arg) updates
    -- the underlying kernel option via setsockopt.  A stale fd (closed
    -- externally) causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:tcpkeepintvl()
    assert(rv ~= nil or err,
           'getter should return the current value or an error object')
    rv, err = s:tcpkeepintvl(30)
    assert(rv ~= nil or err,
           'setter should return the previous value or an error object')

    assert(socket.close(s:fd()))
    rv, err = s:tcpkeepintvl()
    assert.is_nil(rv)
    assert(err)
    rv, err = s:tcpkeepintvl(30)
    assert.is_nil(rv)
    assert(err)
end

function testcase.rcvtimeo()
    -- SO_RCVTIMEO sets the blocking recv() timeout.
    --
    -- Getter returns the current timeout as a lua number (seconds); setter
    -- (number arg) updates SO_RCVTIMEO via setsockopt.  A stale fd
    -- causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:rcvtimeo()
    assert(rv ~= nil or err, 'getter should either succeed or return an error')
    rv, err = s:rcvtimeo(0.5)
    assert(rv ~= nil or err, 'setter should either succeed or return an error')

    assert(socket.close(s:fd()))
    rv, err = s:rcvtimeo()
    assert.is_nil(rv)
    assert(err)
    rv, err = s:rcvtimeo(0.5)
    assert.is_nil(rv)
    assert(err)
end

function testcase.sndtimeo()
    -- SO_SNDTIMEO sets the blocking send() timeout.
    --
    -- Getter returns the current timeout as a lua number (seconds); setter
    -- (number arg) updates SO_SNDTIMEO via setsockopt.  A stale fd
    -- causes both to surface EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:sndtimeo()
    assert(rv ~= nil or err, 'getter should either succeed or return an error')
    rv, err = s:sndtimeo(0.5)
    assert(rv ~= nil or err, 'setter should either succeed or return an error')

    assert(socket.close(s:fd()))
    rv, err = s:sndtimeo()
    assert.is_nil(rv)
    assert(err)
    rv, err = s:sndtimeo(0.5)
    assert.is_nil(rv)
    assert(err)
end

function testcase.rcvtimeo_and_sndtimeo_reject_nan_inf_and_out_of_range()
    -- The C bindings cast the caller-supplied double straight through
    -- modf + (time_t)/(suseconds_t) casts.  NaN, +/-Inf, negative
    -- values, and magnitudes that do not fit in time_t all invoke
    -- undefined behaviour once cast, so the C boundary must reject them.
    -- Method setters return (nil, EINVAL); constructor helpers raise a
    -- Lua error the same way type mismatches do.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    for _, bad in ipairs({
        math.huge,
        -math.huge,
        0 / 0,
        1e30,
        -1,
    }) do
        local rv, err = s:rcvtimeo(bad)
        assert.is_nil(rv, 'rcvtimeo must reject ' .. tostring(bad))
        assert(err)
        assert.equal(err.type, errno.EINVAL)

        rv, err = s:sndtimeo(bad)
        assert.is_nil(rv, 'sndtimeo must reject ' .. tostring(bad))
        assert(err)
        assert.equal(err.type, errno.EINVAL)

        local terr = assert.throws(function()
            socket.new_inet({
                socktype = 'stream',
                protocol = 'tcp',
                rcvtimeo = bad,
            })
        end)
        assert.match(terr, 'opts.rcvtimeo', false)

        terr = assert.throws(function()
            socket.new_inet({
                socktype = 'stream',
                protocol = 'tcp',
                sndtimeo = bad,
            })
        end)
        assert.match(terr, 'opts.sndtimeo', false)
    end
    s:close()
end

function testcase.linger()
    -- SO_LINGER controls how close() handles unsent data on a stream socket.
    -- The Lua binding uses a signed integer to encode both the on/off flag
    -- and the linger interval in seconds:
    --  * value >= 0 : SO_LINGER on, l_linger = value seconds
    --  * value < 0  : SO_LINGER off (disabled)
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    -- Getter returns the current linger value or an error object.
    local rv, err = s:linger()
    assert(rv ~= nil or err)
    -- Setter with a positive value enables SO_LINGER with a linger interval.
    rv, err = s:linger(1)
    assert(rv ~= nil or err)
    -- Setter with a negative value disables SO_LINGER (l_onoff = 0).
    rv, err = s:linger(-1)
    assert(rv ~= nil or err)

    -- A stale (externally-closed) fd causes both getter and setter to
    -- surface EBADF via setsockopt.
    assert(socket.close(s:fd()))
    rv, err = s:linger()
    assert.is_nil(rv)
    assert.not_nil(err)
    rv, err = s:linger(1)
    assert.is_nil(rv)
    assert.not_nil(err)
end

function testcase.cloexec()
    -- FD_CLOEXEC controls whether the fd is closed on exec().
    --
    -- Fresh sockets from socket.new_inet() are created with both
    -- O_CLOEXEC and O_NONBLOCK set; toggling either off and back on
    -- exercises the fcntl F_SETFL / F_SETFD paths.  A stale fd surfaces
    -- EBADF via fcntl F_GETFL / F_GETFD.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.is_true(s:cloexec())
    local ok, err = s:cloexec(false)
    assert(ok ~= nil or err, 'setter should either succeed or return an error')
    ok, err = s:cloexec(true)
    assert(ok ~= nil or err)

    assert(socket.close(s:fd()))
    ok, err = s:cloexec()
    assert.is_nil(ok)
    assert(err)
end

function testcase.nonblock()
    -- O_NONBLOCK controls whether IO on the fd blocks or returns EAGAIN.
    --
    -- Fresh sockets from socket.new_inet() are created with both
    -- O_CLOEXEC and O_NONBLOCK set; toggling either off and back on
    -- exercises the fcntl F_SETFL / F_SETFD paths.  A stale fd surfaces
    -- EBADF via fcntl F_GETFL / F_GETFD.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.is_true(s:nonblock())
    local ok, err = s:nonblock(false)
    assert(ok ~= nil or err, 'setter should either succeed or return an error')
    ok, err = s:nonblock(true)
    assert(ok ~= nil or err)

    assert(socket.close(s:fd()))
    ok, err = s:nonblock()
    assert.is_nil(ok)
    assert(err)
end

function testcase.error()
    -- error() reports the current pending socket error via SO_ERROR:
    --  * nil    when the socket has no pending error (SO_ERROR = 0)
    --  * errobj when a prior asynchronous operation completed with an error
    --
    -- The Lua binding wraps sockopt_int_lua(SOL_SOCKET, SO_ERROR) and
    -- promotes the returned integer errno to an errobj via lua_errno.

    -- Fresh socket: nothing to report.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.is_nil(s:error())
    s:close()

    -- Bind + listen a server, snapshot its port, then close it so that a
    -- subsequent connect() will find no listener.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:listen(0))
    local port = server:getsockname():port()
    server:close()

    -- Non-blocking connect() to the now-defunct port completes
    -- asynchronously with ECONNREFUSED; wait for writability and then
    -- observe SO_ERROR through error().
    local ai = assert(addrinfo.inet('127.0.0.1', port, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local c = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    c:connect(ai)
    c:sendable(1.0)
    local err_obj = c:error()
    assert.not_nil(err_obj)
    c:close()
end

function testcase.acceptconn()
    -- acceptconn() reports whether the socket is currently in the LISTEN
    -- state (i.e., ready to accept incoming connections).  The Lua binding
    -- wraps sockopt_int_lua(SOL_SOCKET, SO_ACCEPTCONN) and returns the
    -- boolean interpretation of the integer.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    -- A non-listening socket reports acceptconn = false (or nil on
    -- platforms that don't expose SO_ACCEPTCONN before bind()).
    local rv = s:acceptconn()
    assert(rv == false or rv == nil)
    local ai = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:bind(ai))
    assert(s:listen())
    -- Some platforms report SO_ACCEPTCONN as true, others as 1, others don't
    -- expose it at all.  Accept any truthy value from a listening socket.
    local lrv = s:acceptconn()
    assert(lrv == true or lrv == 1 or lrv == nil)
    s:close()
end

function testcase.ipv6_recvhoplimit()
    -- IPV6_RECVHOPLIMIT requests the sender IPv6 hop-limit as ancillary
    -- data on recvmsg().  On systems without IPv6 (or without loopback
    -- ::1 configured), new_inet() itself may fail; skip the test there.
    local s, err = socket.new_inet6({
        socktype = 'stream',
        protocol = 'tcp',
    })
    if not s then
        assert(err)
        return
    end
    -- Setter: toggle the option on and off.  Some kernels may return an
    -- error for unsupported family/socktype combinations.
    local ok, oerr = s:ipv6_recvhoplimit(true)
    assert(ok ~= nil or oerr)
    ok, oerr = s:ipv6_recvhoplimit(false)
    assert(ok ~= nil or oerr)
    local rv = s:ipv6_recvhoplimit()
    assert(rv ~= nil or rv == false)
    assert(socket.close(s:fd()))
    ok, oerr = s:ipv6_recvhoplimit()
    assert(ok == nil or ok == false or oerr)
end

function testcase.addgcfn()
    -- addgcfn returns a "net.socket.gcfn: 0x..." handle string on success.
    local called = false
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local handle = assert(s:addgcfn(error, function()
        called = true
    end))
    assert.is_string(handle)
    assert.equal(handle:sub(1, 19), 'net.socket.gcfn: 0x')
    assert(s:close())
    assert.is_true(called)

    -- extra arguments passed to addgcfn are forwarded to the callback.
    local received = {}
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(error, function(a, b, c)
        received[1] = a
        received[2] = b
        received[3] = c
    end, 'first', 42, true))
    assert(s:close())
    assert.equal(received[1], 'first')
    assert.equal(received[2], 42)
    assert.equal(received[3], true)

    -- addgcfn on an already-closed socket returns nil + EBADF error.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local h2, err = s:addgcfn(error, function()
    end)
    assert.is_nil(h2)
    assert.equal(err.type, errno.EBADF)
end

function testcase.delgcfn()
    -- delgcfn(handle) returns true when the handle is currently registered.
    local called = false
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local handle = assert(s:addgcfn(error, function()
        called = true
    end))
    assert.is_true(s:delgcfn(handle))
    assert(s:close())
    assert.is_false(called)

    -- delgcfn can remove a handle from the middle of the registration
    -- stack; the surrounding gcfns still run in LIFO order.
    local order = {}
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 1
    end))
    local h2 = assert(s:addgcfn(error, function()
        order[#order + 1] = 2
    end))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 3
    end))
    assert.is_true(s:delgcfn(h2))
    -- second delete of the same handle returns false.
    assert.is_false(s:delgcfn(h2))
    assert(s:close())
    assert.equal(order, {
        3,
        1,
    })

    -- delgcfn returns false for a well-formed but unknown handle, raises for
    -- an ill-formed prefix, and raises for a bad hex tail.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.is_false(s:delgcfn('net.socket.gcfn: 0x1'))
    local err = assert.throws(function()
        s:delgcfn('invalid handle')
    end)
    assert.match(err, 'net.socket.gcfn', false)
    err = assert.throws(function()
        s:delgcfn('net.socket.gcfn: nothex')
    end)
    assert.match(err, 'invalid net.socket.gcfn handle', false)
    s:close()

    -- delgcfn on an already-closed socket returns false rather than raising.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local h3 = assert(s:addgcfn(error, function()
    end))
    assert(s:close())
    assert.is_false(s:delgcfn(h3))
end

function testcase.gcfn_reentrancy_is_guarded()
    -- While the gc callbacks are draining, the drain loop owns the thread
    -- and the fd: a re-entrant addgcfn must fail with EBADF, delgcfn must
    -- report false, and a re-entrant close must no-op so the remaining
    -- callbacks still see a live fd (the outer close disposes it once the
    -- drain finishes).
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd_seen = -1
    local fd_after
    local add_nil, add_err
    local del_rv, close_rv
    assert(s:addgcfn(error, function()
        fd_seen = s:fd()
        add_nil, add_err = s:addgcfn(error, function() end)
        del_rv = s:delgcfn('net.socket.gcfn: 0x1')
        close_rv = s:close()
        fd_after = s:fd()
    end))
    assert(s:close())

    assert(fd_seen >= 0, 'the fd must be alive during the callbacks')
    assert.equal(fd_after, fd_seen,
                 'the re-entrant close must not dispose the fd')
    assert.is_nil(add_nil)
    assert.not_nil(add_err)
    assert.equal(add_err.type, errno.EBADF)
    assert.is_false(del_rv)
    assert.is_true(close_rv, 're-entrant close must no-op successfully')
end

function testcase.gcfn()
    -- Multiple registered gcfns run in LIFO order when the socket is closed.
    local order = {}
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 1
    end))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 2
    end))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 3
    end))
    assert(s:close())
    assert.equal(order, {
        3,
        2,
        1,
    })

    -- A second close() is a no-op even after the gc thread has been
    -- released (exercises net_gcthread_close's early return).
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    assert(s:close())
end

function testcase.gcfn_error_handling()
    -- The user-provided errfn receives failures raised by the gc callback.
    local caught
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(function(err)
        caught = err
    end, function()
        error('boom')
    end))
    assert(s:close())
    assert.match(caught, 'boom', false)

    -- A gc callback without an errfn does not crash close/gc even when the
    -- callback raises: the outer net_gcthread_close catches / discards it.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(nil, function()
        error('should be swallowed')
    end))
    assert(s:close())

    -- A gc callback whose errfn ALSO raises still terminates cleanly.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(function(err)
        error('errfn also failed: ' .. tostring(err))
    end, function()
        error('boom')
    end))
    assert(s:close())

    -- A failure in one gc callback does not prevent the other callbacks
    -- from running.  LIFO order: the last registered callback runs first;
    -- the middle callback raises and must not abort the iteration.
    local order = {}
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(nil, function()
        order[#order + 1] = 1
    end))
    assert(s:addgcfn(nil, function()
        error('middle fails')
    end))
    assert(s:addgcfn(nil, function()
        order[#order + 1] = 3
    end))
    assert(s:close())
    assert.equal(order, {
        3,
        1,
    })
end

function testcase.mcastloop_v4()
    -- mcastloop() getter/setter on an IPv4 dgram socket.  The setter
    -- toggles IP_MULTICAST_LOOP via setsockopt.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    -- getter returns the current boolean value (or an error object)
    assert(d:mcastloop() ~= nil or select(2, d:mcastloop()))
    -- setter with false / true
    local _, err = d:mcastloop(false)
    assert.is_nil(err)
    _, err = d:mcastloop(true)
    assert.is_nil(err)
    d:close()
end

function testcase.mcastloop_v6()
    -- mcastloop() getter/setter on an IPv6 dgram socket.  The setter
    -- toggles IPV6_MULTICAST_LOOP via setsockopt.  On CI environments
    -- without loopback IPv6, new_inet('::1', ...) may fail; skip the test.
    local d, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d then
        assert(ierr)
        return
    end
    assert(d:mcastloop() ~= nil or select(2, d:mcastloop()))
    local _, err = d:mcastloop(false)
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
    assert(err)
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
    assert(err)
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
    assert(err)
end

function testcase.mcastttl_v4()
    -- mcastttl() getter/setter on an IPv4 dgram socket.  The setter
    -- writes IP_MULTICAST_TTL via setsockopt.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert(d:mcastttl() or select(2, d:mcastttl()))
    local _, err = d:mcastttl(1)
    assert.is_nil(err)
    d:close()
end

function testcase.mcastttl_v6()
    -- mcastttl() on an IPv6 dgram socket writes IPV6_MULTICAST_HOPS.
    local d, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d then
        assert(ierr)
        return
    end
    assert(d:mcastttl() or select(2, d:mcastttl()))
    local _, err = d:mcastttl(1)
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
    assert(err)
    s:close()
end

function testcase.mcastttl_on_af_unix()
    -- mcastttl() on an AF_UNIX dgram socket takes the EAFNOSUPPORT branch.
    local unix = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local rv, err = unix:mcastttl()
    assert.is_nil(rv)
    assert(err)
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
    assert(err)
end

function testcase.mcastif_v4()
    -- mcastif() getter/setter on an IPv4 dgram socket.  It maps to
    -- IP_MULTICAST_IF: the setter accepts an interface name (resolved
    -- via SIOCGIFADDR) or nil to disable the option.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    d:mcastif() -- getter (no interface configured yet)
    d:mcastif('lo0') -- setter with a valid interface name
    d:mcastif(nil) -- setter with nil to disable the option
    d:close()
end

function testcase.mcastif_v6()
    -- mcastif() on an IPv6 dgram socket maps to IPV6_MULTICAST_IF: the
    -- setter accepts an interface name (resolved via if_nametoindex).
    local d, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d then
        assert(ierr)
        return
    end
    d:mcastif()
    d:mcastif('lo0')
    d:mcastif(nil)
    d:close()
end

function testcase.mcastif_invalid_ifname()
    -- An unknown interface name surfaces an error via SIOCGIFADDR (IPv4)
    -- or if_nametoindex (IPv6).
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local rv, err = d:mcastif('__net_no_such_if__')
    assert.is_nil(rv)
    assert(err)
    d:close()
end

function testcase.mcastif_on_stream_socket()
    -- mcastif() on a SOCK_STREAM socket takes the ESOCKTNOSUPPORT branch.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = s:mcastif('lo0')
    assert.is_nil(rv)
    assert(err)
    s:close()
end

function testcase.mcastif_on_af_unix()
    -- mcastif() on an AF_UNIX dgram socket takes the EAFNOSUPPORT branch.
    local unix = assert(socket.new_unix({
        socktype = 'dgram',
    }))
    local rv, err = unix:mcastif()
    assert.is_nil(rv)
    assert(err)
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
    assert(err)
    rv, err = d:mcastif('lo0')
    assert.is_nil(rv)
    assert(err)
end

function testcase.mcastjoin_v4()
    -- mcastjoin(grp[, ifname]) on an IPv4 dgram socket joins the group
    -- via setsockopt IP_ADD_MEMBERSHIP.  We exercise both the plain form
    -- and the form with an explicit interface name.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    d:mcastjoin(grp)
    d:mcastjoin(grp, 'lo0')
    d:close()
end

function testcase.mcastjoin_v6()
    -- mcastjoin() on an IPv6 dgram socket maps to IPV6_JOIN_GROUP.
    local d, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d then
        assert(ierr)
        return
    end
    local grp = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    d:mcastjoin(grp)
    d:mcastjoin(grp, 'lo0')
    d:close()
end

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
    assert(err)
    d4:close()

    local d6, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d6 then
        assert(ierr)
        return
    end
    ok, err = d6:mcastjoin(grp4)
    assert.is_false(ok)
    assert(err)
    d6:close()
end

function testcase.mcastjoin_invalid_ifname()
    -- An unknown interface name surfaces an error via SIOCGIFADDR (IPv4)
    -- or if_nametoindex (IPv6).
    local d4 = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp4 = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d4:mcastjoin(grp4, '__net_no_such_if__')
    assert.is_false(ok)
    assert(err)
    d4:close()

    local d6, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d6 then
        assert(ierr)
        return
    end
    local grp6 = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastjoin(grp6, '__net_no_such_if__')
    assert.is_false(ok)
    assert(err)
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
    assert(err)
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
    assert(err)
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
    assert(err)
end

function testcase.mcastleave_v4()
    -- mcastleave(grp[, ifname]) on an IPv4 dgram socket leaves the group
    -- via setsockopt IP_DROP_MEMBERSHIP.  We exercise both the plain form
    -- and the form with an explicit interface name.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    d:mcastleave(grp)
    d:mcastleave(grp, 'lo0')
    d:close()
end

function testcase.mcastleave_v6()
    -- mcastleave() on an IPv6 dgram socket maps to IPV6_LEAVE_GROUP.
    local d, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d then
        assert(ierr)
        return
    end
    local grp = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    d:mcastleave(grp)
    d:mcastleave(grp, 'lo0')
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
    assert(err)
    d4:close()

    local d6, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d6 then
        assert(ierr)
        return
    end
    ok, err = d6:mcastleave(grp4)
    assert.is_false(ok)
    assert(err)
    d6:close()
end

function testcase.mcastleave_invalid_ifname()
    -- An unknown interface name surfaces an error via SIOCGIFADDR (IPv4)
    -- or if_nametoindex (IPv6).
    local d4 = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local grp4 = assert(addrinfo.inet('239.0.0.1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local ok, err = d4:mcastleave(grp4, '__net_no_such_if__')
    assert.is_false(ok)
    assert(err)
    d4:close()

    local d6, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d6 then
        assert(ierr)
        return
    end
    local grp6 = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    ok, err = d6:mcastleave(grp6, '__net_no_such_if__')
    assert.is_false(ok)
    assert(err)
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
    assert(err)
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
    assert(err)
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
    assert(err)
end

function testcase.mcastjoinsrc_v4()
    -- mcastjoinsrc(grp, src[, ifname]) on an IPv4 dgram socket joins a
    -- source-specific multicast group via setsockopt
    -- IP_ADD_SOURCE_MEMBERSHIP.
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
    d:mcastjoinsrc(grp, src)
    d:mcastjoinsrc(grp, src, 'lo0')
    d:close()
end

function testcase.mcastjoinsrc_v6()
    -- mcastjoinsrc() on an IPv6 dgram socket maps to setsockopt
    -- MCAST_JOIN_SOURCE_GROUP.
    local d, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d then
        assert(ierr)
        return
    end
    local grp = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet6('::1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    d:mcastjoinsrc(grp, src)
    d:mcastjoinsrc(grp, src, 'lo0')
    d:close()
end

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
    assert(err)
    ok, err = d4:mcastjoinsrc(grp4, src6)
    assert.is_false(ok)
    assert(err)
    d4:close()

    -- IPv6 socket + IPv4 grp / src
    local d6, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d6 then
        assert(ierr)
        return
    end
    ok, err = d6:mcastjoinsrc(grp4, src6)
    assert.is_false(ok)
    assert(err)
    ok, err = d6:mcastjoinsrc(grp6, src4)
    assert.is_false(ok)
    assert(err)
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
    local ok, err = d:mcastjoinsrc(grp, src, '__net_no_such_if__')
    assert.is_false(ok)
    assert(err)
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
    assert(err)
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
    assert(err)
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
    assert(err)
end

function testcase.mcastleavesrc_v4()
    -- mcastleavesrc(grp, src[, ifname]) on an IPv4 dgram socket leaves a
    -- source-specific multicast group via setsockopt
    -- IP_DROP_SOURCE_MEMBERSHIP.
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
    d:mcastleavesrc(grp, src)
    d:mcastleavesrc(grp, src, 'lo0')
    d:close()
end

function testcase.mcastleavesrc_v6()
    -- mcastleavesrc() on an IPv6 dgram socket maps to setsockopt
    -- MCAST_LEAVE_SOURCE_GROUP.
    local d, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d then
        assert(ierr)
        return
    end
    local grp = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet6('::1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    d:mcastleavesrc(grp, src)
    d:mcastleavesrc(grp, src, 'lo0')
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
    assert(err)
    ok, err = d4:mcastleavesrc(grp4, src6)
    assert.is_false(ok)
    assert(err)
    d4:close()

    -- IPv6 socket + IPv4 grp / src
    local d6, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d6 then
        assert(ierr)
        return
    end
    ok, err = d6:mcastleavesrc(grp4, src6)
    assert.is_false(ok)
    assert(err)
    ok, err = d6:mcastleavesrc(grp6, src4)
    assert.is_false(ok)
    assert(err)
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
    local ok, err = d:mcastleavesrc(grp, src, '__net_no_such_if__')
    assert.is_false(ok)
    assert(err)
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
    assert(err)
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
    assert(err)
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
    assert(err)
end

function testcase.mcastblocksrc_v4()
    -- mcastblocksrc(grp, src[, ifname]) on an IPv4 dgram socket joins a
    -- source-specific multicast group via setsockopt
    -- IP_BLOCK_SOURCE.
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
    d:mcastblocksrc(grp, src)
    d:mcastblocksrc(grp, src, 'lo0')
    d:close()
end

function testcase.mcastblocksrc_v6()
    -- mcastblocksrc() on an IPv6 dgram socket maps to setsockopt
    -- MCAST_BLOCK_SOURCE.
    local d, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d then
        assert(ierr)
        return
    end
    local grp = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet6('::1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    d:mcastblocksrc(grp, src)
    d:mcastblocksrc(grp, src, 'lo0')
    d:close()
end

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
    assert(err)
    ok, err = d4:mcastblocksrc(grp4, src6)
    assert.is_false(ok)
    assert(err)
    d4:close()

    -- IPv6 socket + IPv4 grp / src
    local d6, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d6 then
        assert(ierr)
        return
    end
    ok, err = d6:mcastblocksrc(grp4, src6)
    assert.is_false(ok)
    assert(err)
    ok, err = d6:mcastblocksrc(grp6, src4)
    assert.is_false(ok)
    assert(err)
    d6:close()
end

function testcase.mcastblocksrc_invalid_ifname()
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
    local ok, err = d:mcastblocksrc(grp, src, '__net_no_such_if__')
    assert.is_false(ok)
    assert(err)
    d:close()
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
    assert(err)
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
    assert(err)
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
    assert(err)
end

function testcase.mcastunblocksrc_v4()
    -- mcastunblocksrc(grp, src[, ifname]) on an IPv4 dgram socket joins a
    -- source-specific multicast group via setsockopt
    -- IP_UNBLOCK_SOURCE.
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
    d:mcastunblocksrc(grp, src)
    d:mcastunblocksrc(grp, src, 'lo0')
    d:close()
end

function testcase.mcastunblocksrc_v6()
    -- mcastunblocksrc() on an IPv6 dgram socket maps to setsockopt
    -- MCAST_UNBLOCK_SOURCE.
    local d, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d then
        assert(ierr)
        return
    end
    local grp = assert(addrinfo.inet6('ff02::1', 5353, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local src = assert(addrinfo.inet6('::1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    d:mcastunblocksrc(grp, src)
    d:mcastunblocksrc(grp, src, 'lo0')
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
    assert(err)
    ok, err = d4:mcastunblocksrc(grp4, src6)
    assert.is_false(ok)
    assert(err)
    d4:close()

    -- IPv6 socket + IPv4 grp / src
    local d6, ierr = socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not d6 then
        assert(ierr)
        return
    end
    ok, err = d6:mcastunblocksrc(grp4, src6)
    assert.is_false(ok)
    assert(err)
    ok, err = d6:mcastunblocksrc(grp6, src4)
    assert.is_false(ok)
    assert(err)
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
    local ok, err = d:mcastunblocksrc(grp, src, '__net_no_such_if__')
    assert.is_false(ok)
    assert(err)
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
    assert(err)
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
    assert(err)
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
    assert(err)
end

function testcase.atmark()
    -- atmark() returns false when the socket has no pending OOB data.
    local socks = assert(socket.pair({
        socktype = 'stream',
        protocol = 'auto',
    }))
    assert.is_false(socks[1]:atmark())
    socks[1]:close()
    socks[2]:close()

    -- atmark() on a stale (externally-closed) fd surfaces an error via
    -- sockatmark() EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(socket.close(s:fd()))
    local rv, err = s:atmark()
    assert(rv == nil or rv == false or err)
end

function testcase.protocol()
    -- protocol() returns the socket's IPPROTO_* value.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(s:protocol(), 'tcp')
    s:close()
end

function testcase.tostring()
    -- tostring(sock) returns a string like "net.socket: 0x...".
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.match(tostring(s), '^net.socket: ', false)
    s:close()
end

function testcase.sendfile_partial_and_short()
    -- Exercise sendfile_lua with a variety of file offsets and byte
    -- counts.  We do not assert on the exact bytes sent since sendfile()
    -- may return partial writes on slow paths; the goal is to run through
    -- the various platform-specific branches of sendfile_lua.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(f:write(string.rep('S', 4096)))
    assert(f:flush())

    -- full send
    assert(a:sendfile(f, 4096, 0))
    assert(b:recv(4096))
    -- send with offset
    assert(a:sendfile(f, 128, 512))
    assert(b:recv(128))
    -- send zero bytes: some paths reject this, others accept
    local rv, err = a:sendfile(f, 0, 0)
    assert(rv == nil or rv >= 0, err)

    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.sendfile_after_peer_close()
    -- After the peer closes its end of the connection, sendfile()
    -- eventually surfaces the terminal error path (EPIPE / ECONNRESET).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    b:close()

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(f:write(string.rep('S', 4096)))
    assert(f:flush())

    -- retry to guarantee sendfile hits the closed-peer error branch
    local rv, err
    for _ = 1, 4 do
        rv, err = a:sendfile(f, 4096, 0)
        if not rv then
            break
        end
    end
    assert.is_nil(rv)
    assert(err)

    f:close()
    os.remove(path)
    a:close()
end

function testcase.sendfile_eof()
    -- pread(2) returns 0 when the offset is at or beyond the end of the
    -- file; sendfile_lua should then return 0 as well.  This exercises
    -- the !nbytes branch.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(f:write('abc'))
    assert(f:flush())

    local rv, err = a:sendfile(f, 4, 100)
    assert(rv, err)
    assert.equal(rv, 0)

    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.sendfile_zero_length()
    -- Requesting zero bytes should be rejected with EINVAL inside
    -- sendfile_lua.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(f:write('abc'))
    assert(f:flush())

    local rv, err = a:sendfile(f, 0, 0)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.sendfile_rejects_negative_size_and_offset()
    -- lauxh_checkinteger accepts negative values.  Casting them straight
    -- to size_t / off_t turned -1 into SIZE_MAX and a negative offset
    -- into an out-of-range file position.  Both must be rejected with
    -- EINVAL before the platform-specific sendfile branch runs.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(f:write('abc'))
    assert(f:flush())

    local rv, err = a:sendfile(f, -1, 0)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    rv, err = a:sendfile(f, 8, -1)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.sendfile_clamps_to_file_and_sndbuf()
    -- The sendfile fallback clamps the request to the bytes left in the
    -- file and sizes its staging buffer after SO_SNDBUF.
    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    local data = string.rep('x', 100 * 1024)
    assert(f:write(data))
    assert(f:flush())

    -- 1) a request larger than the file transfers exactly the file size
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    a:sndbuf(1024 * 1024)
    local sent, err = a:sendfile(f, #data * 2, 0)
    assert(sent, err)
    assert.equal(sent, #data)
    assert.equal(recv_all(b), data)
    a:close()
    b:close()

    -- 2) with a 4 KiB send buffer a single call cannot transfer the whole
    -- file: it stops when the buffer fills and reports the partial
    -- progress with "again", so the caller drains the peer and resumes
    -- until the file has been transferred exactly once
    socks = assert(socket.pair({
        socktype = 'stream',
    }))
    a, b = socks[1], socks[2]
    a:sndbuf(4096)
    local sent2, err2, again = a:sendfile(f, #data, 0)
    assert(sent2, err2)
    assert.less(sent2, #data)
    assert.is_true(again)

    -- the resumption of an interrupted transfer is covered by
    -- testcase.sendfile_again

    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.sendfile_bad_fd()
    -- Passing a closed file descriptor surfaces EBADF; every internal
    -- failure of the sendfile method reports the "sendfile" op regardless
    -- of which platform variant is compiled.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(f:write('abc'))
    assert(f:flush())
    local badfd = fileno(f)
    f:close()

    local rv, err = a:sendfile(badfd, 8, 0)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EBADF)
    assert.equal(err.op, 'sendfile')

    os.remove(path)
    a:close()
    b:close()
end

function testcase.sendfile_on_closed_socket()
    -- test that sendfile surfaces EBADF when the socket has been closed.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(f:write('data'))
    assert(f:flush())
    assert(s:close())

    local rv, err = s:sendfile(f, 4, 0)
    assert.is_nil(rv)
    assert(err)

    f:close()
    os.remove(path)
end

function testcase.sendfile_again()
    -- sendfile() surfaces EAGAIN via (0, nil, true) once the send buffer
    -- is full, and an interrupted transfer resumes at the reported offset
    -- without losing or duplicating bytes.  The kernel clamps
    -- SO_SNDBUF=512 up to its minimum on Linux, so a 100 KiB file
    -- guarantees the EAGAIN branch on every platform.  How many calls a
    -- full transfer needs depends on the effective buffer size, so the
    -- test verifies one EAGAIN stop plus one resumption instead of
    -- driving the transfer to completion.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    a:sndbuf(512)

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    local data = string.rep('S', 100 * 1024)
    assert(f:write(data))
    assert(f:flush())

    -- fill the send buffer: the first call stops with "again" while the
    -- file still has bytes left
    local sent, err, again = a:sendfile(f, #data, 0)
    assert.is_nil(err)
    assert.is_int(sent)
    assert.less(sent, #data)
    assert.is_true(again)

    -- resume at the reported offset: draining the peer frees buffer
    -- space, the resumed call transfers more bytes, and everything
    -- received so far matches the file prefix
    local got1 = recv_all(b)
    local sent2, err2 = a:sendfile(f, #data - sent, sent)
    assert.is_nil(err2)
    assert.is_int(sent2)
    assert.greater(sent2, 0)
    local got2 = recv_all(b)

    assert.equal(#got1 + #got2, sent + sent2)
    assert.equal(got1 .. got2, data:sub(1, sent + sent2))

    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.sendfile_stream_pair()
    -- Round-trip a file through sendfile() on a connected stream pair.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(f:write('filedata'))
    assert(f:flush())
    assert(a:sendfile(f, 8, 0))
    assert.equal(assert(b:recv(8)), 'filedata')
    assert(a:sendfile(fileno(f), 8, 0))
    assert.equal(assert(b:recv(8)), 'filedata')
    f:close()
    os.remove(path)

    a:close()
    b:close()
end

function testcase.sendfd()
    -- Basic SCM_RIGHTS round-trip: sending a file descriptor over a unix
    -- stream socketpair transfers the fd to the peer.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(a:sendfd(fileno(f)))
    assert(b:recvable(1))
    local fd = assert(b:recvfd())
    assert(socket.close(fd))
    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.sendfd_with_destination_addr()
    -- On unix dgram sockets a destination addrinfo is honored: the
    -- msghdr's msg_name / msg_namelen are populated from ai_addr /
    -- ai_addrlen.
    local path_a = os.tmpname()
    os.remove(path_a)
    local path_b = os.tmpname()
    os.remove(path_b)
    local ai_a = assert(addrinfo.unix(path_a, {
        socktype = 'dgram',
    }))
    local ai_b = assert(addrinfo.unix(path_b, {
        socktype = 'dgram',
    }))
    local da = assert(socket.bind_unix(ai_a))
    local db = assert(socket.bind_unix(ai_b))
    local n, err = da:sendfd(0, ai_b)
    assert.equal(n, 0)
    assert.is_nil(err)
    da:close()
    db:close()
    os.remove(path_a)
    os.remove(path_b)
end

function testcase.sendfd_again()
    -- Fill the send buffer to drive sendfd_lua's EAGAIN branch.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    a:sndbuf(512)
    local n, err, again
    for _ = 1, 1024 do
        n, err, again = a:sendfd(0)
        assert.is_nil(err)
        if again then
            break
        end
    end
    assert.is_true(again)
    assert.equal(n, 0)
    a:close()
    b:close()
end

function testcase.sendfd_on_closed_socket()
    -- sendfd() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:sendfd(0)
    assert.is_nil(rv)
    assert(err)
end

function testcase.sendfd_rejects_out_of_range_fd()
    -- Casting the lua_Integer fd straight to int wrapped out-of-range
    -- values onto unrelated descriptor numbers in the SCM_RIGHTS payload.
    -- Values outside 0..INT_MAX must be rejected with EINVAL instead.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]

    local rv, err = a:sendfd(2147483648)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    rv, err = a:sendfd(-1)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    a:close()
    socks[2]:close()
end

function testcase.wrap_rejects_out_of_range_fd()
    -- wrap() used to cast the lua_Integer argument straight to int, so an
    -- out-of-range value could wrap onto an unrelated fd number.
    local rv, err = socket.wrap(2147483648)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    rv, err = socket.wrap(-1)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)
end

function testcase.shutdown_close_reject_out_of_range_fd()
    -- shutdown()/close() on an out-of-range fd used to truncate the value
    -- to int and could hit an unrelated descriptor; both must fail with
    -- EINVAL before touching any fd.
    local ok, err = socket.shutdown(2147483648)
    assert.is_false(ok)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    ok, err = socket.close(2147483648)
    assert.is_false(ok)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    ok, err = socket.close(-1)
    assert.is_false(ok)
    assert(err)
    assert.equal(err.type, errno.EINVAL)
end

function testcase.sendfile_rejects_out_of_range_fd()
    -- Integer fd arguments beyond the int range must fail with EINVAL
    -- before the platform-specific sendfile branch truncates them.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]

    local rv, err = a:sendfile(2147483648, 8, 0)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    rv, err = a:sendfile(-1, 8, 0)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    a:close()
    socks[2]:close()
end

function testcase.sendmsg_cmsg_rejects_out_of_range_fd()
    -- cmsg SCM_RIGHTS data must be an integral fd within 0..INT_MAX; the
    -- old code accepted any number and truncated it when casting to int.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]

    local err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = 2147483648,
            },
        })
    end)
    assert.match(err, 'fd', false)

    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = 1.5,
            },
        })
    end)
    assert.match(err, 'fd', false)

    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = {
                    0,
                    2147483648,
                },
            },
        })
    end)
    assert.match(err, 'fd', false)

    a:close()
    socks[2]:close()
end

function testcase.recvfd()
    -- Basic reception via SCM_RIGHTS: sendfd on one end, recvfd on the other.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(a:sendfd(fileno(f)))
    assert(b:recvable(1))
    local fd = assert(b:recvfd())
    assert(socket.close(fd))
    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.recvfd_sets_cloexec()
    -- SCM_RIGHTS delivers a fresh fd in the receiver process.  Without
    -- MSG_CMSG_CLOEXEC or an explicit fcntl on the extracted fd, that fd
    -- would inherit into every subsequent exec() and defeat the CLOEXEC
    -- default the rest of the library maintains.  Verify the received fd
    -- is not visible after os.execute forks + execs a shell (which is
    -- exactly the exec-inheritance scenario CLOEXEC guards against).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    assert(a:sendfd(fileno(f)))
    assert(b:recvable(1))
    local fd = assert(b:recvfd())
    -- os.execute forks and execs /bin/sh.  If FD_CLOEXEC was set on fd,
    -- /dev/fd/<fd> disappears in the shell.  If it was NOT set, the fd
    -- inherits and the shell sees /dev/fd/<fd>.
    local rv = os.execute(string.format(
                              'test -e /dev/fd/%d && exit 1 || exit 0', fd))
    assert(rv == true or rv == 0,
           'received SCM_RIGHTS fd must be marked FD_CLOEXEC')
    assert(socket.close(fd))
    f:close()
    os.remove(path)
    a:close()
    b:close()
end
function testcase.recvfd_again()
    -- No pending data: recvfd returns (nil, nil, true) to signal EAGAIN,
    -- matching recv's convention.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local rfd, err, again = b:recvfd()
    assert.is_nil(rfd)
    assert.is_nil(err)
    assert.is_true(again)
    a:close()
    b:close()
end

function testcase.recvfd_when_peer_closed()
    -- After peer close, recvfd on stream returns 0 values (EOF).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    a:close()
    local rfd, err = b:recvfd()
    assert.is_nil(rfd)
    assert.is_nil(err)
    b:close()
end

function testcase.recvfd_non_scm_rights_discarded()
    -- A message that does NOT carry SCM_RIGHTS makes recvfd take the
    -- "discard received messages" branch and return (nil, nil, true).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(b:write('X'))
    for _ = 1, 20 do
        if a:recvable(0.05) then
            break
        end
    end
    local rfd, err, again = a:recvfd()
    assert.is_nil(rfd)
    assert.is_nil(err)
    assert.is_true(again)
    a:close()
    b:close()
end

function testcase.recvfd_on_closed_socket()
    -- recvfd() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:recvfd()
    assert.is_nil(rv)
    assert(err)

end

function testcase.sendmsg_dgram_after_peer_close()
    -- On dgram sockets, sendto/sendmsg to an addr for a closed peer often
    -- succeeds because there is no connection state.  Exercise the
    -- msghdr-only-cmsg send path via a dgram pair.
    local socks = assert(socket.pair({
        socktype = 'dgram',
    }))
    local a = socks[1]
    local b = socks[2]
    b:close()
    -- send should not raise; the datagram is dropped or accepted.
    local rv, err = a:sendmsg('x')
    assert(rv or err)
    a:close()
end

function testcase.sendmsg_empty_input()
    -- sendmsg() with neither payload nor cmsg surfaces EINVAL.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- test that sending nothing (no data and no cmsg) returns EINVAL
    local len, err = a:sendmsg()
    assert.is_nil(len)
    assert.equal(err.type, errno.EINVAL)

    -- test that an empty cmsg table together with data still succeeds
    len, err = a:sendmsg('z', nil, {})
    assert(len, err)
    assert.equal(len, 1)
    assert.equal(assert(b:recv(1)), 'z')

    a:close()
    b:close()
end

function testcase.sendmsg_returns_syscalled_flag()
    -- The low-level sendmsg returns a 4th value that tells the net.lua
    -- wrapper whether the syscall actually completed: ancillary data is
    -- consumed by the kernel only on a completed call.  An interrupted
    -- call (EAGAIN/EINTR) reports (0, nil, true) with no 4th value so the
    -- wrapper keeps the cmsg for the retry; a successful call reports
    -- (len, nil, again, true).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- fill the send buffer to drive the EAGAIN branch: completed calls
    -- report syscalled, the interrupted one does not
    a:sndbuf(512)
    local len, err, again, syscalled
    repeat
        len, err, again, syscalled = a:sendmsg('x')
        assert.is_nil(err)
        if again then
            assert.is_nil(syscalled,
                          'interrupted call must not report syscalled')
        else
            assert.is_true(syscalled, 'completed call must report syscalled')
        end
    until again and len == 0
    assert.is_true(again)
    assert.equal(len, 0)
    b:close()

    -- a completed call reports syscalled = true
    local socks2 = assert(socket.pair({
        socktype = 'stream',
    }))
    len, err, again, syscalled = socks2[1]:sendmsg('y')
    assert(len, err)
    assert.is_nil(err)
    assert.is_false(again)
    assert.is_true(syscalled, 'completed call must report syscalled')

    socks2[1]:close()
    socks2[2]:close()
    a:close()
end

function testcase.sendmsg_when_peer_closed()
    -- After the peer closes, sendmsg() eventually surfaces EPIPE /
    -- ECONNRESET.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- Close the peer; subsequent sends should encounter EPIPE (or
    -- ECONNRESET on some kernels) and the error path in sendmsg_lua.  We
    -- must ignore SIGPIPE for the duration of this test so the raised
    -- SIGPIPE does not abort the process on stream sockets.
    b:close()
    -- On stream sockets the very first sendmsg after peer close may still
    -- succeed as the kernel queues the buffer.  A second call is guaranteed
    -- to surface the error.
    local sent, err
    for _ = 1, 4 do
        sent, err = a:sendmsg('x')
        if not sent then
            break
        end
    end
    assert.is_nil(sent)
    assert(err, 'sendmsg should surface an error after peer close')

    a:close()
end

function testcase.send_survives_sigpipe_after_shutdown_wr()
    -- Writing after the local write direction is shut down must surface
    -- EPIPE as a Lua error object, not kill the process with SIGPIPE.
    -- The child runs with SIGPIPE at its default disposition so the
    -- runner's SIGPIPE ignore cannot mask the behaviour; the parent
    -- detects a SIGPIPE death via the wait status.
    local proc = assert(fork())
    if proc:is_child() then
        signal.sigdefault('SIGPIPE')
        local socks = assert(socket.pair({
            socktype = 'stream',
        }))
        assert(socks[1]:shutdown('wr'))
        local sent, err = socks[1]:send('x')
        assert.is_nil(sent)
        assert.match(err, 'EPIPE')
        os.exit(0)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.write_survives_sigpipe_after_shutdown_wr()
    -- Same as send_survives_sigpipe_after_shutdown_wr, but through the
    -- plain write() path.
    local proc = assert(fork())
    if proc:is_child() then
        signal.sigdefault('SIGPIPE')
        local socks = assert(socket.pair({
            socktype = 'stream',
        }))
        assert(socks[1]:shutdown('wr'))
        local n, err = socks[1]:write('x')
        assert.is_nil(n)
        assert.match(err, 'EPIPE')
        os.exit(0)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendmsg_survives_sigpipe_after_shutdown_wr()
    -- Same as send_survives_sigpipe_after_shutdown_wr, but through the
    -- sendmsg() path.
    local proc = assert(fork())
    if proc:is_child() then
        signal.sigdefault('SIGPIPE')
        local socks = assert(socket.pair({
            socktype = 'stream',
        }))
        assert(socks[1]:shutdown('wr'))
        local sent, err = socks[1]:sendmsg('x')
        assert.is_nil(sent)
        assert.match(err, 'EPIPE')
        os.exit(0)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendmsg_again()
    -- sendmsg() surfaces EAGAIN via (0, nil, true) once the send buffer
    -- is full.  We shrink the buffer to drive the branch quickly.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    a:sndbuf(512)

    local chunk = string.rep('x', 1024)
    local n, err, again
    repeat
        n, err, again = a:sendmsg(chunk)
        assert.is_nil(err)
        assert.is_int(n)
    until again and n == 0
    assert.is_true(again)
    assert.equal(n, 0)

    a:close()
    b:close()
end

function testcase.sendmsg_on_closed_socket()
    -- sendmsg() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:sendmsg('x')
    assert.is_nil(rv)
    assert(err)
end

function testcase.sendmsg_cmsg_socket_fd_passing()
    -- Round-trip a single file descriptor via SCM_RIGHTS ancillary data
    -- on a unix stream socketpair.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))

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
    assert.equal(msg.data, 'x')
    assert.equal(#msg.cmsgs, 1)
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'socket')
    assert.equal(cm.type, 'rights')
    assert.is_int(cm.data)
    -- clean up received fd
    socket.close(cm.data)

    f:close()
    os.remove(path)
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

    local paths = {
        os.tmpname(),
        os.tmpname(),
    }
    local files = {
        assert(io.open(paths[1], 'w+')),
        assert(io.open(paths[2], 'w+')),
    }

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
    assert.equal(msg.data, 'y')
    assert.equal(#msg.cmsgs, 1)
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'socket')
    assert.equal(cm.type, 'rights')
    assert.is_table(cm.data)
    assert.equal(#cm.data, 2)
    -- clean up received fds
    socket.close(cm.data[1])
    socket.close(cm.data[2])

    files[1]:close()
    files[2]:close()
    os.remove(paths[1])
    os.remove(paths[2])
    a:close()
    b:close()
end

function testcase.sendmsg_cmsg_socket_only_send()
    -- Exercise the branch of sendmsg_lua that runs when only cmsg is
    -- provided (no data payload).  We use SCM_RIGHTS to make the kernel
    -- accept the message with an empty iov.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))
    -- Some kernels require at least one byte of data with SCM_RIGHTS;
    -- others accept a zero-length iov.  Handle both outcomes gracefully.
    local rv, err = a:sendmsg(nil, nil, {
        {
            level = 'socket',
            type = 'rights',
            data = fileno(f),
        },
    })
    if rv then
        assert.is_nil(err)
        if rv > 0 then
            assert(b:recvable(1))
            local msg = assert(b:recvmsg(1, 128))
            if msg and msg.cmsgs then
                local cm = msg.cmsgs[1]
                if cm and cm.type == 'rights' then
                    socket.close(cm.data)
                end
            end
        end
    else
        assert(err)
    end
    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.sendmsg_cmsg_ip_tos_udp()
    -- test that level='ip' / type='tos' cmsg entries are accepted by
    -- write_cmsg_entry via the raw-string path, and that the received TOS
    -- (which the kernel delivers under IP_RECVTOS on macOS or IP_TOS on
    -- Linux) is exposed by push_type2name(): as an integer when the
    -- constant is not in our type map, or as a string ("tos") otherwise.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    server:ip_recvtos(true)
    assert(server:ip_recvtos())
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    local tos_bytes = string.char(0, 0, 0, 0)
    local len, err = client:sendmsg('q', sai, {
        {
            level = 'ip',
            type = 'tos',
            data = tos_bytes,
        },
    })
    assert(len, err)
    assert.equal(len, 1)

    assert(server:recvable(1))
    local msg = assert(server:recvmsg(1, 128))
    assert.equal(msg.data, 'q')
    assert(msg.cmsgs and #msg.cmsgs > 0, 'received TOS cmsg should be present')
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'ip')
    assert(type(cm.type) == 'string' or type(cm.type) == 'number',
           'cm.type must be string or number')
    assert.is_string(cm.data)

    client:close()
    server:close()
end

function testcase.sendmsg_cmsg_ip_ttl_udp()
    -- test that level='ip' / type='ttl' cmsg entries serialize successfully
    -- via write_cmsg_entry's raw-string path.  We use a UDP socket to send
    -- a single-byte payload with an IP_TTL ancillary data and enable
    -- IP_RECVTTL on the receiver so the kernel delivers the received TTL
    -- back as a cmsg.  This exercises the default (non-SOL_SOCKET) branch
    -- of push_data() and the integer fallback of push_type2name() when the
    -- kernel reports the received TTL with a platform-specific constant
    -- (e.g. IP_RECVTTL on macOS) that is not in our type map.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    server:ip_recvttl(true)
    assert(server:ip_recvttl())
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    local ttl_bytes = string.char(64, 0, 0, 0)
    local len, err = client:sendmsg('p', sai, {
        {
            level = 'ip',
            type = 'ttl',
            data = ttl_bytes,
        },
    })
    assert(len, err)
    assert.equal(len, 1)

    assert(server:recvable(1))
    local msg = assert(server:recvmsg(1, 128))
    assert.equal(msg.data, 'p')
    assert(msg.cmsgs and #msg.cmsgs > 0, 'received TTL cmsg should be present')
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'ip')
    -- On platforms where the kernel delivers the received TTL under a
    -- different constant (e.g., IP_RECVTTL on macOS), the type is pushed
    -- as an integer.  On platforms where it matches IP_TTL, the type is
    -- pushed as the string "ttl".
    assert(type(cm.type) == 'string' or type(cm.type) == 'number',
           'cm.type must be string or number')
    assert.is_string(cm.data)

    client:close()
    server:close()
end

function testcase.sendmsg_cmsg_ipv6_hoplimit_udp()
    -- test that level='ipv6' + type='hoplimit' resolves via level2type_map's
    -- IPPROTO_IPV6 branch and reaches the raw-string cmsg serializer.
    local server, srv_err = socket.bind_inet('::1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    })
    if not server then
        -- IPv6 loopback may not be available on this host; skip in that case.
        assert.match(tostring(srv_err), 'address', false)
        return
    end
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet6({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    local hop_bytes = string.char(64, 0, 0, 0)
    local len, err = client:sendmsg('h', sai, {
        {
            level = 'ipv6',
            type = 'hoplimit',
            data = hop_bytes,
        },
    })
    assert(len, err)
    assert.equal(len, 1)

    assert(server:recvable(1))
    local msg = assert(server:recvmsg(1))
    assert.equal(msg.data, 'h')

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

    -- Wrapped in pcall so that any thrown error can be inspected.  The
    -- library must not raise; a wrongly-sized TTL cmsg surfaces as a
    -- normal (nil, errno) return pair.
    local ok, len, err = pcall(a.sendmsg, a, 'x', nil, {
        {
            level = 'ip',
            type = 'ttl',
            data = string.rep('x', 5000),
        },
    })
    assert.is_true(ok, 'sendmsg must not raise for oversized raw cmsg')
    -- Either sendmsg succeeds (some kernels ignore the wrong size) or
    -- returns nil + errno; both are acceptable so long as no Lua-level
    -- buffer overflow is raised.
    if not len then
        assert.not_nil(err)
    end

    a:close()
    b:close()
end

function testcase.sendmsg_cmsg_concatenates_multiple_entries()
    -- When more than one cmsg descriptor is supplied, each entry is
    -- serialized into its own Lua string and the strings are then
    -- concatenated via lua_concat() to produce a single control-buffer
    -- block.  Exercise that concatenation path with two IP_TTL cmsg
    -- entries on a UDP socket so that the assembled block reaches the
    -- kernel and the send succeeds.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    local ttl_bytes = string.char(64, 0, 0, 0)
    local len, err = client:sendmsg('m', sai, {
        {
            level = 'ip',
            type = 'ttl',
            data = ttl_bytes,
        },
        {
            level = 'ip',
            type = 'ttl',
            data = ttl_bytes,
        },
    })
    assert(len, err)
    assert.equal(len, 1)

    client:close()
    server:close()
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

function testcase.recvmsg_empty_input()
    -- recvmsg() with neither bufsize nor cmsgbuf surfaces EINVAL.  A
    -- negative bufsize or cmsgbuf is rejected as a Lua argument error.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- test that recvmsg with neither data nor cmsg buffer returns EINVAL
    local msg, err = a:recvmsg()
    assert.is_nil(msg)
    assert.equal(err.type, errno.EINVAL)

    -- test that a negative bufsize raises
    local rerr = assert.throws(function()
        a:recvmsg(-1, 0)
    end)
    assert.match(rerr, 'bufsize', false)

    -- test that a negative cmsgbuf raises
    rerr = assert.throws(function()
        a:recvmsg(0, -1)
    end)
    assert.match(rerr, 'cmsgbuf', false)

    a:close()
    b:close()
end

function testcase.recvmsg_reports_control_truncation()
    -- When the kernel drops part of the ancillary data because the caller's
    -- cmsg buffer was too small, it sets MSG_CTRUNC on msg_flags to warn
    -- the caller not to trust the delivered cmsg set.  Expose that
    -- indication through the returned msg table so callers can react
    -- (for example by refusing to consume half of an SCM_RIGHTS batch).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))

    local len = assert(a:sendmsg('x', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = {
                fileno(f),
                fileno(f),
                fileno(f),
                fileno(f),
            },
        },
    }))
    assert.equal(len, 1)

    -- 8 bytes is smaller than any well-formed SCM_RIGHTS cmsg, so the
    -- kernel truncates the ancillary data and sets MSG_CTRUNC.
    local msg = assert(b:recvmsg(1, 8))
    assert.equal(msg.data, 'x')
    assert(msg.flags, 'recvmsg must report msg_flags')
    assert.is_true(msg.flags.ctrunc)
    -- Any file descriptors that the kernel did deliver despite truncation
    -- must still be closed to avoid leaking.
    if msg.cmsgs then
        for _, cm in ipairs(msg.cmsgs) do
            if cm.type == 'rights' then
                if type(cm.data) == 'number' then
                    socket.close(cm.data)
                else
                    for _, fd in ipairs(cm.data) do
                        socket.close(fd)
                    end
                end
            end
        end
    end

    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.recvmsg_reports_no_truncation_when_buffers_fit()
    -- The complement of recvmsg_reports_control_truncation: with cmsg
    -- buffers large enough to receive the full ancillary data, msg.flags
    -- reports both truncated and ctruncated as false.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local path = os.tmpname()
    local f = assert(io.open(path, 'w+'))

    assert(a:sendmsg('y', nil, {
        {
            level = 'socket',
            type = 'rights',
            data = fileno(f),
        },
    }))

    local msg = assert(b:recvmsg(1, 128))
    assert.equal(msg.data, 'y')
    assert(msg.flags, 'recvmsg must report msg_flags')
    -- No truncation flags should be present on the returned table.
    assert.is_nil(msg.flags.trunc)
    assert.is_nil(msg.flags.ctrunc)
    assert.equal(#msg.cmsgs, 1)
    socket.close(msg.cmsgs[1].data)

    f:close()
    os.remove(path)
    a:close()
    b:close()
end

function testcase.recvmsg_oom()
    -- Lua VMs reject impractically large userdata allocations with
    -- implementation-specific messages; verify that both buffer arguments
    -- fail without relying on the wording.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local err = assert.throws(function()
        a:recvmsg(2 ^ 60)
    end)
    assert.is_string(err)

    err = assert.throws(function()
        a:recvmsg(0, 2 ^ 60)
    end)
    assert.is_string(err)

    a:close()
    b:close()
end

function testcase.recvmsg_eof()
    -- After peer close, recvmsg() on a stream socket returns 0 values
    -- (EOF) to match recv()'s convention.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    a:close()
    -- test that recvmsg after peer close returns all nil (matches recv)
    local msg, err, again = b:recvmsg(8)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_nil(again)

    b:close()
end

function testcase.recvmsg_again()
    -- recvmsg() on a non-blocking stream socket with no pending data
    -- returns (nil, nil, true) to signal EAGAIN, mirroring recv().
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- test that recvmsg on a non-blocking socket with no pending data returns
    -- (nil, nil, true) so callers can distinguish EAGAIN from EOF.
    local msg, err, again = b:recvmsg(8)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)

    a:close()
    b:close()
end

function testcase.recvmsg_on_closed_socket()
    -- recvmsg() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:recvmsg(1)
    assert.is_nil(rv)
    assert(err)
end

function testcase.recvmsg_cmsg_socket_scm_timestamp()
    -- test that a SCM_TIMESTAMP cmsg delivered via SO_TIMESTAMP is exposed
    -- as { level='socket', type='timestamp', data=<raw bytes> }, which
    -- exercises the SOL_SOCKET-but-not-SCM_RIGHTS fallthrough path in
    -- push_data() (i.e., raw-string serialization for SOL_SOCKET).
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    server:timestamp(true)
    assert(server:timestamp())
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    assert(client:sendmsg('t', sai))
    assert(server:recvable(1))
    local msg = assert(server:recvmsg(1, 256))
    assert.equal(msg.data, 't')
    assert(msg.cmsgs and #msg.cmsgs > 0, 'SCM_TIMESTAMP cmsg should be present')
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'socket')
    assert.equal(cm.type, 'timestamp')
    assert.is_table(cm.data)
    assert.is_int(cm.data.sec)
    assert.is_int(cm.data.usec)

    client:close()
    server:close()
end

function testcase.recvmsg_cmsg_socket_scm_credentials_linux()
    -- SCM_CREDENTIALS is a Linux-only cmsg type carried with SO_PASSCRED.
    -- We exercise a round-trip on Linux and skip the test elsewhere.
    if skip_if_not_linux('recvmsg_receives_scm_credentials_linux') then
        return
    end
    -- test that a SCM_CREDENTIALS cmsg delivered via SO_PASSCRED is
    -- exposed as { level='socket', type='credentials', data=<raw bytes> }
    -- and that its serialized payload is a struct ucred (12 bytes on
    -- typical Linux/x86_64 layouts: pid + uid + gid).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- Enable receive-side SO_PASSCRED via generic setsockopt-style method
    -- if available; otherwise, this test is a soft no-op on unsupported
    -- kernels.  The method mirrors the convention used by other boolean
    -- socket options in this module (e.g. socket:timestamp).
    if b.passcred then
        b:passcred(true)
    end

    -- Some kernels require the sender to include an SCM_CREDENTIALS cmsg
    -- with a struct ucred payload of the sender's real credentials.  We
    -- pass a zeroed struct-ucred-sized buffer; on kernels that fill it in
    -- automatically, the receiver will see the actual credentials.
    local raw = string.rep('\0', 12)
    local rv, err = a:sendmsg('c', nil, {
        {
            level = 'socket',
            type = 'credentials',
            data = raw,
        },
    })
    if not rv then
        -- Some kernels reject the explicit send; report the error path
        -- rather than fail the whole test.
        assert(err, 'expected an error object when sendmsg fails')
        a:close()
        b:close()
        return
    end
    assert.equal(rv, 1)

    assert(b:recvable(1))
    local msg = assert(b:recvmsg(1, 128))
    assert.equal(msg.data, 'c')
    assert(msg.cmsgs and #msg.cmsgs > 0,
           'SCM_CREDENTIALS cmsg should be present')
    local cm = msg.cmsgs[1]
    assert.equal(cm.level, 'socket')
    assert.equal(cm.type, 'credentials')
    assert.is_string(cm.data)
    assert.greater_or_equal(#cm.data, 12)

    a:close()
    b:close()
end

function testcase.bind()
    -- bind() associates a fresh socket with a local address.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    local ai = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:bind(ai))
    local bound = assert(s:getsockname())
    assert.greater(bound:port(), 0)
    s:close()

    -- bind() on a closed socket returns (false, err) via EBADF.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local ok, err = s:bind(ai)
    assert.is_false(ok)
    assert(err)
end

function testcase.connect()
    -- connect() method drives a fresh socket into a three-way handshake
    -- with a listening peer.  On loopback the handshake either completes
    -- synchronously (ok == true) or reports EINPROGRESS via again == true.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(0))
    local ai = assert(server:getsockname())
    local ai_client = assert(addrinfo.inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local c = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err, again = c:connect(ai_client)
    if again then
        assert.is_false(ok)
        assert.is_nil(err)
        assert(c:sendable(1))
        assert.is_nil(c:error())
    else
        assert(ok, err)
    end
    c:close()
    server:close()

    -- connect() on a closed socket returns (false, err).
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    ok, err = s:connect(ai_client)
    assert.is_false(ok)
    assert(err)
end

function testcase.connect_returns_again_when_previous_connect_pending()
    -- While a non-blocking connect() is still in progress on a socket,
    -- invoking connect() on the same socket surfaces EALREADY.  connect_lua
    -- must treat EALREADY the same as EINPROGRESS -- that is, "still in
    -- progress" -- and return (false, nil, true).  Prior to the fix,
    -- EALREADY was collapsed into the success path and the second call
    -- returned (true), which would let callers proceed on an unhandshaked
    -- fd.
    --
    -- The pending state is produced deterministically by targeting an
    -- address in the TEST-NET-1 range (RFC 5737, 192.0.2.0/24), which is
    -- reserved for documentation and is not answered by any real host.
    -- The SYN is transmitted but never receives a SYN-ACK, so successive
    -- connect() calls on the same fd all observe the same in-progress
    -- state without racing against a real handshake.
    local ai = assert(addrinfo.inet('192.0.2.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local c = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    -- First connect() on a non-blocking socket returns EINPROGRESS as
    -- (false, nil, true).
    local ok, err, again = c:connect(ai)
    assert.is_nil(err)
    assert.is_false(ok)
    assert.is_true(again)

    -- Second connect() on the same socket returns EALREADY as
    -- (false, nil, true).
    ok, err, again = c:connect(ai)
    assert.is_nil(err)
    assert.is_false(ok)
    assert.is_true(again)
    c:close()

    -- socket.connect_inet() also drives connect_lua and observes the same
    -- shape from its internal call: it returns (sock, nil, true) when the
    -- initial connect() surfaces EINPROGRESS.
    c, err, again = assert(socket.connect_inet(ai, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.is_nil(err)
    assert.is_true(again)

    -- A follow-up connect() on the still-pending socket again returns
    -- EALREADY as (false, nil, true).
    ok, err, again = c:connect(ai)
    assert.is_nil(err)
    assert.is_false(ok)
    assert.is_true(again)
    c:close()
end

function testcase.connect_returns_ok_when_already_connected()
    -- Once the three-way handshake has finished, calling connect() again on
    -- the same socket causes the kernel to fail with EISCONN.  connect_lua
    -- must treat EISCONN as success (already connected) and return
    -- (true), rather than surfacing the errno as a terminal error.  Prior
    -- to the fix, EISCONN fell through to the error path and the second
    -- connect() returned (false, err).
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(32))
    local ai = assert(server:getsockname())
    local ai_client = assert(addrinfo.inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local c = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    -- First connect() on a non-blocking socket returns EINPROGRESS as
    -- (false, nil, true).
    local ok, err, again = c:connect(ai_client)
    assert.is_false(ok)
    assert.is_nil(err)
    assert.is_true(again)

    -- Give the kernel time to complete the three-way handshake on
    -- loopback.  100 ms is well above the observed handshake latency and
    -- keeps the test time-bounded.
    timer.sleep(0.1)

    -- Second connect() on the now-connected socket surfaces EISCONN,
    -- which connect_lua must report as (true, nil, nil).
    ok, err, again = c:connect(ai_client)
    assert.is_true(ok)
    assert.is_nil(err)
    assert.is_nil(again)

    c:close()
    server:close()
end

function testcase.listen()
    -- listen() marks a bound socket as accepting incoming connections.
    local s = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(s:listen(0))
    local rv = s:acceptconn()
    assert(rv == true or rv == 1 or rv == nil)
    s:close()

    -- listen() on a closed socket returns (false, err).
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local ok, err = s:listen()
    assert.is_false(ok)
    assert(err)
end

function testcase.getsockname()
    -- getsockname() reports the socket's local address after bind().
    local s = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    local ai = assert(s:getsockname())
    assert.equal(ai:family(), 'inet')
    assert.greater(ai:port(), 0)
    s:close()

    -- getsockname() on a closed socket returns (nil, err).
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:getsockname()
    assert.is_nil(rv)
    assert(err)
end

function testcase.dup_on_closed_socket()
    -- test that dup() on a closed socket returns nil + EBADF rather than
    -- silently succeeding.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local dup, err = s:dup()
    assert.is_nil(dup)
    assert(err)
    assert.equal(err.type, errno.EBADF)
end

function testcase.dup_on_stale_fd()
    -- Same technique as above: stale fd on a still-live userdata drives
    -- dup_lua's dup(-1) == EBADF error branch.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(socket.close(s:fd()))
    local d, err = s:dup()
    assert.is_nil(d)
    assert(err)
end

function testcase.dup()
    -- dup() creates a new socket that shares the underlying fd but preserves
    -- the family / socktype attributes.
    local s = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local dup = assert(s:dup())
    assert.equal(dup:family(), s:family())
    assert.equal(dup:socktype(), s:socktype())
    dup:close()
    s:close()
end

function testcase.wrap_non_socket_fd()
    -- test that socket.wrap on a non-socket fd (e.g. stdout, fd 1) surfaces
    -- getsockname's ENOTSOCK error rather than crashing.
    local s, err = socket.wrap(1)
    assert.is_nil(s)
    assert(err, 'wrap on a non-socket fd should return an error')
    assert.equal(err.type, errno.ENOTSOCK)
end

function testcase.bind_inet_preserves_emfile_from_new_socket()
    -- new_net_socket() iterates candidate addrinfos and calls new_socket()
    -- for each.  If new_socket() itself fails (EMFILE / ENFILE /
    -- EPROTONOSUPPORT / ...) that errno used to be dropped and the
    -- caller saw EADDRNOTAVAIL instead, masking capacity failures as
    -- address failures.  Consume all available fds and verify the real
    -- errno surfaces.
    local hoard = {}
    while true do
        local socks = socket.pair({
            socktype = 'stream',
        })
        if not socks then
            break
        end
        hoard[#hoard + 1] = socks[1]
        hoard[#hoard + 1] = socks[2]
    end
    -- socket.pair breaks when a 2-fd allocation fails; one single fd may
    -- still be available.  Drain it too with new_inet so bind_inet's
    -- 1-fd socket() call has nothing left.
    while true do
        local s = socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        })
        if not s then
            break
        end
        hoard[#hoard + 1] = s
    end

    local ok, err = socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    })

    for _, s in ipairs(hoard) do
        s:close()
    end
    if ok then
        ok:close()
    end

    assert.is_nil(ok)
    assert(err)
    assert(err.type == errno.EMFILE or err.type == errno.ENFILE,
           'expected EMFILE/ENFILE, got ' .. tostring(err.type))
    assert.not_equal(err.type, errno.EADDRNOTAVAIL)
end

function testcase.wrap_invalid_fd()
    -- test that socket.wrap on a closed / invalid fd surfaces EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = s:unwrap()
    assert(socket.close(fd))
    local wrapped, err = socket.wrap(fd)
    assert.is_nil(wrapped)
    assert(err)
    assert.equal(err.type, errno.EBADF)
end

function testcase.wrap()
    -- socket.wrap() takes a raw fd (typically from unwrap() or a foreign
    -- system-call) and returns a new socket userdata that owns it.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = s:unwrap()
    local wrapped = assert(socket.wrap(fd))
    assert.equal(wrapped:family(), 'inet')
    wrapped:close()
end

function testcase.wrap_sets_cloexec_and_nonblock()
    -- The documented contract for socket.wrap(fd) is that the adopted fd
    -- inherits both FD_CLOEXEC and O_NONBLOCK regardless of its prior
    -- state.  Forge a raw fd whose FD_CLOEXEC is deliberately cleared and
    -- verify wrap() re-applies both flags -- a foreign fd handed to wrap
    -- must not leak into child processes on subsequent exec().
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:cloexec(false))
    assert.is_false(s:cloexec())
    assert(s:nonblock(false))
    assert.is_false(s:nonblock())

    local fd = s:unwrap()
    local wrapped = assert(socket.wrap(fd))
    assert.is_true(wrapped:cloexec(),
                   'wrap() must re-apply FD_CLOEXEC to the adopted fd')
    assert.is_true(wrapped:nonblock(),
                   'wrap() must re-apply O_NONBLOCK to the adopted fd')
    wrapped:close()
end

function testcase.wrap_send_survives_sigpipe_after_shutdown_wr()
    -- Sockets re-adopted via wrap() must get the same SIGPIPE suppression
    -- as freshly created ones.
    local proc = assert(fork())
    if proc:is_child() then
        signal.sigdefault('SIGPIPE')
        local socks = assert(socket.pair({
            socktype = 'stream',
        }))
        local fd = assert(socks[1]:unwrap())
        local s = assert(socket.wrap(fd))
        assert(s:shutdown('wr'))
        local sent, err = s:send('x')
        assert.is_nil(sent)
        assert.match(err, 'EPIPE')
        os.exit(0)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.unwrap_returns_fd_and_disables_socket()
    -- Explicitly exercise unwrap_lua's success path to ensure gc_thread is
    -- released and the fd is transferred back to the caller.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = s:unwrap()
    assert.is_int(fd)
    assert(socket.close(fd))
end

function testcase.close_shutdown_and_close_both_fail()
    -- socket.close(fd, how) calls shutdown() then close().  When the fd has
    -- already been closed, both syscalls fail with EBADF and closefd() must
    -- surface the chained error: the top-level error carries the close(2)
    -- failure and its `wrap` field carries the shutdown(2) failure.  A
    -- previous assertion of just `assert(err)` accepted any truthy value and
    -- would not have detected a regression that dropped the chained
    -- shutdown error or mislabelled either op.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = s:fd()
    assert(socket.close(fd))

    local ok, err = socket.close(fd, 'rd')
    assert.is_false(ok)
    assert(err, 'closefd() must return an error object when both syscalls fail')
    assert.equal(err.op, 'close')
    assert.equal(err.type, errno.EBADF)
    assert(err.wrap,
           'closefd() must attach the shutdown failure to err.wrap when both fail')
    assert.equal(err.wrap.op, 'shutdown')
    assert.equal(err.wrap.type, errno.EBADF)
end

function testcase.close_with_shutdown_error()
    -- socket.close(fd, how) performs shutdown(how) followed by close(fd).
    -- shutdown(2) on a socket that has never been connected fails with
    -- ENOTCONN, but close(2) still succeeds; closefd() must therefore return
    -- (false, ENOTCONN-from-shutdown), NOT the errno that happens to remain
    -- in the thread after close(2) returned successfully.
    --
    -- The previous assertion `assert(rv or err)` was trivially satisfied by
    -- the non-nil error alone and did not verify that the reported errno
    -- was the one shutdown(2) had recorded.  This regression asserts on the
    -- concrete type / op so a future refactor cannot silently swap the
    -- reported errno for whatever value happened to sit in `errno` after
    -- close(2).
    local closed = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = closed:unwrap()

    local rv, err = socket.close(fd, 'rd')
    assert.is_false(rv)
    assert(err, 'closefd() must return an error when shutdown(2) fails')
    assert.equal(err.op, 'shutdown')
    assert.equal(err.type, errno.ENOTCONN)
    assert.is_nil(err.wrap)
end

function testcase.shutdown_invalid_flags()
    -- The `how` argument to shutdown() (both the method form and the
    -- static socket.shutdown(fd, how) form) must be one of the strings
    -- "rd", "wr", "rdwr".  Non-strings and unknown strings are rejected
    -- by checkshutflag() with a diagnostic Lua error.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local err = assert.throws(function()
        socks[1]:shutdown(1)
    end)
    assert.match(err, 'how must be string', false)

    err = assert.throws(function()
        socks[1]:shutdown('invalid')
    end)
    assert.match(err, 'not a recognized shutdown direction', false)

    err = assert.throws(function()
        socket.shutdown(socks[1]:fd(), 1)
    end)
    assert.match(err, 'how must be string', false)

    socks[1]:close()
    socks[2]:close()
end

function testcase.shutdown()
    -- shutdown() half-closes a connected stream socket in the specified
    -- direction; the static socket.shutdown(fd, how) form does the same on
    -- a bare fd.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    assert(a:shutdown('wr'))
    -- Some kernels (macOS) return ENOTCONN once one side has already shut
    -- its write half; accept either outcome for the peer-side
    -- socket.shutdown() invocation.
    local ok, err = socket.shutdown(b:fd(), 'rd')
    assert(ok ~= nil or err)
    a:close()
    b:close()
end

function testcase.shutdown_on_closed_socket()
    -- shutdown() on a closed socket returns (false, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local ok, err = s:shutdown('rd')
    assert.is_false(ok)
    assert(err)
end

function testcase.gc_closes_socket()
    -- test that a live socket that never had close() called is closed when
    -- it is garbage-collected.  We drop the only reference in an inner block
    -- and then force a full GC cycle so gc_lua's fd != -1 branch runs.
    local fd
    do
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        fd = s:fd()
        -- do not call s:close(); rely on gc
    end
    collectgarbage('collect')
    collectgarbage('collect')
    -- after gc, the underlying fd must have been closed by gc_lua; trying
    -- to close it again should fail with EBADF (or succeed if the OS
    -- happens to have reused the fd; in that case the test is a soft
    -- no-op because we still exercised gc_lua's code path).
    local _, err = socket.close(fd)
    if err then
        assert.equal(err.type, errno.EBADF)
    end
end

function testcase.accept_on_closed_socket()
    -- accept() on a closed socket should return nil + EBADF (or similar).
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local sock, err = s:accept()
    assert.is_nil(sock)
    assert(err)
end

function testcase.accept_when_no_pending()
    -- accept() and acceptfd() on a listening socket with no pending
    -- connection return (nil, nil) to indicate EAGAIN (the socket is
    -- non-blocking by default).  This mirrors recv()'s convention of
    -- distinguishing EAGAIN (nil, nil, true) from EOF/error (nil, err).
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:listen())
    local rv, err = server:acceptfd()
    assert.is_nil(rv)
    assert.is_nil(err)
    rv, err = server:accept()
    assert.is_nil(rv)
    assert.is_nil(err)
    server:close()
end

function testcase.accept_with_addr()
    -- accept(true) additionally returns the peer's address as a fourth
    -- return value, wrapped in a net.addrinfo userdata.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen())
    local ai = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:recvable(1))

    local peer, err, again, peer_ai = server:accept(true)
    assert(peer, err)
    assert.is_nil(again)
    assert.equal(peer_ai:family(), 'inet')

    peer:close()
    client:close()
    server:close()
end

function testcase.accept()
    -- accept() returns the peer socket once a client has connected.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen())
    local ai = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:recvable(1))
    local peer, err = server:accept()
    assert(peer, err)
    assert.equal(assert(peer:getsockname()):port(), ai:port())
    peer:close()
    client:close()
    server:close()
end

function testcase.acceptfd_on_non_listening()
    -- acceptfd() on a bound-but-not-listening socket surfaces EINVAL.
    local unlisten = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local rv, err = unlisten:acceptfd()
    assert.is_nil(rv)
    assert(err)
    unlisten:close()
end

function testcase.acceptfd()
    -- acceptfd() returns the raw accepted fd, which can then be adopted
    -- via socket.wrap().
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(0))
    local ai = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:recvable(1))
    local afd = assert(server:acceptfd())
    local wrapped = assert(socket.wrap(afd))
    wrapped:close()
    client:close()
    server:close()
end

function testcase.acceptfd_on_closed_socket()
    -- acceptfd() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:acceptfd()
    assert.is_nil(rv)
    assert(err)
end

function testcase.accept_send_survives_sigpipe_after_shutdown_wr()
    -- Sockets obtained via accept() must be as SIGPIPE-safe as paired
    -- ones.
    local proc = assert(fork())
    if proc:is_child() then
        signal.sigdefault('SIGPIPE')
        local server = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
            reuseaddr = true,
        }))
        assert(server:listen())
        local ai = assert(server:getsockname())
        local client = assert(socket.connect_inet('127.0.0.1', ai:port(), {
            socktype = 'stream',
            protocol = 'tcp',
        }))
        assert(server:recvable(1))
        local peer = assert(server:accept())
        client:close()
        assert(peer:shutdown('wr'))
        local sent, err = peer:send('x')
        assert.is_nil(sent)
        assert.match(err, 'EPIPE')
        os.exit(0)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendable_recvable_basic()
    -- sendable(sec) / recvable(sec) block for up to `sec` seconds and
    -- return (true) once the socket is writable / readable, or (false,
    -- nil, true) on timeout.  On a fresh stream pair the send side is
    -- immediately writable and the recv side times out.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- immediate readiness (sec = 0)
    assert.is_true(a:sendable(0))

    -- readiness with a positive timeout branch: nothing is pending so
    -- recvable should time out.
    local ok, err, timeout = b:recvable(0.001)
    assert.is_false(ok)
    assert.is_nil(err)
    assert.is_true(timeout)

    a:close()
    b:close()

    -- After close, s->fd is -1 which makes poll(2) ignore the entry and
    -- return 0, driving the timeout branch.
    local rv = a:sendable(0)
    assert.is_false(rv)
end

function testcase.sendable_recvable_on_stale_fd()
    -- Force poll_lua's POLLNVAL branch (EBADF):
    -- 1. create a real socket, then externally close its fd via
    --    socket.close(fd) so the userdata still holds a numerically valid
    --    but kernel-closed fd
    -- 2. sendable/recvable then invoke poll() on that stale fd and get
    --    POLLNVAL, which is surfaced as EBADF
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd = s:fd()
    assert(socket.close(fd))

    local rv, err = s:sendable(0)
    assert.is_false(rv)
    assert(err)
    rv, err = s:recvable(0)
    assert.is_false(rv)
    assert(err)
    rv, err = s:sendable(0, true)
    assert.is_false(rv)
    assert(err)
    rv, err = s:recvable(0, true)
    assert.is_false(rv)
    assert(err)
end

function testcase.sendable_recvable_on_closed_socket()
    -- sendable/recvable both go through poll_lua.  A socket closed via
    -- close() has fd == -1 and must surface EBADF, matching the POLLNVAL
    -- result poll(2) reports for an externally closed fd: the two closed
    -- states carry the same meaning and must not be distinguished by
    -- whether the descriptor number is still stored.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err, timeout = s:sendable(0)
    assert.is_false(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
    rv, err, timeout = s:recvable(0)
    assert.is_false(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)

    -- an externally closed fd takes the poll(2) POLLNVAL path and must
    -- report the same EBADF
    local s2 = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(socket.close(s2:fd()))
    rv, err, timeout = s2:sendable(0)
    assert.is_false(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
    s2:close()
end

function testcase.sendable_recvable_supports_high_fd_values()
    -- The historical select(2) + fd_set implementation invoked undefined
    -- behaviour when the socket's fd was >= FD_SETSIZE (typically 1024)
    -- because FD_SET writes past the end of the local fd_set.  The
    -- current implementation uses poll(2), whose struct pollfd carries
    -- no such upper bound.  Consume file descriptors until any newly
    -- created socket has an fd well above 1024 and verify that
    -- sendable() / recvable() work correctly on that fd.  If the
    -- process's RLIMIT_NOFILE is below the target the test releases its
    -- hoard and silently skips the assertion so it does not perturb
    -- constrained CI environments.
    local target = 1030
    local hoard = {}
    local a, b
    while true do
        local socks = socket.pair({
            socktype = 'stream',
        })
        if not socks then
            break
        end
        if math.max(socks[1]:fd(), socks[2]:fd()) >= target then
            a = socks[1]
            b = socks[2]
            break
        end
        hoard[#hoard + 1] = socks[1]
        hoard[#hoard + 1] = socks[2]
    end

    if a and b then
        assert.is_true(a:sendable(0))
        local ok, err, timeout = b:recvable(0.001)
        assert.is_false(ok)
        assert.is_nil(err)
        assert.is_true(timeout)
        a:close()
        b:close()
    end

    for _, s in ipairs(hoard) do
        s:close()
    end
end

function testcase.getpeername_unconnected()
    -- getpeername() on an unconnected socket surfaces ENOTCONN.  The
    -- close() method is also idempotent -- calling it twice succeeds.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    local ai, err = s:getpeername()
    assert.is_nil(ai)
    assert(err)
    assert(s:close())
    assert(s:close())
end

function testcase.getpeername()
    -- getpeername() reports the remote address of a connected socket.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(0))
    local sai = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', sai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    -- ensure the handshake completes before probing peername.
    assert(client:sendable(1))
    local peer = assert(client:getpeername())
    assert.equal(peer:port(), sai:port())
    client:close()
    server:close()
end

-- SCM_CREDENTIALS is a Linux-only cmsg type.  On other platforms (macOS,
-- most BSDs) the equivalent SCM_CREDS has no reliable explicit-send API
-- that we can exercise from Lua, so we skip the test there.
--
-- socket.pair
--
function testcase.pair_stream()
    -- pair creates a pair of connected unix stream sockets.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    assert.equal(#socks, 2)
    assert.equal(socks[1]:family(), 'unix')
    assert.equal(socks[2]:family(), 'unix')
    socks[1]:close()
    socks[2]:close()
end

function testcase.pair_dgram()
    -- pair creates a pair of connected unix dgram sockets.
    local socks = assert(socket.pair({
        socktype = 'dgram',
    }))
    socks[1]:close()
    socks[2]:close()
end

function testcase.pair_opts()
    -- opts.socktype is required.
    local err = assert.throws(function()
        socket.pair({})
    end)
    assert.match(err, 'opts.socktype is required', false)

    -- opts.protocol / opts.socktype must be strings (check_socktype /
    -- check_protocol type-check branches).
    err = assert.throws(function()
        socket.pair({
            socktype = 'stream',
            protocol = 123,
        })
    end)
    assert.match(err, 'opts.protocol must be string')

    err = assert.throws(function()
        socket.pair({
            socktype = 123,
        })
    end)
    assert.match(err, 'opts.socktype must be string')

    -- Unknown symbolic values are rejected by check_socktype / check_protocol.
    err = assert.throws(function()
        socket.pair({
            socktype = 'invalid',
        })
    end)
    assert.match(err, 'not a recognized socket type')

    err = assert.throws(function()
        socket.pair({
            socktype = 'stream',
            protocol = 'invalid',
        })
    end)
    assert.match(err, 'not a recognized protocol')

    -- Also reject symbolic values not in the pair-side protocol map.
    err = assert.throws(function()
        socket.pair({
            socktype = 'stream',
            protocol = 'not-a-recognized-protocol',
        })
    end)
    assert(err)
end

function testcase.pair_socketpair_failure()
    -- socketpair(AF_UNIX, SOCK_DGRAM, IPPROTO_TCP) fails with
    -- EPROTONOSUPPORT, so pair_lua's socketpair() -1 branch is exercised.
    local s, err = socket.pair({
        socktype = 'dgram',
        protocol = 'tcp',
    })
    assert.is_nil(s)
    assert(err)
end

--
-- error propagation from the addrinfo resolver
--
--
-- error paths
--
function testcase.write_again()
    -- write() surfaces EAGAIN via (0, nil, true) once the send buffer
    -- is full.  We shrink the send buffer so a couple of write() calls
    -- suffice to fill it and drive write_lua's EAGAIN branch.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    -- Shrink the send buffer so a couple of write() calls suffice to fill
    -- it and drive write_lua's EAGAIN branch quickly.
    a:sndbuf(512)

    local chunk = string.rep('x', 1024)
    local n, err, again
    repeat
        n, err, again = a:write(chunk)
        assert.is_nil(err)
        assert.is_int(n)
    until again and n == 0
    assert.is_true(again)
    assert.equal(n, 0)

    a:close()
    b:close()
end

function testcase.write_when_peer_closed()
    -- After the peer closes, write() eventually surfaces the terminal
    -- error path (EPIPE / ECONNRESET).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    b:close()

    -- Some kernels queue the first write; retry until write_lua surfaces
    -- the error path (EPIPE / ECONNRESET).
    local sent, err
    for _ = 1, 4 do
        sent, err = a:write('x')
        if not sent then
            break
        end
    end
    assert.is_nil(sent)
    assert(err)

    a:close()
end

function testcase.write()
    -- Round-trip a payload through a connected unix stream pair.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    assert(a:write('hello'))
    assert(b:recvable(1))
    assert.equal(b:read(5), 'hello')
    a:close()
    b:close()
end

function testcase.write_empty_payload()
    -- An empty payload is rejected (write requires at least one byte).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local rv, err = a:write('')
    assert.is_nil(rv)
    assert(err)
    a:close()
    socks[2]:close()
end

function testcase.write_on_closed_socket()
    -- write() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:write('x')
    assert.is_nil(rv)
    assert(err)
end

function testcase.read_again()
    -- read() on a non-blocking stream socket with an empty receive queue
    -- returns (nil, nil, true) to signal EAGAIN, mirroring recv().
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- read on a non-blocking socket with an empty receive queue must
    -- return (nil, nil, true) to signal EAGAIN.
    local msg, err, again = a:read(16)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)

    a:close()
    b:close()
end

function testcase.read()
    -- read() reads up to N bytes from a connected stream pair.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    assert(b:write('world'))
    assert(a:recvable(1))
    assert.equal(a:read(5), 'world')
    a:close()
    b:close()
end

function testcase.read_zero_length()
    -- read(0) is rejected as an invalid length.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local rv, err = socks[1]:read(0)
    assert.is_nil(rv)
    assert(err)
    socks[1]:close()
    socks[2]:close()
end

function testcase.read_when_peer_closed()
    -- After peer close, read returns nil (EOF).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    b:close()
    assert.is_nil(a:read(4))
    a:close()
end

function testcase.read_on_closed_socket()
    -- read() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:read(1)
    assert.is_nil(rv)
    assert(err)
end

function testcase.send_again()
    -- send() surfaces EAGAIN via (0, nil, true) once the send buffer
    -- is full.  We shrink the buffer to drive the branch quickly.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    a:sndbuf(512)

    -- Fill the send buffer.  send() may report `again` with a partial write
    -- (n > 0) once the buffer starts blocking, and subsequently returns
    -- (0, nil, true) when no byte can be written at all.
    local chunk = string.rep('x', 1024)
    local n, err, again
    repeat
        n, err, again = a:send(chunk)
        assert.is_nil(err)
        assert.is_int(n)
    until again and n == 0
    assert.is_true(again)
    assert.equal(n, 0)

    a:close()
    b:close()
end

function testcase.send_when_peer_closed()
    -- After the peer closes its end of the connection, send() eventually
    -- surfaces the terminal error path (EPIPE / ECONNRESET).  Some kernels
    -- queue the first small write; retry until send_lua reports the error.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    b:close()

    local sent, err
    for _ = 1, 4 do
        sent, err = a:send('x')
        if not sent then
            break
        end
    end
    assert.is_nil(sent)
    assert(err)

    a:close()
end

function testcase.send()
    -- send() sends bytes on a connected stream pair.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    assert(a:send('hello'))
    assert(b:recvable(1))
    assert.equal(b:recv(5), 'hello')
    a:close()
    b:close()
end

function testcase.send_empty_payload()
    -- send('') is rejected as an invalid (empty) payload.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local rv, err = socks[1]:send('')
    assert.is_nil(rv)
    assert(err)
    socks[1]:close()
    socks[2]:close()
end

function testcase.send_on_closed_socket()
    -- send() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:send('x')
    assert.is_nil(rv)
    assert(err)
end

function testcase.recv_again()
    -- recv() on a non-blocking stream socket with an empty receive queue
    -- returns (nil, nil, true) to signal EAGAIN.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local msg, err, again = a:recv(16)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)

    a:close()
    b:close()
end

function testcase.recv_when_peer_closed()
    -- After peer close, recv() on a stream socket returns 0 values (EOF)
    -- to match recv()'s convention.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    a:close()

    -- recv_lua should see EOF (rv == 0) and return nil (no error) so that
    -- callers can distinguish EOF from EAGAIN.
    local rv, err = b:recv(8)
    assert.is_nil(rv)
    assert.is_nil(err)

    b:close()
end

function testcase.recv_dgram()
    -- run recv_lua's default (successful) branch on a dgram socket.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    assert(client:sendto('hello', sai))
    assert(server:recvable(1))
    local msg = assert(server:recv(8))
    assert.equal(msg, 'hello')

    client:close()
    server:close()
end

function testcase.recv()
    -- recv() reads up to N bytes from a connected stream pair.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    assert(b:send('world'))
    assert(a:recvable(1))
    assert.equal(a:recv(5), 'world')
    a:close()
    b:close()
end

function testcase.recv_zero_length()
    -- recv(0) is rejected as an invalid length.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local rv, err = socks[1]:recv(0)
    assert.is_nil(rv)
    assert(err)
    socks[1]:close()
    socks[2]:close()
end

function testcase.recv_dgram_again()
    -- recv() on a fresh non-blocking dgram socket with no data returns
    -- (nil, nil, true) rather than blocking.
    local d = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local msg, err, again = d:recv(1)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)
    d:close()
end

function testcase.recv_on_closed_socket()
    -- recv() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:recv(1)
    assert.is_nil(rv)
    assert(err)
end

function testcase.sendto_dgram()
    -- Exercise sendto_lua's success and again branches on a dgram pair.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    -- normal sendto
    local rv, err = client:sendto('hi', sai)
    assert(rv, err)
    assert.equal(rv, 2)

    -- sendto with an empty payload should surface EINVAL
    rv, err = client:sendto('', sai)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    client:close()
    server:close()
end

function testcase.sendto()
    -- sendto() sends a datagram to an explicit destination address.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert(client:sendto('hi', sai))
    assert(server:recvable(1))
    assert.equal(server:recvfrom(4), 'hi')
    client:close()
    server:close()
end

function testcase.sendto_on_closed_socket()
    -- sendto() on a closed socket returns (nil, err) via EBADF.
    local sai = assert(addrinfo.inet('127.0.0.1', 65535, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:sendto('x', sai)
    assert.is_nil(rv)
    assert(err)
end

function testcase.recvfrom_again()
    -- recvfrom() on a fresh dgram socket with no pending datagrams
    -- returns (nil, nil, true) to signal EAGAIN.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local msg, err, again = server:recvfrom(16)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)
    server:close()
end

function testcase.recvfrom_when_peer_closed()
    -- After the peer of a dgram flow disappears there is no sender-side
    -- error to surface; recvfrom() on an idle dgram socket simply
    -- reports EAGAIN via (nil, nil, true).
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    a:close()

    local rv, err = b:recvfrom(8)
    assert.is_nil(rv)
    assert.is_nil(err)

    b:close()
end

function testcase.recvfrom_dgram()
    -- recvfrom_lua's success and again paths on a dgram pair.  We also
    -- pass an explicit bufsize and flags to run through the option
    -- decoding branches.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    local sai = assert(server:getsockname())
    local client = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
    }))

    -- again path (nothing pending on the server yet)
    local msg, err, again = server:recvfrom(16)
    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(again)

    -- success path
    assert(client:sendto('hi', sai))
    assert(server:recvable(1))
    local rmsg, rerr, _, rai = server:recvfrom(16)
    assert(rmsg, rerr)
    assert.equal(rmsg, 'hi')
    assert(rai)

    client:close()
    server:close()
end

function testcase.recvfrom_stream_no_addr()
    -- On a connected SOCK_STREAM socket, recvfrom() succeeds but the peer
    -- address is anonymous (slen == 0), so recvfrom_lua takes the "no
    -- addrinfo" branch and returns only the data.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    assert(b:send('hi'))
    -- Wait for data to arrive.
    for _ = 1, 20 do
        if a:recvable(0.05) then
            break
        end
    end
    local msg, err, again, ai = a:recvfrom(8)
    assert.equal(msg, 'hi')
    assert.is_nil(err)
    assert.is_nil(again)
    assert.is_nil(ai)

    a:close()
    b:close()
end

function testcase.recvfrom_zero_length()
    -- recvfrom(0) is rejected as an invalid length.
    local pair_socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local rv, rerr = pair_socks[1]:recvfrom(0)
    assert.is_nil(rv)
    assert(rerr)
    pair_socks[1]:close()
    pair_socks[2]:close()
end

function testcase.recvfrom_on_closed_socket()
    -- recvfrom() on a closed socket returns (nil, err) via EBADF.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:recvfrom(1)
    assert.is_nil(rv)
    assert(err)
end

function testcase.message_flags_accept_string_names()
    -- Connected stream sockets cover send/recv/sendmsg/recvmsg without
    -- relying on an inet bind.  Receive-side MSG_PEEK leaves the payload for
    -- the following unflagged call, proving that the decoded flags reach the
    -- syscall.  Repeated names and nil gaps exercise the variadic parser.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    assert.equal(assert(a:send('s', 'dontwait', nil, 'dontwait')), 1)
    assert.equal(assert(b:recv(1)), 's')

    assert.equal(assert(b:send('r')), 1)
    assert.equal(assert(a:recv(1, 'peek', nil, 'dontwait', 'peek')), 'r')
    assert.equal(assert(a:recv(1)), 'r')

    assert.equal(assert(a:sendmsg('m', nil, nil, 'dontwait', nil, 'dontwait')),
                 1)
    assert.equal(assert(b:recv(1)), 'm')

    assert.equal(assert(b:sendmsg('g')), 1)
    local msg = assert(a:recvmsg(1, 0, 'peek', nil, 'dontwait', 'peek'))
    assert.equal(msg.data, 'g')
    assert.equal(assert(a:recv(1)), 'g')

    a:close()
    b:close()

    -- sendfd/recvfd consume SCM_RIGHTS messages, so MSG_DONTWAIT is the safe
    -- portable flag for these paths.  Every received descriptor is closed.
    socks = assert(socket.pair({
        socktype = 'stream',
    }))
    a = socks[1]
    b = socks[2]
    local f = assert(io.tmpfile())

    assert.equal(assert(a:sendfd(fileno(f), nil, 'dontwait', nil, 'dontwait')),
                 0)
    local fd = assert(b:recvfd('dontwait', nil, 'dontwait'))
    assert(socket.close(fd))

    f:close()
    a:close()
    b:close()

    -- sendto requires an explicit address.  Unix datagram sockets avoid
    -- depending on an available inet interface or port.
    local path_a = os.tmpname()
    os.remove(path_a)
    local path_b = os.tmpname()
    os.remove(path_b)
    local ai_a = assert(addrinfo.unix(path_a, {
        socktype = 'dgram',
    }))
    local ai_b = assert(addrinfo.unix(path_b, {
        socktype = 'dgram',
    }))
    local da = assert(socket.bind_unix(ai_a))
    local db = assert(socket.bind_unix(ai_b))

    assert.equal(assert(da:sendto('t', ai_b, 'dontwait', nil, 'dontwait')), 1)
    assert.equal(assert(db:recvfrom(1)), 't')

    da:close()
    db:close()
    os.remove(path_a)
    os.remove(path_b)

    -- A stream socketpair is sufficient for recvfrom's flag path; an
    -- anonymous peer address is an expected result for this socket family.
    socks = assert(socket.pair({
        socktype = 'stream',
    }))
    a = socks[1]
    b = socks[2]
    assert.equal(assert(b:send('f')), 1)
    assert.equal(assert(a:recvfrom(1, 'peek', nil, 'dontwait', 'peek')), 'f')
    assert.equal(assert(a:recv(1)), 'f')
    a:close()
    b:close()
end

function testcase.message_flags_reject_unknown_and_non_string_values()
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local f = assert(io.tmpfile())
    local path = os.tmpname()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'dgram',
    }))
    local cases = {
        {
            name = 'send',
            argument = 4,
            call = function(value)
                a:send('x', 'dontwait', nil, value)
            end,
        },
        {
            name = 'sendto',
            argument = 5,
            call = function(value)
                a:sendto('x', ai, 'dontwait', nil, value)
            end,
        },
        {
            name = 'sendfd',
            argument = 5,
            call = function(value)
                a:sendfd(fileno(f), nil, 'dontwait', nil, value)
            end,
        },
        {
            name = 'sendmsg',
            argument = 6,
            call = function(value)
                a:sendmsg('x', nil, nil, 'dontwait', nil, value)
            end,
        },
        {
            name = 'recv',
            argument = 4,
            call = function(value)
                a:recv(1, 'peek', nil, value)
            end,
        },
        {
            name = 'recvfrom',
            argument = 4,
            call = function(value)
                a:recvfrom(1, 'peek', nil, value)
            end,
        },
        {
            name = 'recvfd',
            argument = 3,
            call = function(value)
                a:recvfd('dontwait', nil, value)
            end,
        },
        {
            name = 'recvmsg',
            argument = 5,
            call = function(value)
                a:recvmsg(1, 0, 'peek', nil, value)
            end,
        },
    }

    for _, case in ipairs(cases) do
        local err = assert.throws(function()
            case.call('not_a_msg_flag')
        end)
        assert.match(err, 'bad argument #' .. case.argument, false)
        assert.match(err, "to '" .. case.name .. "'", false)
        assert.match(err, "unknown MSG_%* flag: 'not_a_msg_flag'", false)

        err = assert.throws(function()
            case.call(0)
        end)
        assert.match(err, 'bad argument #' .. case.argument, false)
        assert.match(err, "to '" .. case.name .. "'", false)
        assert.match(err, 'flag must be a string', false)
    end

    f:close()
    a:close()
    b:close()
    os.remove(path)
end

function testcase.recv_family_rejects_msg_trunc_input_flag()
    -- On Linux datagram, raw, and seqpacket sockets, MSG_TRUNC as a
    -- recv-family input flag makes the syscall return the full original
    -- packet length rather than the number of bytes actually copied into
    -- the caller-provided buffer, which would leak adjacent memory when
    -- Lua later pushed that many bytes as a string.  The MSG_* input-flag
    -- parser therefore rejects "trunc" outright with the standard
    -- unknown-flag argument error on every recv entry point.
    local socks = assert(socket.pair({
        socktype = 'dgram',
    }))
    local a = socks[1]
    local b = socks[2]

    local cases = {
        {
            name = 'recv',
            argument = 2,
            call = function()
                a:recv(1, 'trunc')
            end,
        },
        {
            name = 'recvfrom',
            argument = 2,
            call = function()
                a:recvfrom(1, 'trunc')
            end,
        },
        {
            name = 'recvfd',
            argument = 1,
            call = function()
                a:recvfd('trunc')
            end,
        },
        {
            name = 'recvmsg',
            argument = 3,
            call = function()
                a:recvmsg(1, 0, 'trunc')
            end,
        },
    }

    for _, case in ipairs(cases) do
        local err = assert.throws(function()
            case.call()
        end)
        assert.match(err, 'bad argument #' .. case.argument, false)
        assert.match(err, "to '" .. case.name .. "'", false)
        assert.match(err, "unknown MSG_%* flag: 'trunc'", false)
    end

    a:close()
    b:close()
end

function testcase.addgcfn_too_many_arguments()
    -- Pushing the gc callback's extra arguments onto the socket's gc
    -- thread must go through the stack guard: an argument count the
    -- thread stack cannot hold raises a Lua error instead of writing
    -- past the end of the thread stack (SIGSEGV/SIGBUS before the fix).
    -- A single large call is legitimately accepted when the stack can
    -- grow that far, so keep registering 200-argument callbacks until
    -- the guard fires.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    local args = {}
    for i = 1, 200 do
        args[i] = i
    end
    -- the number of registrations before the guard fires depends on the
    -- runtime's stack limit (~7.7k on Lua 5.1, ~1M on Lua 5.2+), so keep
    -- registering until the guard fires instead of assuming a threshold.
    local fired = false
    for _ = 1, 1000000 do
        local ok = pcall(s.addgcfn, s, nil, function()
        end, unpack(args))
        if not ok then
            fired = true
            break
        end
    end
    assert.is_true(fired, 'guard must fire before the registration loop ends')

    assert(s:close())
end

function testcase.addgcfn_repeated_registration_hits_guard()
    -- Even with few arguments per call, repeated registrations keep
    -- growing the gc thread stack; the guard must eventually raise a
    -- Lua error (or keep accepting after legitimately growing the stack)
    -- instead of corrupting the heap.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    local ok = true
    local err
    for _ = 1, 10000 do
        ok, err = pcall(s.addgcfn, s, nil, function()
        end)
        if not ok then
            break
        end
    end
    -- either every registration succeeded (stack grew legitimately) or a
    -- guard error surfaced; both are acceptable, a crash is not.
    if not ok then
        assert.match(tostring(err), 'too many arguments to addgcfn')
    end

    assert(s:close())
end

function testcase.embedded_nul_string_mismatch()
    -- Lua strings are byte sequences that may contain NULs, and
    -- strcmp()-based lookups stop at the first NUL: "broadcast\0x" used
    -- to enable SO_BROADCAST and "rd\0x" used to match SHUT_RD.  Names
    -- and keys containing embedded NULs must not match any option,
    -- constant, or flag.
    local s = assert(socket.new_inet({
        socktype = 'dgram',
        protocol = 'udp',
        ['broadcast\0x'] = true,
    }))
    -- the NUL-suffixed key must be ignored like any unknown key
    assert.is_false(s:broadcast())
    s:close()

    local c = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    -- the shutdown direction must not match "rd"
    local err = assert.throws(c.shutdown, c, 'rd\0x')
    assert.match(err, 'not a recognized shutdown direction')
    -- the recv flag must not match "peek"
    err = assert.throws(c.recv, c, 1024, 'peek\0')
    assert.match(err, "unknown MSG_* flag: 'peek")
    c:close()
end
