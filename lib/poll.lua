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

--- readable
-- @return ok
-- @return err
-- @return timeout
local function readable() return true; end

--- writable
-- @return ok
-- @return err
-- @return timeout
local function writable() return true; end

--- readlock
-- @param fd
-- @param deadline
-- @return ok
-- @return err
-- @return timeout
local function readlock() return true; end

--- readunlock
-- @param fd
local function readunlock() end


--- writelock
-- @param fd
-- @param deadline
-- @return ok
-- @return err
-- @return timeout
local function writelock() return true; end

--- writelock
-- @param fd
local function writeunlock() end


--- load event poller module
do
    local ok, synops = pcall( require, 'synops' );

    if ok then
        pollable = synops.pollable;
        readable = synops.readable;
        writable = synops.writable
        readlock = synops.readlock;
        readunlock = synops.readunlock;
        writelock = synops.writelock;
        writeunlock = synops.writeunlock;
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
    local ok, err, timeout = readlock( fd, sock.rcvdeadl );
    local msg;

    if ok then
        msg, err, timeout = fn( sock, ... );
        readunlock( fd );
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
    local ok, err, timeout = readlock( fd, sock.rcvdeadl );
    local msg, addr;

    if ok then
        msg, addr, err, timeout = fn( sock, ... );
        readunlock( fd );
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
    local ok, err, timeout = writelock( fd, sock.snddeadl );
    local len = 0;

    if ok then
        len, err, timeout = fn( sock, ... );
        writeunlock( fd );
    end

    return len, err, timeout;
end



return {
    pollable = pollable,
    readable = readable,
    writable = writable,
    recvsync = recvsync,
    recvfromsync = recvfromsync,
    sendsync = sendsync,
};

