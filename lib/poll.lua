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
--- @return string? err
--- @return boolean? timeout
local function poll_wait_readable(fd, msec)
    return false, 'not pollable'
end

--- poll_wait_writable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function poll_wait_writable(fd, msec)
    return true
end

--- poll_unwait_readable
--- @param fd integer
--- @return boolean? ok
local function poll_unwait_readable(fd)
    return true
end

--- poll_unwait_writable
--- @param fd integer
--- @return boolean? ok
local function poll_unwait_writable(fd)
    return true
end

--- poll_unwait
-- @param fd
local function poll_unwait(fd)
    return true
end

--- poll_read_lock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function poll_read_lock(fd, msec)
    return false, 'not pollable'
end

--- poll_read_unlock
--- @param fd integer
--- @return boolean ok
local function poll_read_unlock(fd)
    return true
end

--- poll_write_lock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function poll_write_lock(fd, msec)
    return true
end

--- poll_write_unlock
--- @param fd integer
local function poll_write_unlock(fd)
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
---@param p table
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
                error(format('%q is not function: %q', k, type(f)))
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
--- @return string? err
--- @return boolean? timeout
local function readlock(fd, deadline)
    return poll_read_lock(fd, deadline)
end

--- readunlock releases a read lock
--- @param fd integer
--- @return boolean ok
--- @return string? err
local function readunlock(fd)
    return poll_read_unlock(fd)
end

--- recvsync
--- @param sock net.Socket
--- @param deadline integer
--- @param fn function
--- @vararg any arguments
--- @return any? val
--- @return string? err
--- @return boolean? timeout
--- @return any? extra
local function recvsync(sock, deadline, fn, ...)
    -- wait until another coroutine releases the right to read
    local fd = sock:fd()
    local ok, err, timeout = poll_read_lock(fd, deadline)
    local val, extra

    if ok then
        val, err, timeout, extra = fn(sock, ...)
        poll_read_unlock(fd)
    end

    return val, err, timeout, extra
end

--- sendsync
--- @param sock net.Socket
--- @param deadline integer
--- @param fn function
--- @vararg any arguments
--- @return integer? len
--- @return string? err
--- @return boolean? timeout
local function sendsync(sock, deadline, fn, ...)
    -- wait until another coroutine releases the right to write
    local fd = sock:fd()
    local ok, err, timeout = poll_write_lock(fd, deadline)
    local len = 0

    if ok then
        len, err, timeout = fn(sock, ...)
        poll_write_unlock(fd)
    end

    return len, err, timeout
end

--- waitio
--- @param pollfn function
--- @param fd integer
--- @param deadline integer
--- @param hook function
--- @param ctx any
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function waitio(pollfn, fd, deadline, hook, ctx)
    -- call hook function before wait ioable
    if hook then
        local ok, err, timeout = hook(ctx, deadline)

        if not ok then
            return false, err, timeout
        end
    end

    -- wait until ioable
    return pollfn(fd, deadline)
end

--- waitrecv
--- @param fd integer
--- @param deadline integer
--- @param hook function
--- @param ctx any
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function waitrecv(fd, deadline, hook, ctx)
    return waitio(poll_wait_readable, fd, deadline, hook, ctx)
end

--- waitsend
--- @param fd integer
--- @param deadline integer
--- @param hook function
--- @param ctx any
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function waitsend(fd, deadline, hook, ctx)
    return waitio(poll_wait_writable, fd, deadline, hook, ctx)
end

--- unwaitrecv
--- @param fd integer
local function unwaitrecv(fd)
    return poll_unwait_readable(fd)
end

--- unwaitsend
--- @param fd integer
local function unwaitsend(fd)
    return poll_unwait_writable(fd)
end

--- unwait
--- @param fd integer
local function unwait(fd)
    return poll_unwait(fd)
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
    recvsync = recvsync,
    sendsync = sendsync,
}
