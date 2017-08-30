--[[

  Copyright (C) 2015 Masatoshi Teruya

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

  lib/dgram/unix.lua
  lua-net
  Created by Masatoshi Teruya on 15/11/15.

--]]

-- assign to local
local pollable = require('net.poll').pollable;
local getaddrinfo = require('net.dgram').getaddrinfoun;
local socket = require('llsocket.socket');

-- MARK: class Socket
local Socket = require('halo').class.Socket;


Socket.inherits {
    'net.dgram.Socket'
};


--- init
-- @param opts
--  opts.path
-- @return Socket
-- @return err
function Socket:init( opts )
    local nonblock = pollable();
    local addr, err = getaddrinfo( opts );
    local sock;

    if err then
        return nil, err;
    end

    sock, err = socket.new( addr, nonblock );
    if err then
        return nil, err;
    end

    self.sock = sock;
    self.nonblock = nonblock;
    -- init message queue
    self:initq();

    return self;
end


--- connect
-- @param opts
--  opts.path
-- @return err
function Socket:connect( opts )
    if not opts then
        return self.sock:connect();
    else
        local addr, err = getaddrinfo( opts );

        if not err then
            err = self.sock:connect( addr );
        end

        return err;
    end
end


--- bind
-- @param opts
--  opts.path
-- @return err
function Socket:bind( opts )
    if not opts then
        return self.sock:bind();
    else
        local addr, err = getaddrinfo( opts );

        if not err then
            err = self.sock:bind( addr );
        end

        return err;
    end
end


return Socket.exports;
