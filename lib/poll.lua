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
--- pollable
--- @return boolean ok
local function pollable()
    return false
end

--- waitReadable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function waitReadable(fd, msec)
    return true
end

--- waitWritable
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function waitWritable(fd, msec)
    return true
end

--- unwaitReadable
--- @param fd integer
--- @return boolean? ok
local function unwaitReadable(fd)
    return true
end

--- unwaitWritable
--- @param fd integer
--- @return boolean? ok
local function unwaitWritable(fd)
    return true
end

--- unwait
-- @param fd
local function unwait(fd)
    return true
end

--- readLock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function readLock(fd, msec)
    return true
end

--- readUnlock
--- @param fd integer
local function readUnlock(fd)
end

--- writeLock
--- @param fd integer
--- @param msec integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function writeLock(fd, msec)
    return true
end

--- writeUnlock
--- @param fd integer
local function writeUnlock(fd)
end

--- load event poller module
do
    local ok, act = pcall(require, 'act')

    if ok then
        pollable = act.pollable
        waitReadable = act.waitReadable
        waitWritable = act.waitWritable
        unwaitReadable = act.unwaitReadable
        unwaitWritable = act.unwaitWritable
        unwait = act.unwait
        readLock = act.readLock
        readUnlock = act.readUnlock
        writeLock = act.writeLock
        writeUnlock = act.writeUnlock
    end
end

--- recvsync
--- @param sock net.Socket
--- @param fn function
--- @vararg integer flags
--- @return string? msg
--- @return string? err
--- @return boolean? timeout
local function recvsync(sock, fn, ...)
    -- wait until another coroutine releases the right to read
    local fd = sock:fd()
    local ok, err, timeout = readLock(fd, sock.rcvdeadl)
    local msg

    if ok then
        msg, err, timeout = fn(sock, ...)
        readUnlock(fd)
    end

    return msg, err, timeout
end

--- recvfromsync
--- @param sock net.dgram.Socket
--- @param fn function
--- @vararg integer flags
--- @return string? msg
--- @return string? err
--- @return boolean? timeout
--- @return llsocket.addrinfo? ai
local function recvfromsync(sock, fn, ...)
    -- wait until another coroutine releases the right to read
    local fd = sock:fd()
    local ok, err, timeout = readLock(fd, sock.rcvdeadl)
    local msg, ai

    if ok then
        msg, err, timeout, ai = fn(sock, ...)
        readUnlock(fd)
    end

    return msg, err, timeout, ai
end

--- sendsync
--- @param sock net.Socket
--- @param fn function
--- @vararg integer flags
--- @return integer? len
--- @return string? err
--- @return boolean? timeout
local function sendsync(sock, fn, ...)
    -- wait until another coroutine releases the right to write
    local fd = sock:fd()
    local ok, err, timeout = writeLock(fd, sock.snddeadl)
    local len = 0

    if ok then
        len, err, timeout = fn(sock, ...)
        writeUnlock(fd)
    end

    return len, err, timeout
end

--- waitio
--- @param fn function
--- @param fd integer
--- @param deadline integer
--- @param hook function
--- @param ctx any
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
local function waitio(fn, fd, deadline, hook, ctx)
    -- call hook function before wait ioable
    if hook then
        local ok, err, timeout = hook(ctx, deadline)

        if not ok then
            return false, err, timeout
        end
    end

    -- wait until ioable
    return fn(fd, deadline)
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
    return waitio(waitReadable, fd, deadline, hook, ctx)
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
    return waitio(waitWritable, fd, deadline, hook, ctx)
end

return {
    pollable = pollable,
    waitrecv = waitrecv,
    waitsend = waitsend,
    unwaitrecv = unwaitReadable,
    unwaitsend = unwaitWritable,
    unwait = unwait,
    recvsync = recvsync,
    recvfromsync = recvfromsync,
    sendsync = sendsync,
}
