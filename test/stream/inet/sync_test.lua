local support = require('test.stream.inet.helpers').new()
local testcase = require('testcase')
local assert = require('assert')
local error = require('error')
local errno = require('errno')
local gpoll = require('gpoll')
local open_pair = support.open_pair


function testcase.before_each()
    support.before_each()
end

function testcase.after_each()
    support.after_each()
end

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

function testcase.sync_normalizes_zero_timeo_for_lock_wait()
    -- rcvtimeo(0)/sndtimeo(0) select the library defaults, but a
    -- poller treats a lock wait of sec=0 as an immediate timeout, so
    -- every syncread/syncwrite under contention would fail instantly.
    -- The lock wait must use the library defaults (330s / 960s), the
    -- same normalization the async read/write paths apply.
    local _, c = open_pair()
    c:rcvtimeo(0)
    c:sndtimeo(0)

    local rsec, wsec
    gpoll.set_poller({
        read_lock = function(_, sec)
            rsec = sec
            return true
        end,
        read_unlock = function()
            return true
        end,
        write_lock = function(_, sec)
            wsec = sec
            return true
        end,
        write_unlock = function()
            return true
        end,
    })

    assert.equal(c:syncread(function()
        return 'ok'
    end), 'ok')
    assert.equal(rsec, 330)

    assert.equal(c:syncwrite(function(_, str)
        return #str
    end, 'x'), 1)
    assert.equal(wsec, 960)
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
