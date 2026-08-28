require('luacov')
local testcase = require('testcase')
local fork = require('testcase.fork')
local sleep = require('testcase.timer').sleep
local assert = require('assert')
local error = require('error')
local errno = require('errno')
local errno_eai = require('errno.eai')
local gpoll = require('gpoll')
local iovec = require('iovec')
local inet = require('net.stream.inet')

local HOST = '127.0.0.1'
local SERVER, CLIENT, PEER
local TESTFILE

function testcase.before_each()
    TESTFILE = os.tmpname()
    os.remove(TESTFILE)
end

function testcase.after_each()
    if PEER then
        PEER:close()
        PEER = nil
    end
    if CLIENT then
        CLIENT:close()
        CLIENT = nil
    end
    if SERVER then
        SERVER:close()
        SERVER = nil
    end
    os.remove(TESTFILE)
    gpoll.set_poller()
end

-- open_pair sets SERVER, CLIENT, PEER so after_each closes them.  The
-- caller may still close explicitly to observe close-side errors.
local function open_pair()
    SERVER = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(SERVER:listen())
    local port = assert(SERVER:getsockname()):port()
    CLIENT = assert(inet.client.new(HOST, port))
    PEER = assert(SERVER:accept())
    return SERVER, CLIENT, PEER
end

function testcase.server_new()
    -- test that create new net.stream.inet.Server
    local s, _, ai = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert.match(tostring(s), '^net.stream.inet.Server: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'tcp')
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.greater(ai:port(), 0)
    s:close()

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.server.new('invalid hostname', 0)
    assert.not_nil(error.is(err, errno_eai.EAI_NONAME))
    _, err = inet.server.new(HOST, 'invalid servname')
    assert(error.is(err, errno_eai.EAI_SERVICE) or
               error.is(err, errno_eai.EAI_NONAME))

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.server.new(HOST, 0, {
            reuseaddr = 1,
        })
    end), 'reuseaddr must be boolean', false)

    assert.match(assert.throws(function()
        inet.server.new(HOST, 0, {
            reuseport = 'foo',
        })
    end), 'reuseport must be boolean', false)
end

function testcase.client_new_failover_across_resolved_addrs()
    -- 'localhost' resolves to ::1 first and 127.0.0.1 second here.  With a
    -- listener on 127.0.0.1 only, the non-blocking connect to ::1 fails
    -- asynchronously; client.new must then try the remaining resolved
    -- address instead of giving up with the first ECONNREFUSED.
    local s = assert(inet.server.new('127.0.0.1', 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c, err = inet.client.new('localhost', port)
    assert(c, err)
    assert.equal(assert(c:getpeername()):addr(), '127.0.0.1')

    c:close()
    s:close()
end

function testcase.client_new()
    local s = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    local port = assert(s:getsockname()):port()

    -- test that return client
    assert(s:listen())
    local c, err, timeout, ai = assert(inet.client.new(HOST, port, {
        deadline = 0.1,
    }))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.match(tostring(c), '^net.stream.inet.Client: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(c:isnonblock(), 'c:isnonblock() is not false')
    assert.equal(c:family(), 'inet')
    assert.equal(c:socktype(), 'stream')
    assert.equal(c:protocol(), 'tcp')
    c:close()
    s:close()

    -- test that returns error that refuse
    c, err, timeout = inet.client.new(HOST, port, {
        deadline = 0.1,
    })
    assert.is_nil(c)
    assert.not_nil(error.is(err, errno.ECONNREFUSED))
    assert.is_nil(timeout)

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.client.new(HOST, port, {
            deadline = 'foo',
        })
    end), 'deadline must be finite number', false)
end

function testcase.accept()
    local _, _, peer = open_pair()
    assert.match(tostring(peer), '^net.stream.inet.Socket: ', false)
end

function testcase.accept_sec_timeout()
    -- accept and acceptfd with a sec argument report the timeout
    -- indication when no connection arrives within the deadline; without
    -- the argument they keep waiting indefinitely and are not exercised
    -- here.
    local s = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())

    local sock, err, timeout = s:accept(nil, 0.05)
    assert.is_nil(sock)
    assert.is_nil(err)
    assert.is_true(timeout)

    local fd, ferr, ftimeout = s:acceptfd(nil, 0.05)
    assert.is_nil(fd)
    assert.is_nil(ferr)
    assert.is_true(ftimeout)
    assert(s:close())
end

function testcase.accept_sec_validation()
    local s = assert(inet.server.new(HOST, 0))
    assert(s:listen())
    assert.match(assert.throws(function()
        s:accept(nil, 'foo')
    end), 'sec must be finite number')
    assert.match(assert.throws(function()
        s:acceptfd(nil, 'foo')
    end), 'sec must be finite number')
    assert(s:close())
end

function testcase.accept_within_sec_with_ai()
    -- a connection arriving within the deadline is accepted with the
    -- timeout slot staying nil, and acceptfd returns the descriptor along
    -- with the peer addrinfo when with_ai is set
    local s = assert(inet.server.new(HOST, 0))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c = assert(inet.client.new(HOST, port))
    local sock, err, timeout, ai = assert(s:accept(true, 1))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.match(tostring(sock), '^net.stream.inet.Socket: ', false)
    assert.not_nil(ai)
    assert.greater(assert(ai:port()), 0)
    assert.equal(ai:addr(), HOST)
    assert(sock:close())
    assert(c:close())

    local c2 = assert(inet.client.new(HOST, port))
    local fd, ferr, ftimeout, fai = assert(s:acceptfd(true, 1))
    assert.is_nil(ferr)
    assert.is_nil(ftimeout)
    assert.greater(fd, 2)
    assert.not_nil(fai)
    assert.equal(fai:addr(), HOST)
    -- the raw descriptor can be adopted back into a socket object
    local adopted = assert(inet.wrap(fd))
    assert(adopted:close())
    assert(c2:close())
    assert(s:close())
end

function testcase.write_read()
    local _, c, peer = open_pair()
    -- write from client, read on the accepted peer.
    assert(c:write('hello'))
    assert.equal(assert(peer:read()), 'hello')
end

function testcase.write_error_returns_zero_len()
    -- Go-style contract: a failed write() must return (0, err) rather
    -- than (nil, err) so callers always have the sent count.
    local s = assert(inet.server.new('127.0.0.1', 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new('127.0.0.1', port))
    local peer = assert(s:accept())

    peer:close()

    -- after the peer closed, writes eventually surface EPIPE; the first
    -- may still succeed into the kernel buffer, so loop.
    local sent, err
    for _ = 1, 8 do
        sent, err = c:write(string.rep('x', 1024))
        if err then
            break
        end
    end
    assert(err, 'write should surface an error after peer close')
    assert.equal(sent, 0, 'failed write must report len 0, not nil')

    c:close()
    s:close()
end

function testcase.send_recv()
    local _, c, peer = open_pair()
    -- send from client, recv on the accepted peer.
    assert(c:send('hello'))
    assert.equal(assert(peer:recv()), 'hello')
end

function testcase.sendfile_recv()
    local _, c, peer = open_pair()
    local f = assert(io.open(TESTFILE, 'w+'))
    assert(f:write('hello'))
    assert(f:flush())
    assert(c:sendfile(f, f:seek('end')))
    assert.equal(assert(peer:recv()), 'hello')
end

function testcase.sendmsg_recvmsg()
    local _, c, peer = open_pair()
    -- new (msg:string) API; cmsg / addr are not used on connected TCP.
    assert.equal(assert(c:sendmsg('hello')), 5)
    assert.equal(assert(peer:recvmsg(5)).data, 'hello')

    assert.equal(assert(c:sendmsg('world')), 5)
    assert.equal(assert(peer:recvmsg(5)).data, 'world')
end

function testcase.zero_timeo_means_no_instant_deadline()
    -- rcvtimeo(0) means "no timeout" (SO_RCVTIMEO semantics): the read
    -- deadline must not collapse to an already-elapsed deadline that
    -- reports an instant timeout before data arrives.
    local s = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(HOST, port))

    assert(c:rcvtimeo(0))
    assert(c:sndtimeo(0))

    -- data sent after a short delay must still be received; an instant
    -- deadline would have returned (nil, nil, true) before it arrives
    local p = fork()
    if p:is_child() then
        s:close()
        sleep(0.2)
        assert(c:send('late'))
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert(peer:rcvtimeo(0))
    assert.equal(peer:recv(), 'late')
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.close_idempotent_and_wait_reports_ebadf()
    -- Closing an already-closed socket must stay idempotent: Socket:close()
    -- unwaits the poller before disposing, and an unwait on the disposed
    -- fd (-1) used to raise a raw Lua error from the poller instead of
    -- being skipped.
    local s = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(HOST, port))

    -- double close is idempotent
    assert(c:close())
    assert(c:close())

    -- waits on the closed socket surface EBADF from the socket layer
    -- itself: the poller is pluggable and must not see the disposed fd
    local ok, err, timeout = c:wait_readable(0.1)
    assert.is_nil(ok)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
    ok, err, timeout = c:wait_writable(0.1)
    assert.is_nil(ok)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)

    s:close()
end

function testcase.writev_error_returns_zero_len()
    -- Go-style contract: a failed writev() must return (0, err) rather
    -- than (nil, err) so callers always have the sent count, matching
    -- every other send-path method.
    local s = assert(inet.server.new('127.0.0.1', 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new('127.0.0.1', port))
    assert(s:accept())
    c:close()

    local iov = iovec.new()
    iov:add('x')

    local sent, err = c:writev(iov)
    assert.equal(sent, 0, 'failed writev must report len 0, not nil')
    assert(err, 'writev on a closed socket must return an error')

    s:close()
end

function testcase.writev_readv()
    local _, c, peer = open_pair()
    local iov_w = iovec.new()
    iov_w:add('hello')
    iov_w:add('world')
    local iov_r = iovec.new()
    iov_r:addn(5)
    assert(c:writev(iov_w))
    -- writev did not consume message
    assert(iov_w:bytes(), 10)
    assert.equal(assert(peer:readv(iov_r)), 5)
    assert.equal(iov_r:concat(), iov_w:get(1))
    assert.equal(assert(peer:readv(iov_r)), 5)
    assert.equal(iov_r:concat(), iov_w:get(2))
end

-- new_lock_poller returns a poller which owns fd locks in a table instead of
-- a real event loop.  A held lock reports timeout immediately, so a leaked
-- lock makes the subsequent lock acquisition fail fast instead of blocking.
local function new_lock_poller()
    local locked = {}
    local function lock(key)
        return function(fd)
            if locked[key .. fd] then
                return false, nil, true
            end
            locked[key .. fd] = true
            return true
        end
    end
    local function unlock(key)
        return function(fd)
            locked[key .. fd] = nil
            return true
        end
    end

    return {
        read_lock = lock('r'),
        read_unlock = unlock('r'),
        write_lock = lock('w'),
        write_unlock = unlock('w'),
    }
end

function testcase.syncread_releases_lock_on_error()
    local _, c = open_pair()
    c:rcvtimeo(0.5)
    gpoll.set_poller(new_lock_poller())

    -- fn that raises an error must not leak the read lock
    local v, err = c:syncread(function()
        error('syncread failure')
    end)
    assert.is_nil(v)
    assert.match(tostring(err), 'syncread failure')

    -- the lock is released, so a subsequent syncread acquires it and runs
    -- its fn instead of timing out
    local executed = false
    v, err = c:syncread(function()
        executed = true
        return 'ok'
    end)
    assert.is_true(executed)
    assert.equal(v, 'ok')
    assert.is_nil(err)
    assert.is_nil(select(3, c:syncread(function()
        return 'ok'
    end)))
end

function testcase.syncwrite_releases_lock_on_error()
    local _, c = open_pair()
    c:sndtimeo(0.5)
    gpoll.set_poller(new_lock_poller())

    -- fn that raises an error must not leak the write lock
    local len, err = c:syncwrite(function()
        error('syncwrite failure')
    end)
    assert.is_nil(len)
    assert.match(tostring(err), 'syncwrite failure')

    -- the lock is released, so a subsequent syncwrite acquires it and runs
    -- its fn instead of timing out
    local executed = false
    len, err = c:syncwrite(function(_, str)
        executed = true
        return #str
    end, 'hello')
    assert.is_true(executed)
    assert.equal(len, 5)
    assert.is_nil(err)
    assert.is_nil(select(3, c:syncwrite(function()
        return 1
    end, 'x')))
end

function testcase.syncread_syncwrite_lock_unsupported()
    local _, c = open_pair()
    -- the default poller does not support fd locks and read_lock/write_lock
    -- return an ENOTSUP error; fn must not run and the error is returned
    local executed = false
    local v, err = c:syncread(function()
        executed = true
    end)
    assert.is_nil(v)
    assert.is_false(executed)
    assert.not_nil(error.is(err, errno.ENOTSUP))

    executed = false
    local _, werr = c:syncwrite(function()
        executed = true
    end)
    assert.is_false(executed)
    assert.not_nil(error.is(werr, errno.ENOTSUP))
end

function testcase.syncwrite_lock_error_returns_nil_len()
    local _, c = open_pair()
    -- when the write lock cannot be acquired, len must be nil so that
    -- callers cannot mistake the truthy 0 for success
    local len, err = c:syncwrite(function()
        error('must not be called')
    end)
    assert.is_nil(len)
    assert.not_nil(error.is(err, errno.ENOTSUP))
end

function testcase.sendfile_eof()
    -- Requesting more bytes than the file holds reaches EOF: sendfile must
    -- report the bytes actually sent and return promptly without driving
    -- the caller into a zero-progress retry loop until the deadline.
    -- (Before the Linux fix, rv == 0 was reported as "again" while the
    -- socket stayed writable, spinning until sndtimeo elapsed.)
    local _, c, p = open_pair()
    assert(c:sndtimeo(1))
    p:close()

    local f = assert(io.open(TESTFILE, 'w'))
    f:write(string.rep('x', 1024))
    f:close()
    local fd = assert(io.open(TESTFILE, 'r'))

    local gettime = require('time.clock').gettime
    local t0 = gettime()
    local sent, err, timeout = c:sendfile(fd, 2048, 0)
    local elapsed = gettime() - t0

    assert.equal(sent, 1024)
    assert.is_nil(err)
    assert.is_nil(timeout)
    -- a busy loop until the deadline would take ~1s (sndtimeo)
    assert.less(elapsed, 0.9)

    fd:close()
    c:close()
end

