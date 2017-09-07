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

  lib/unix.lua
  lua-net
  Created by Masatoshi Teruya on 17/09/05.

--]]

-- assign to local
local readable = require('net.poll').readable;
local writable = require('net.poll').writable;


-- MARK: class Socket
local Socket = require('halo').class.Socket;


Socket.inherits {
    'net.Socket'
};


--- sendfd
-- @param self
-- @param fd
-- @param ai
-- @return len number of bytes sent
-- @return err
-- @return timeout
local function sendfd( self, fd, ai )
    local sock, fn;

    if self.tls then
        -- currently, does not support sendfd on tls connection
        -- EOPNOTSUPP: Operation not supported on socket
        return nil, 'Operation not supported on socket';
    else
        sock, fn = self.sock, self.sock.sendfd;
    end

    while true do
        local len, err, again = fn( sock, fd, ai );

        if not len then
            return nil, err;
        elseif not again or not self.nonblock then
            return len, err, again;
        -- wait until writable
        else
            local ok, perr, timeout = writable( self:fd(), self.snddeadl );

            if not ok then
                return len, perr, timeout;
            end
        end
    end
end


--- sendfdqred
-- @param self
-- @param args
--  [1] fd
--  [2] ai
-- @return len number of bytes sent or queued
-- @return err
-- @return timeout
local function sendfdqred( self, args )
    return sendfd( self, args[1], args[2] );
end


--- sendfd
-- @param fd
-- @param ai
-- @return len number of bytes sent or queued
-- @return err
-- @return timeout
function Socket:sendfd( fd, ai )
    if self.msgqtail == 0 then
        local len, err, timeout = sendfd( self, fd, ai );

        if timeout then
            self:sendfdq( fd );
        end

        return len, err, timeout;
    end

    -- put into send queue
    self:sendfdq( fd, ai );

    return self:flushq();
end


--- sendfdq
-- @param fd
-- @param ai
function Socket:sendfdq( fd, ai )
    -- put str into message queue
    self.msgqtail = self.msgqtail + 1;
    self.msgq[self.msgqtail] = {
        fn = sendfdqred,
        fd,
        ai
    };
end


--- recvfd
-- @return fd
-- @return err
-- @return timeout
function Socket:recvfd()
    local sock, fn;

    if self.tls then
        -- currently, does not support recvmsg on tls connection
        -- EOPNOTSUPP: Operation not supported on socket
        return nil, 'Operation not supported on socket';
    else
        sock, fn = self.sock, self.sock.recvfd;
    end

    while true do
        local fd, err, again = fn( sock );

        if not again or not self.nonblock then
            return fd, err, again;
        -- wait until readable
        else
            local ok, perr, timeout = readable( self:fd(), self.rcvdeadl );

            if not ok then
                return nil, perr, timeout;
            end
        end
    end
end


Socket = Socket.exports;
