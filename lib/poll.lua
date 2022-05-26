--
-- Copyright (C) 2017 Masatoshi Teruya
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- lib/poll.lua
-- lua-net
-- Created by Masatoshi Teruya on 17/07/06.
--
local toerror = require('error').toerror
local new_errno = require('errno').new

--- default functions
--- poll_pollable
--- @return boolean ok
local function poll_pollable()
    return false
end

--- poll_wait_readable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
local function poll_wait_readable(fd, msec)
    return false, new_errno('ENOTSUP', 'not pollable')
end

--- poll_wait_writable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
local function poll_wait_writable(fd, msec)
    return false, new_errno('ENOTSUP', 'not pollable')
end

--- poll_unwait_readable
--- @param fd integer
--- @return boolean ok
--- @return error? err
local function poll_unwait_readable(fd)
    return true
end

--- poll_unwait_writable
--- @param fd integer
--- @return boolean? ok
--- @return error? err
local function poll_unwait_writable(fd)
    return true
end

--- poll_unwait
--- @param fd
--- @return boolean? ok
--- @return error? err
local function poll_unwait(fd)
    return true
end

--- poll_read_lock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
local function poll_read_lock(fd, msec)
    return false, new_errno('ENOTSUP', 'not pollable')
end

--- poll_read_unlock
--- @param fd integer
--- @return boolean ok
--- @return error? err
local function poll_read_unlock(fd)
    return true
end

--- poll_write_lock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
local function poll_write_lock(fd, msec)
    return false, new_errno('ENOTSUP', 'not pollable')
end

--- poll_write_unlock
--- @param fd integer
--- @return boolean ok
--- @return error? err
local function poll_write_unlock(fd)
    return true
end

local DEFAULT_POLLER = {
    pollable = poll_pollable,
    wait_readable = poll_wait_readable,
    wait_writable = poll_wait_writable,
    unwait_readable = poll_unwait_readable,
    unwait_writable = poll_unwait_writable,
    unwait = poll_unwait,
    read_lock = poll_read_lock,
    read_unlock = poll_read_unlock,
    write_lock = poll_write_lock,
    write_unlock = poll_write_unlock,
}

-- assign to local
local type = type
local error = error
local format = string.format

--- set_poller replace the internal polling functions
--- @param p table
local function set_poller(p)
    if p == nil then
        p = DEFAULT_POLLER
    else
        for _, k in ipairs({
            'pollable',
            'wait_readable',
            'wait_writable',
            'unwait_readable',
            'unwait_writable',
            'unwait',
            'read_lock',
            'read_unlock',
            'write_lock',
            'write_unlock',
        }) do
            local f = p[k]
            if type(f) ~= 'function' then
                error(format('%q is not function: %q', k, type(f)), 2)
            end
        end
    end

    --- replace poll functions
    poll_pollable = p.pollable
    poll_wait_readable = p.wait_readable
    poll_wait_writable = p.wait_writable
    poll_unwait_readable = p.unwait_readable
    poll_unwait_writable = p.unwait_writable
    poll_unwait = p.unwait
    poll_read_lock = p.read_lock
    poll_read_unlock = p.read_unlock
    poll_write_lock = p.write_lock
    poll_write_unlock = p.write_unlock
end

--- readlock waits until a read lock is acquired
--- @param fd integer
--- @param deadline integer
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
local function readlock(fd, deadline)
    local ok, err, timeout = poll_read_lock(fd, deadline)
    if ok then
        return true
    elseif err == nil then
        error('poll_read_lock returned false without error')
    end
    return false, toerror(err), timeout
end

--- readunlock releases a read lock
--- @param fd integer
--- @return boolean ok
--- @return error? err
local function readunlock(fd)
    local ok, err = poll_read_unlock(fd)
    if ok then
        return true
    elseif err == nil then
        error('poll_read_unlock returned false without error')
    end
    return false, toerror(err)
end

--- writelock waits until a write lock is acquired
--- @param fd integer
--- @param deadline integer
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
local function writelock(fd, deadline)
    local ok, err, timeout = poll_write_lock(fd, deadline)
    if ok then
        return true
    elseif err == nil then
        error('poll_write_lock returned false without error')
    end
    return false, toerror(err), timeout
end

--- writeunlock releases a write lock
--- @param fd integer
--- @return boolean ok
--- @return error? err
local function writeunlock(fd)
    local ok, err = poll_write_unlock(fd)
    if ok then
        return true
    elseif err == nil then
        error('poll_write_unlock returned false without error')
    end
    return false, toerror(err)
end

--- waitrecv
--- @param fd integer
--- @param deadline integer
--- @param hook function
--- @param ctx any
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
local function waitrecv(fd, deadline, hook, ctx)
    -- call hook function before wait
    if hook then
        local ok, err, timeout = hook(ctx, deadline)

        if not ok then
            if err == nil then
                error('hook returned false without error')
            end
            return false, toerror(err), timeout
        end
    end

    return poll_wait_readable(fd, deadline)
end

--- waitsend
--- @param fd integer
--- @param deadline integer
--- @param hook function
--- @param ctx any
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
local function waitsend(fd, deadline, hook, ctx)
    -- call hook function before wait
    if hook then
        local ok, err, timeout = hook(ctx, deadline)

        if not ok then
            if err == nil then
                error('hook returned false without error')
            end
            return false, toerror(err), timeout
        end
    end

    return poll_wait_writable(fd, deadline)
end

--- unwaitrecv
--- @param fd integer
local function unwaitrecv(fd)
    local ok, err = poll_unwait_readable(fd)
    if ok then
        return true
    elseif err == nil then
        error('poll_unwait_readable returned false without error')
    end
    return false, toerror(err)
end

--- unwaitsend
--- @param fd integer
local function unwaitsend(fd)
    local ok, err = poll_unwait_writable(fd)
    if ok then
        return true
    elseif err == nil then
        error('poll_unwait_writable returned false without error')
    end
    return false, toerror(err)
end

--- unwait
--- @param fd integer
local function unwait(fd)
    local ok, err = poll_unwait(fd)
    if ok then
        return true
    elseif err == nil then
        error('poll_unwait returned false without error')
    end
    return false, toerror(err)
end

--- pollable
--- @return boolean ok
local function pollable()
    return poll_pollable()
end

return {
    set_poller = set_poller,
    pollable = pollable,
    waitrecv = waitrecv,
    waitsend = waitsend,
    unwaitrecv = unwaitrecv,
    unwaitsend = unwaitsend,
    unwait = unwait,
    readlock = readlock,
    readunlock = readunlock,
    writelock = writelock,
    writeunlock = writeunlock,
}
