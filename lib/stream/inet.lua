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
local pollable = require('net.poll').pollable;
local waitsend = require('net.poll').waitsend;
local getaddrinfo = require('net.stream').getaddrinfoin;
local libtls = require('libtls');
local socket = require('llsocket.socket');


-- MARK: class Client
local Client = require('halo').class.Client;


Client.inherits {
    'net.stream.Socket'
};


--- init
-- @param opts
--  opts.host
--  opts.port
--  opts.tcpnodelay
--  opts.tlscfg
--  opts.servername
-- @param connect
-- @return Client
-- @return err
function Client:init( opts, connect )
    self.opts = {
        host = opts.host,
        port = opts.port,
        tcpnodelay = opts.tcpnodelay == true or pollable() == true,
        tlscfg = opts.tlscfg,
        servername = opts.servername or opts.host
    };

    -- create tls client context
    if opts.tlscfg then
        local err;

        self.tls, err = libtls.client( opts.tlscfg );
        if err then
            return nil, err;
        end
    end

    if connect ~= false then
        local err = self:connect();

        if err then
            return nil, err;
        end
    end

    return self;
end


--- connect
-- @return err
-- @return timeout
function Client:connect()
    local nonblock = pollable();
    local addrs, err = getaddrinfo( self.opts );
    local sock;

    if err then
        return err;
    end

    for _, addr in ipairs( addrs ) do
        sock, err = socket.new( addr, nonblock );
        if not err then
            local again, ok;

            err, again = sock:connect();
            -- wait until writable
            if again then
                local perr;

                ok, perr, again = waitsend( sock:fd(), self.snddeadl );
                if ok then
                    -- check errno
                    perr, err = sock:error();
                    if not err and perr ~= 0 then
                        err = perr;
                    end
                elseif again then
                    err = 'Operation timed out';
                else
                    err = perr;
                end
            end

            if err then
                -- close failed
                sock:close();
                return err;
            -- set tcpnodelay option
            elseif self.opts.tcpnodelay == true then
                err = select( 2, sock:tcpnodelay( true ) );
                if err then
                    -- close failed
                    sock:close();
                    return err;
                end
            end

            -- connect a tls connection
            if self.tls then
                ok, err = self.tls:connect_socket( sock:fd(), self.opts.servername );
                if not ok then
                    sock:close();
                    return err;
                end
            end

            -- close current socket
            if self.sock then
                self:close();
            end
            self.sock = sock;
            self.nonblock = nonblock;

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
--  opts.reuseaddr
--  opts.reuseport
--  opts.tcpnodelay
--  opts.tlscfg
-- @return Server
-- @return err
function Server:init( opts )
    local nonblock = pollable();
    local tls, addrs, sock, ok, err;

    -- create tls server context
    if opts.tlscfg then
        tls, err = libtls.server( opts.tlscfg );
        if err then
            return nil, err;
        end
    end

    addrs, err = getaddrinfo({
        host = opts.host,
        port = opts.port,
        passive = true
    });
    if err then
        return nil, err;
    end

    for _, addr in ipairs( addrs ) do
        sock, err = socket.new( addr, nonblock );
        if not err then
            -- enable reuseaddr
            if opts.reuseaddr == nil or opts.reuseaddr == true then
                ok, err = sock:reuseaddr( true );
                if not ok then
                    sock:close();
                    return nil, err;
                end
            end

            -- enable reuseport
            if opts.reuseport == true then
                ok, err = sock:reuseport( true );
                if not ok then
                    sock:close();
                    return nil, err;
                end
            end

            -- enable tcpnodelay
            if opts.tcpnodelay == true or pollable() == true then
                ok, err = sock:tcpnodelay( true );
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
            self.nonblock = nonblock;
            self.tls = tls;
            self.tlscfg = opts.tlscfg;

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


