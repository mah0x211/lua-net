local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')

local EXTERNALLY_CLOSED_SOCKET

function testcase.after_each()
    if EXTERNALLY_CLOSED_SOCKET then
        -- The fd is already closed; discard stale ownership without closing
        -- a descriptor that may since have been reused.
        EXTERNALLY_CLOSED_SOCKET:unwrap()
        EXTERNALLY_CLOSED_SOCKET = nil
    end
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
    local before, opt_err = s:rcvtimeo()
    assert.is_number(before)
    assert.is_nil(opt_err)
    local prev
    prev, opt_err = s:rcvtimeo(1.5)
    assert.equal(prev, before)
    assert.is_nil(opt_err)
    local value
    value, opt_err = s:rcvtimeo()
    assert.equal(value, 1.5)
    assert.is_nil(opt_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:rcvtimeo()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:rcvtimeo(0.5)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
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
    local before, opt_err = s:sndtimeo()
    assert.is_number(before)
    assert.is_nil(opt_err)
    local prev
    prev, opt_err = s:sndtimeo(1.5)
    assert.equal(prev, before)
    assert.is_nil(opt_err)
    local value
    value, opt_err = s:sndtimeo()
    assert.equal(value, 1.5)
    assert.is_nil(opt_err)

    assert(socket.close(s:fd()))
    EXTERNALLY_CLOSED_SOCKET = s
    local rv, err = s:sndtimeo()
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    rv, err = s:sndtimeo(0.5)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
end

function testcase.rcvtimeo_and_sndtimeo_reject_nan_inf_and_out_of_range()
    -- Reject non-finite or out-of-range values before converting to timeval
    -- fields. Negative timeouts are invalid even when the casts would fit.
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
        assert.is_nil(rv)
        assert(err)
        assert.equal(err.type, errno.EINVAL)

        rv, err = s:sndtimeo(bad)
        assert.is_nil(rv)
        assert(err)
        assert.equal(err.type, errno.EINVAL)

        local terr = assert.throws(function()
            socket.new_inet({
                socktype = 'stream',
                protocol = 'tcp',
                rcvtimeo = bad,
            })
        end)
        assert.match(terr,
                     'opts.rcvtimeo must be a finite, non-negative number within the time_t range')

        terr = assert.throws(function()
            socket.new_inet({
                socktype = 'stream',
                protocol = 'tcp',
                sndtimeo = bad,
            })
        end)
        assert.match(terr,
                     'opts.sndtimeo must be a finite, non-negative number within the time_t range')
    end
    s:close()
end
