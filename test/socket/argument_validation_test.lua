local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')

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
    local err = assert.throws(function()
        s:listen(-1)
    end)
    assert.match(err, 'backlog must be a non-negative integer in the int range')
    err = assert.throws(function()
        s:listen(2147483648)
    end)
    assert.match(err, 'backlog must be a non-negative integer in the int range')

    -- linger: int range, negatives disable, INT_MIN/INT_MAX accepted
    assert(s:linger(2147483647))
    assert(s:linger(-2147483648))
    assert.equal(s:linger(), -1)
    err = assert.throws(function()
        s:linger(2147483649)
    end)
    assert.match(err, 'linger must be an integer in the int range')
    err = assert.throws(function()
        s:linger(-2147483649)
    end)
    assert.match(err, 'linger must be an integer in the int range')

    -- runtime sockopt setter
    assert(s:rcvbuf(2147483647))
    err = assert.throws(function()
        s:rcvbuf(2147483648)
    end)
    assert.match(err, 'rcvbuf must be an integer in the int range')
    err = assert.throws(function()
        s:rcvbuf(-2147483649)
    end)
    assert.match(err, 'rcvbuf must be an integer in the int range')

    -- constructor opts table
    err = assert.throws(function()
        socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
            rcvbuf = 2147483648,
        })
    end)
    assert.match(err, 'opts.rcvbuf must be an integer in the int range')
    assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
        rcvbuf = 2147483647,
    }):close())

    s:close()
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
    assert.match(err, 'cmsg[1].data: fd must be in the range')

    err = assert.throws(function()
        a:sendmsg('x', nil, {
            {
                level = 'socket',
                type = 'rights',
                data = 1.5,
            },
        })
    end)
    assert.match(err, 'cmsg[1].data must be integer fd')

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
    assert.match(err, 'cmsg[1].data[2]: fd must be in the range')

    a:close()
    socks[2]:close()
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
