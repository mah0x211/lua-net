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

  lib/stream/unix.lua
  lua-net
  Created by Masatoshi Teruya on 16/05/16.

--]]

-- assign to local
local pollable = require('net.poll').pollable;
local writable = require('net.poll').writable;
local getaddrinfo = require('net.stream').getaddrinfoun;
local libtls = require('libtls');
local llsocket = require('llsocket');
local socket = llsocket.socket;

-- MARK: class Client
local Client = require('halo').class.Client;


Client.inherits {
    'net.stream.Socket'
};


--- init
-- @param opts
--  opts.path
--  opts.tlscfg
--  opts.servername
-- @param connect
-- @return Client
-- @return err
function Client:init( opts, connect )
    local again;

    self.opts = {
        path = opts.path,
        tlscfg = opts.tlscfg,
        servername = opts.servername
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
    local tls, addr, sock, again, ok, err;

    -- create tls client context
    if self.opts.tlscfg then
        tls, err = libtls.client( self.opts.tlscfg );
        if err then
            return err;
        end
    end

    addr, err = getaddrinfo( self.opts );
    if err then
        return err;
    end

    sock, err = socket.new( addr, pollable() );
    if err then
        return err;
    end

    err, again = sock:connect();
    -- wait until writable
    if again then
        local perr, timeout;

        again = nil;
        ok, perr, timeout = writable( sock:fd(), self.snddeadl );
        if ok then
            -- check errno
            perr, err = sock:error();
            if not err and perr ~= 0 then
                err = perr;
            end
        elseif timeout then
            err = 'Operation timed out';
        else
            err = perr;
        end
    end

    if err then
        sock:close();
        return err;
    end

    if tls then
        ok, err = tls:connect_socket( sock:fd(), self.opts.servername );
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
    self.tls = tls;
    -- init message queue
    self:initq();

    return nil, again;
end


Client = Client.exports;



-- MARK: class Server
local Server = require('halo').class.Server;


Server.inherits {
    'net.stream.Server'
};


--- init
-- @param opts
--  opts.path
--  opts.tlscfg
-- @return Server
-- @return err
function Server:init( opts )
    local tls, addr, sock, err;

    -- create tls server context
    if opts.tlscfg then
        tls, err = libtls.server( opts.tlscfg );
        if err then
            return nil, err;
        end
    end

    addr, err = getaddrinfo({
        path = opts.path,
        passive = true
    });
    if err then
        return nil, err;
    end

    sock, err = socket.new( addr, pollable() );
    if err then
        return nil, err;
    end

    -- bind
    err = sock:bind();
    if err then
        sock:close();
        return nil, err;
    end

    self.sock = sock;
    self.tls = tls;
    self.tlscfg = opts.tlscfg;

    return self;
end


Server = Server.exports;


return {
    client = Client,
    server = Server
}

