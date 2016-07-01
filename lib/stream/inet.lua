--[[

  Copyright (C) 2016 Masatoshi Teruya

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

  lib/stream/inet.lua
  lua-net
  Created by Masatoshi Teruya on 16/05/16.

--]]

-- assign to local
local getaddrinfo = require('net.stream').getaddrinfoin;
local llsocket = require('llsocket');
local socket = llsocket.socket;

-- MARK: class Client
local Client = require('halo').class.Client;


Client.inherits {
    'net.stream.Socket'
};


--- init
-- @param opts
--  opts.host
--  opts.port
--  opts.nonblock
-- @return Client
-- @return err
function Client:init( opts )
    local err;

    self.opts = {
        host = opts.host,
        port = opts.port,
        nonblock = opts.nonblock == true
    };

    err = self:connect();
    if err then
        return nil, err;
    end

    return self;
end


--- connect
-- @return err
function Client:connect()
    local addrinfo, err = getaddrinfo( self.opts );

    if not err then
        local sock;

        for _, addr in ipairs( addrinfo ) do
            sock, err = socket.new( addr, self.opts.nonblock );
            if not err then
                err = sock:connect();
                if not err then
                    -- close current socket
                    if self.sock then
                        self.sock:close();
                    end

                    self.sock = sock;
                    -- init message queue if non-blocking mode
                    if self.opts.nonblock then
                        self:initq();
                    end

                    return;
                end

                -- close failed
                sock:close();
            end
        end
    end

    return err;
end


Client = Client.exports;



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
-- @return Server
-- @return err
function Server:init( opts )
    local addrs, err = getaddrinfo({
        host = opts.host,
        port = opts.port,
        passive = true
    });

    if not err then
        local nonblock = opts.nonblock == true;
        local sock;

        for _, addr in ipairs( addrs ) do
            sock, err = socket.new( addr, nonblock );
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


Server = Server.exports;



return {
    client = Client,
    server = Server
};


