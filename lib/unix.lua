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
local waitrecv = require('net.poll').waitrecv;
local waitsend = require('net.poll').waitsend;
local recvsync = require('net.poll').recvsync;
local sendsync = require('net.poll').sendsync;


-- MARK: class Socket
local Socket = require('halo').class.Socket;


Socket.inherits {
    'net.Socket'
};


--- sendfd
-- @param fd
-- @param ai
-- @return len
-- @return err
-- @return timeout
function Socket:sendfd( fd, ai )
    if self.tls then
        -- currently, does not support sendfd on tls connection
        -- EOPNOTSUPP: Operation not supported on socket
        return nil, 'Operation not supported on socket';
    end

    while true do
        local len, err, again = self.sock:sendfd( fd, ai );

        if not len then
            return nil, err;
        elseif not again or not self.nonblock then
            return len, err, again;
        -- wait until writable
        else
            local ok, perr, timeout = waitsend( self:fd(), self.snddeadl,
                                                self.sndhook, self.sndhookctx );

            if not ok then
                return len, perr, timeout;
            end
        end
    end
end


--- sendfdsync
-- @param fd
-- @param ai
-- @return len
-- @return err
-- @return timeout
function Socket:sendfdsync( ... )
    return sendsync( self, self.sendfd, ... );
end


--- recvfd
-- @return fd
-- @return err
-- @return timeout
function Socket:recvfd()
    if self.tls then
        -- currently, does not support recvmsg on tls connection
        -- EOPNOTSUPP: Operation not supported on socket
        return nil, 'Operation not supported on socket';
    end

    while true do
        local fd, err, again = self.sock:recvfd();

        if not again or not self.nonblock then
            return fd, err, again;
        -- wait until readable
        else
            local ok, perr, timeout = waitrecv( self:fd(), self.rcvdeadl,
                                                self.rcvhook, self.rcvhookctx );

            if not ok then
                return nil, perr, timeout;
            end
        end
    end
end


--- recvfdsync
-- @return fd
-- @return err
-- @return timeout
function Socket:recvfdsync( ... )
    return recvsync( self, self.recvfd, ... );
end


Socket = Socket.exports;
