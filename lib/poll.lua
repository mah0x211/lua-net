--[[

  Copyright (C) 2017 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  lib/poll.lua
  lua-net
  Created by Masatoshi Teruya on 17/07/06.

--]]

--- default functions

--- pollable
-- @return ok
local function pollable() return false; end

--- waitReadable
-- @return ok
-- @return err
-- @return timeout
local function waitReadable() return true; end

--- waitWritable
-- @return ok
-- @return err
-- @return timeout
local function waitWritable() return true; end

--- readLock
-- @param fd
-- @param deadline
-- @return ok
-- @return err
-- @return timeout
local function readLock() return true; end

--- readUnlock
-- @param fd
local function readUnlock() end


--- writeLock
-- @param fd
-- @param deadline
-- @return ok
-- @return err
-- @return timeout
local function writeLock() return true; end

--- writeUnlock
-- @param fd
local function writeUnlock() end


--- load event poller module
do
    local ok, act = pcall( require, 'act' );

    if ok then
        pollable = act.pollable;
        waitReadable = act.waitReadable;
        waitWritable = act.waitWritable
        readLock = act.readLock;
        readUnlock = act.readUnlock;
        writeLock = act.writeLock;
        writeUnlock = act.writeUnlock;
    end
end


--- recvsync
-- @param sock
-- @param fn
-- @param ...
-- @return msg
-- @return err
-- @return timeout
local function recvsync( sock, fn, ... )
    -- wait until another coroutine releases the right to read
    local fd = sock:fd();
    local ok, err, timeout = readLock( fd, sock.rcvdeadl );
    local msg;

    if ok then
        msg, err, timeout = fn( sock, ... );
        readUnlock( fd );
    end

    return msg, err, timeout;
end


--- recvfromsync
-- @param sock
-- @param fn
-- @param ...
-- @return msg
-- @return addr
-- @return err
-- @return timeout
local function recvfromsync( sock, fn, ... )
    -- wait until another coroutine releases the right to read
    local fd = sock:fd();
    local ok, err, timeout = readLock( fd, sock.rcvdeadl );
    local msg, addr;

    if ok then
        msg, addr, err, timeout = fn( sock, ... );
        readUnlock( fd );
    end

    return msg, addr, err, timeout;
end


--- sendsync
-- @param sock
-- @param fn
-- @param ...
-- @return len
-- @return err
-- @return timeout
local function sendsync( sock, fn, ... )
    -- wait until another coroutine releases the right to write
    local fd = sock:fd();
    local ok, err, timeout = writeLock( fd, sock.snddeadl );
    local len = 0;

    if ok then
        len, err, timeout = fn( sock, ... );
        writeUnlock( fd );
    end

    return len, err, timeout;
end


--- waitio
-- @param fn
-- @param fd
-- @param deadline
-- @param hook
-- @param ctx
-- @return ok
-- @return err
-- @return timeout
local function waitio( fn, fd, deadline, hook, ctx )
    -- call hook function before wait ioable
    if hook then
        local ok, err, timeout = hook( ctx, deadline );

        if not ok then
            return false, err, timeout;
        end
    end

    -- wait until ioable
    return fn( fd, deadline );
end


--- waitrecv
-- @param fd
-- @param deadline
-- @param hook
-- @param ctx
-- @return ok
-- @return err
-- @return timeout
local function waitrecv( fd, deadline, hook, ctx )
    return waitio( waitReadable, fd, deadline, hook, ctx );
end


--- waitsend
-- @param fd
-- @param deadline
-- @param hook
-- @param ctx
-- @return ok
-- @return err
-- @return timeout
local function waitsend( fd, deadline, hook, ctx )
    return waitio( waitWritable, fd, deadline, hook, ctx );
end


return {
    pollable = pollable,
    waitrecv = waitrecv,
    waitsend = waitsend,
    recvsync = recvsync,
    recvfromsync = recvfromsync,
    sendsync = sendsync,
};

