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

  lib/stream/inet/server.lua
  lua-net
  Created by Masatoshi Teruya on 15/11/15.

--]]

-- assign to local
local llsocket = require('llsocket');
local socket = llsocket.socket;
local getaddrinfo = llsocket.inet.getaddrinfo;

-- constants
local SOCK_STREAM = llsocket.SOCK_STREAM;
local IPPROTO_TCP = llsocket.IPPROTO_TCP;
local AI_PASSIVE = llsocket.AI_PASSIVE;

-- MARK: class Server
local Server = require('halo').class.Server;


Server.inherits {
    'net.stream.Server'
};


--- init
-- @param opts
--  opts.host
--  opts.port
--  opts.nonblock
--  opts.reuseaddr
-- @return server
-- @return err
function Server:init( opts )
    local addrinfo, err;

    addrinfo, err = getaddrinfo(
        opts.host, opts.port, SOCK_STREAM, IPPROTO_TCP, AI_PASSIVE
    );
    if not err then
        local sock;

        for _, addr in ipairs( addrinfo ) do
            sock, err = socket.new( addr, opts.nonblock == true );
            if not err then
                self.sock = sock;
                -- enable reuseaddr
                if opts.reuseaddr == true then
                    _, err = sock:reuseaddr( true );
                    if err then
                        sock:close();
                        return nil, err;
                    end
                end

                -- bind
                err = sock:bind();
                if not err then
                    return self;
                end

                sock:close();
                break;
            end
        end
    end

    return nil, err;
end


return Server.exports;

