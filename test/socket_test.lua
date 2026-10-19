local fileno = require('io.fileno')
local testcase = require('testcase')
local fork = require('testcase.fork')
local signal = require('testcase.signal')
local rlimit = require('testcase.rlimit')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')

local RLIMIT_NOFILE

local function revert_rlimit_nofile()
    if RLIMIT_NOFILE then
        assert(rlimit('nofile', RLIMIT_NOFILE.cur, RLIMIT_NOFILE.max))
        RLIMIT_NOFILE = nil
    end
end

local function stash_rlimit_nofile()
    revert_rlimit_nofile()
    RLIMIT_NOFILE = assert(rlimit('nofile'))
end

local TMPPATHS = {}

--- Tracked tmpname(): the path is removed by after_each even when a
--- test fails midway, so no unix socket or temp file is left behind.
--- @return string path
local function tmpname()
    local path = os.tmpname()
    TMPPATHS[#TMPPATHS + 1] = path
    return path
end

function testcase.after_each()
    for i = #TMPPATHS, 1, -1 do
        os.remove(TMPPATHS[i])
        TMPPATHS[i] = nil
    end
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
    local path = tmpname()
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
    local path = tmpname()
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

function testcase.int_option_range_guards()
    -- listen, linger and the integer sockopts narrow their lua_Integer
    -- argument to int; out-of-range values used to wrap silently
    -- (listen(2^32+5) became backlog 5) and must raise instead.
    -- Negative linger keeps its documented meaning: disable SO_LINGER.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    -- listen backlog: non-negative int, INT_MAX accepted
    assert(s:listen(0))
    assert(s:listen(2147483647))
    assert.throws(function()
        s:listen(-1)
    end)
    assert.throws(function()
        s:listen(2147483648)
    end)

    -- linger: int range, negatives disable, INT_MIN/INT_MAX accepted
    assert(s:linger(2147483647))
    assert(s:linger(-2147483648))
    assert.throws(function()
        s:linger(2147483649)
    end)
    assert.throws(function()
        s:linger(-2147483649)
    end)

    -- runtime sockopt setter
    assert(s:rcvbuf(2147483647))
    assert.throws(function()
        s:rcvbuf(2147483648)
    end)
    assert.throws(function()
        s:rcvbuf(-2147483649)
    end)

    -- constructor opts table
    assert.throws(function()
        socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            rcvbuf = 2147483648,
        })
    end)
    assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
        rcvbuf = 2147483647,
    }):close())

    s:close()
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
    local _, cerr = c:connect(ai)
    assert.is_nil(cerr)
    assert(c:sendable(1.0))
    local err_obj = c:error()
    assert.not_nil(err_obj)
    c:close()
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
    local reached = false
    -- cap the loop: far more data than any send buffer holds; reaching
    -- the cap means EAGAIN never surfaced
    for _ = 1, 4096 do
        len, err, again, syscalled = a:sendmsg('x')
        assert.is_nil(err)
        if again then
            assert.is_nil(syscalled,
                          'interrupted call must not report syscalled')
        else
            assert.is_true(syscalled, 'completed call must report syscalled')
        end
        if again and len == 0 then
            reached = true
            break
        end
    end
    assert.is_true(reached, 'EAGAIN was never reached')
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
    local reached = false
    -- cap the loop: far more data than any send buffer holds; reaching
    -- the cap means EAGAIN never surfaced
    for _ = 1, 4096 do
        n, err, again = a:sendmsg(chunk)
        assert.is_nil(err)
        assert.is_int(n)
        if again and n == 0 then
            reached = true
            break
        end
    end
    assert.is_true(reached, 'EAGAIN was never reached')
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

function testcase.recvmsg_rejects_cmsgbuf_beyond_socklen_t()
    -- msg_controllen is a 32-bit socklen_t even on LP64; a cmsgbuf larger
    -- than that would wrap after the cast (2^32 becomes 0) and silently
    -- receive no cmsgs.  The guard must fire before any allocation.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    -- integer literals: 2^32 as float arithmetic is rejected by
    -- lua_isinteger on Lua 5.3+ before the guard under test runs
    for _, size in ipairs({
        4294967296, -- 2^32
        4294967396, -- 2^32 + 100
        4611686018427387904, -- 2^62
    }) do
        local err = assert.throws(function()
            a:recvmsg(1, size)
        end)
        assert.match(err, 'cmsgbuf', false)
    end

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
    -- (false, nil, true).  On CI runners whose egress is blocked the SYN
    -- cannot even leave the host and connect(2) fails synchronously with
    -- ENETUNREACH or EACCES; accept those and skip the in-progress
    -- assertions, which need the SYN to be on the wire.
    local ok, err, again = c:connect(ai)
    assert.is_false(ok)
    if err then
        assert.not_nil(error_is(err, errno.ENETUNREACH) or
                           error_is(err, errno.EACCES),
                       'unexpected terminal connect error: ' .. tostring(err))
        c:close()
        return
    end
    assert.is_nil(err)
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

    -- Wait for the kernel to complete the three-way handshake on
    -- loopback: poll writability instead of sleeping a fixed interval,
    -- so a slow runner cannot observe a still-pending connect.
    assert(c:sendable(1), 'the loopback handshake did not complete')

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

function testcase.bind_inet_preserves_emfile_from_new_socket()
    -- new_net_socket() iterates candidate addrinfos and calls new_socket()
    -- for each.  If new_socket() itself fails (EMFILE / ENFILE /
    -- EPROTONOSUPPORT / ...) that errno used to be dropped and the
    -- caller saw EADDRNOTAVAIL instead, masking capacity failures as
    -- address failures.  Lower the soft fd limit to the next free fd
    -- number so the following socket() fails with EMFILE; the probe
    -- descriptor stays valid and nothing is hoarded.
    stash_rlimit_nofile()
    local probe = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(rlimit('nofile', probe:fd()))

    local ok, err = socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    })

    probe:close()
    revert_rlimit_nofile()

    assert.is_nil(ok)
    assert(err)
    assert(err.type == errno.EMFILE or err.type == errno.ENFILE,
           'expected EMFILE/ENFILE, got ' .. tostring(err.type))
    assert.not_equal(err.type, errno.EADDRNOTAVAIL)
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

function testcase.acceptfd_with_addr()
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:listen())
    local addr = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', addr:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(server:recvable(1))

    local fd, err, again, peer_addr = server:acceptfd(true)
    assert.is_number(fd)
    assert.is_nil(err)
    assert.is_nil(again)
    local peer = assert(socket.wrap(fd))
    local client_addr = assert(client:getsockname())
    assert.equal(peer_addr:family(), 'inet')
    assert.equal(peer_addr:addr(), client_addr:addr())
    assert.equal(peer_addr:port(), client_addr:port())
    assert(client:send('hello'))
    assert(peer:recvable(1))
    assert.equal(peer:recv(5), 'hello')

    peer:close()
    client:close()
    fd, err, again = server:acceptfd(true)
    assert.is_nil(fd)
    assert.is_nil(err)
    assert.is_true(again)
    collectgarbage('collect')
    assert(server:getsockname())
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
    local reached = false
    -- cap the loop: far more data than any send buffer holds; reaching
    -- the cap means EAGAIN never surfaced
    for _ = 1, 4096 do
        n, err, again = a:write(chunk)
        assert.is_nil(err)
        assert.is_int(n)
        if again and n == 0 then
            reached = true
            break
        end
    end
    assert.is_true(reached, 'EAGAIN was never reached')
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
    local reached = false
    -- cap the loop: far more data than any send buffer holds; reaching
    -- the cap means EAGAIN never surfaced
    for _ = 1, 4096 do
        n, err, again = a:send(chunk)
        assert.is_nil(err)
        assert.is_int(n)
        if again and n == 0 then
            reached = true
            break
        end
    end
    assert.is_true(reached, 'EAGAIN was never reached')
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
    local fd = assert(assert(b:recvfd('dontwait', nil, 'dontwait')):get())
    assert(socket.close(fd))

    f:close()
    a:close()
    b:close()

    -- sendto requires an explicit address.  Unix datagram sockets avoid
    -- depending on an available inet interface or port.
    local path_a = tmpname()
    os.remove(path_a)
    local path_b = tmpname()
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
    local path = tmpname()
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

function testcase.recv_unknown_message_flag_preserves_64_bytes()
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local s = socks[1]
    local flag = string.rep('x', 64)
    local err = assert.throws(s.recv, s, 1, flag)
    assert.match(err, "unknown MSG_* flag: '" .. flag .. "'")
    assert.not_match(err, '...')
    s:close()
    socks[2]:close()
end

function testcase.recv_unknown_message_flag_truncates_after_64_bytes()
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local s = socks[1]
    local prefix = string.rep('x', 64)
    local err = assert.throws(s.recv, s, 1, prefix .. 'y')
    assert.match(err, "unknown MSG_* flag: '" .. prefix .. "'...")
    assert.not_match(err, prefix .. 'y')
    s:close()
    socks[2]:close()
end

function testcase.recv_unknown_message_flag_bounds_large_input_diagnostic()
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local s = socks[1]
    local prefix = string.rep('x', 64)
    local flag = prefix .. string.rep('y', 1024 * 1024)
    local err = assert.throws(s.recv, s, 1, flag)
    assert.match(err, "unknown MSG_* flag: '" .. prefix .. "'...")
    assert.not_match(err, string.rep('y', 65))
    assert.less(#err, 256)
    s:close()
    socks[2]:close()
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

function testcase.rejects_output_only_msg_flags()
    -- MSG_CTRUNC, MSG_HAVEMORE and MSG_RCVMORE are kernel-set output
    -- flags (the msg_flags field that recvmsg(2) fills in), never valid
    -- input flags; accepting them let typos pass silently, so every
    -- flags-accepting entry point must reject them like any unknown
    -- flag name.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local f = assert(io.tmpfile())
    local path = tmpname()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'dgram',
    }))

    local cases = {
        {
            name = 'send',
            argument = 2,
            call = function(flag)
                a:send('x', flag)
            end,
        },
        {
            name = 'sendto',
            argument = 3,
            call = function(flag)
                a:sendto('x', ai, flag)
            end,
        },
        {
            name = 'sendfd',
            argument = 3,
            call = function(flag)
                a:sendfd(fileno(f), nil, flag)
            end,
        },
        {
            name = 'sendmsg',
            argument = 4,
            call = function(flag)
                a:sendmsg('x', nil, nil, flag)
            end,
        },
        {
            name = 'recv',
            argument = 2,
            call = function(flag)
                a:recv(1, flag)
            end,
        },
        {
            name = 'recvfrom',
            argument = 2,
            call = function(flag)
                a:recvfrom(1, flag)
            end,
        },
        {
            name = 'recvfd',
            argument = 1,
            call = function(flag)
                a:recvfd(flag)
            end,
        },
        {
            name = 'recvmsg',
            argument = 3,
            call = function(flag)
                a:recvmsg(1, 0, flag)
            end,
        },
    }

    for _, case in ipairs(cases) do
        for _, flag in ipairs({
            'ctrunc',
            'havemore',
            'rcvmore',
        }) do
            local err = assert.throws(function()
                case.call(flag)
            end)
            assert.match(err, 'bad argument #' .. case.argument, false)
            assert.match(err, "to '" .. case.name .. "'", false)
            assert.match(err, "unknown MSG_%* flag: '" .. flag .. "'", false)
        end
    end

    f:close()
    a:close()
    b:close()
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
