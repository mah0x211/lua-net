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

  lib/stream/unix/client.lua
  lua-net
  Created by Masatoshi Teruya on 15/11/15.

--]]

-- assign to local
local llsocket = require('llsocket');
local socket = llsocket.socket;
local getaddrinfo = llsocket.unix.getaddrinfo;

-- constants
local SOCK_STREAM = llsocket.SOCK_STREAM;

-- MARK: class Client
local Client = require('halo').class.Client;


Client.inherits {
    'net.stream.Socket'
};


--- init
-- @param opts
--  opts.path
--  opts.nonblock
-- @return Client
function Client:init( opts )
    local err;

    self.path = opts.path;
    self.nonblock = opts.nonblock == true;

    err = self:connect();
    if err then
        return nil, err;
    end

    return self;
end


--- connect
-- @return  err     string or nil
function Client:connect()
    local addrinfo, err = getaddrinfo( self.path, SOCK_STREAM );

    if not err then
        local sock;

        sock, err = socket.new( addrinfo, self.nonblock );
        if sock then
            err = sock:connect();
            if not err then
                -- close current socket
                if self.sock then
                    self.sock:close();
                end

                self.sock = sock;
                return;
            end

            -- close failed
            sock:close();
        end
    end

    return err;
end


return Client.exports;

