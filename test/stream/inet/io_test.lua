local support = require('test.stream.inet.helpers').new()
local testcase = require('testcase')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local sleep = require('testcase.timer').sleep
local assert = require('assert')
local error = require('error')
local errno = require('errno')
local inet = require('net.stream.inet')
local HOST = support.HOST
local open_pair = support.open_pair

local TESTFILE

function testcase.before_each()
    TESTFILE = support.before_each()
end

function testcase.after_each()
    support.after_each()
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
    local _, c = open_pair()
    -- Local write shutdown makes the failed write deterministic.
    assert(c:closew())
    local sent, err = c:write('x')
    assert.not_nil(error.is(err, errno.EPIPE))
    assert.equal(sent, 0)
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
    -- rcvtimeo(0) selects the library default: the read
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
    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            sleep(0.2)
            assert(c:send('late'))
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert(peer:rcvtimeo(0))
    assert.equal(peer:recv(), 'late')
    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
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

function testcase.sendfile_eof()
    -- Requesting more bytes than the file holds reaches EOF: sendfile must
    -- report the bytes actually sent and return promptly without driving
    -- the caller into a zero-progress retry loop until the deadline.
    -- (Before the Linux fix, rv == 0 was reported as "again" while the
    -- socket stayed writable, spinning until sndtimeo elapsed.)
    local _, c, p = open_pair()
    assert(c:sndtimeo(1))
    assert(p:rcvtimeo(1))

    local data = string.rep('x', 1024)
    local f = assert(io.open(TESTFILE, 'w'))
    f:write(data)
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

    -- TCP may split the payload across reads. Keep the peer open until all
    -- bytes have arrived, independently of how the kernel segments them.
    local received = {}
    local nrecv = 0
    while nrecv < #data do
        local chunk = assert(p:recv(#data - nrecv))
        assert.not_equal(chunk, '')
        received[#received + 1] = chunk
        nrecv = nrecv + #chunk
    end
    assert.equal(table.concat(received), data)

    fd:close()
    p:close()
    c:close()
end
