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

  lib/dgram/inet.lua
  lua-net
  Created by Masatoshi Teruya on 15/11/15.

--]]

-- assign to local
local getaddrinfo = require('net.dgram').getaddrinfoin;
local llsocket = require('llsocket');
local socket = llsocket.socket;

-- MARK: class Socket
local Socket = require('halo').class.Socket;


Socket.inherits {
    'net.dgram.Socket'
};


--- init
-- @param opts
--  opts.host
--  opts.port
--  opts.passive
--  opts.nonblock
--  opts.reuseaddr
-- @return Socket
-- @return err
function Socket:init( opts )
    local addrs, err = getaddrinfo( opts );

    if not err then
        local nonblock = opts.nonblock == true;
        local sock;

        for _, addr in ipairs( addrs ) do
            sock, err = socket.new( addr, nonblock );
            if not err then
                -- enable reuseaddr
                if opts.reuseaddr == true then
                    _, err = sock:reuseaddr( true );
                    if err then
                        sock:close();
                        return nil, err;
                    end
                end

                self.sock = sock;
                -- init message queue if non-blocking mode
                if nonblock then
                    self:initq();
                end

                return self;
            end
        end
    end

    return nil, err;
end


--- connect
-- @param opts
--  opts.host
--  opts.port
--  opts.passive
--  opts.canonname
--  opts.numeric
-- @return err
function Socket:connect( opts )
    if not opts then
        return self.sock:connect();
    else
        local addrs, err = getaddrinfo( opts );

        if not err then
            for _, addr in ipairs( addrs ) do
                err = self.sock:connect( addr );
                if not err then
                    break;
                end
            end
        end

        return err;
    end
end


--- bind
-- @param opts
--  opts.host
--  opts.port
--  opts.passive
--  opts.canonname
--  opts.numeric
-- @return err
function Socket:bind( opts )
    if not opts then
        return self.sock:bind();
    else
        local addrs, err = getaddrinfo( opts );

        if not err then
            for _, addr in ipairs( addrs ) do
                err = self.sock:bind( addr );
                if not err then
                    break;
                end
            end
        end

        return err;
    end
end


return Socket.exports;
