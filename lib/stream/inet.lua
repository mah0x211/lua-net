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
--  opts.nodelay
-- @param connect
-- @return Client
-- @return err
-- @return again
function Client:init( opts, connect )
    local again;

    self.opts = {
        host = opts.host,
        port = opts.port,
        nonblock = opts.nonblock == true,
        nodelay = opts.nodelay == true
    };

    if connect ~= false then
        local err;

        err, again = self:connect();
        if err then
            return nil, err;
        end
    end

    return self, nil, again;
end


--- connect
-- @return err
-- @return again
function Client:connect()
    local addrs, err = getaddrinfo( self.opts );
    local sock;

    if err then
        return err;
    end

    for _, addr in ipairs( addrs ) do
        sock, err = socket.new( addr, self.opts.nonblock );
        if not err then
            local again;

            err, again = sock:connect();
            if err then
                -- close failed
                sock:close();
                return err;
            -- set tcpnodelay option
            elseif self.opts.nodelay then
                err = select( 2, sock:tcpnodelay( true ) );
                if err then
                    -- close failed
                    sock:close();
                    return err;
                end
            end

            -- close current socket
            if self.sock then
                self:close();
            end
            self.sock = sock;

            -- init message queue if non-blocking mode
            if self.opts.nonblock then
                self:initq();
            end

            return nil, again;
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
    local addrs, sock, nonblock, err;

    addrs, err = getaddrinfo({
        host = opts.host,
        port = opts.port,
        passive = true
    });
    if err then
        return nil, err;
    end

    nonblock = opts.nonblock == true;
    for _, addr in ipairs( addrs ) do
        sock, err = socket.new( addr, nonblock );
        if not err then
            -- enable reuseaddr
            if opts.reuseaddr == true then
                local ok;

                ok, err = sock:reuseaddr( true );
                if not ok then
                    sock:close();
                    return nil, err;
                end
            end

            -- bind
            err = sock:bind();
            if err then
                sock:close();
                return nil, err;
            end

            self.sock = sock;

            return self;
        end
    end

    return nil, err;
end


Server = Server.exports;



return {
    client = Client,
    server = Server
};


