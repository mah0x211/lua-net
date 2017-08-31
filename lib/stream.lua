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

  lib/stream.lua
  lua-net
  Created by Masatoshi Teruya on 15/11/15.

--]]

-- assign to local
local llsocket = require('llsocket');
local socket = llsocket.socket;
local getaddrinfoInet = llsocket.inet.getaddrinfo;
local getaddrinfoUnix = llsocket.unix.getaddrinfo;
local unpack = table.unpack or unpack;
local pollable = require('net.poll').pollable;
local readable = require('net.poll').readable;
local writable = require('net.poll').writable;
-- constants
local SOCK_STREAM = llsocket.SOCK_STREAM;
local IPPROTO_TCP = llsocket.IPPROTO_TCP;
local AI_PASSIVE = llsocket.AI_PASSIVE;
local AI_CANONNAME = llsocket.AI_CANONNAME;
local AI_NUMERICHOST = llsocket.AI_NUMERICHOST;

-- MARK: class Socket
local Socket = require('halo').class.Socket;


Socket.inherits {
    'net.Socket'
};


--- acceptconn
-- @return bool
-- @return err
function Socket:acceptconn()
    return self.sock:acceptconn();
end


--- oobinline
-- @param bool
-- @return bool
-- @return err
function Socket:oobinline( bool )
    return self.sock:oobinline( bool );
end


--- keepalive
-- @param bool
-- @return bool
-- @return err
function Socket:keepalive( bool )
    return self.sock:keepalive( bool );
end


--- tcpnodelay
-- @param bool
-- @return bool
-- @return err
function Socket:tcpnodelay( bool )
    return self.sock:tcpnodelay( bool );
end


--- tcpcork
-- @param bool
-- @return bool
-- @return err
function Socket:tcpcork( bool )
    return self.sock:tcpcork( bool );
end


--- tcpkeepalive
-- @param sec
-- @return sec
-- @return err
function Socket:tcpkeepalive( idle )
    return self.sock:tcpkeepalive( idle )
end


--- tcpkeepintvl
-- @param sec
-- @return sec
-- @return err
function Socket:tcpkeepintvl( intvl )
    return self.sock:tcpkeepintvl( intvl );
end


--- tcpkeepcnt
-- @param cnt
-- @return cnt
-- @return err
function Socket:tcpkeepcnt( cnt )
    return self.sock:tcpkeepcnt( cnt );
end


--- sendfile
-- @param self
-- @param fd
-- @param bytes
-- @param offset
-- @return len number of bytes sent
-- @return err
-- @return timeout
local function sendfile( self, fd, bytes, offset )
    local sent = 0;
    local sock, fn;

    if self.tls then
        sock, fn = self.tls, self.tls.sendfile;
    else
        sock, fn = self.sock, self.sock.sendfile;
    end

    if not offset then
        offset = 0;
    end

    while true do
        local len, err, again = fn( sock, fd, bytes, offset );

        if not len then
            return nil, err;
        end

        -- update a bytes sent
        sent = sent + len;

        if not again or not self.nonblock then
            return sent, err, again;
        -- wait until writable
        else
            local ok, perr, timeout = writable( self:fd(), self.snddeadl );

            if not ok then
                return sent, perr, timeout;
            end

            bytes = bytes - len;
            offset = offset + len;
        end
    end
end


--- sendfileqred
-- @param self
-- @param args
--  [1] fd
--  [2] bytes
--  [3] offset
--  [4] finalizer
--  [5] ctx
--  [6-N] ...
-- @return len number of bytes sent
-- @return err
-- @return timeout
local function sendfileqred( self, args )
    local len, err, timeout = sendfile( self, args[1], args[2], args[3] );

    -- update bytes and offset
    if timeout then
        args[2] = args[2] - len;
        args[3] = args[3] + len;
    -- call finalizer
    elseif args[4] then
        args[4]( args[5], err, args[1], select( 6, unpack( args ) ) );
    end

    return len, err, timeout;
end


--- sendfile
-- @param fd
-- @param bytes
-- @param offset
-- @param finalizer
--  finalizer( ctx, err, fd, ... )
-- @param ctx
-- @param ...
-- @return len number of bytes sent
-- @return err
-- @return timeout
function Socket:sendfile( fd, bytes, offset, finalizer, ctx, ... )
    if self.msgqtail == 0 then
        local len, err, timeout = sendfile( self, fd, bytes, offset );

        if timeout then
            self:sendfileq( fd, bytes - len, offset + len, finalizer, ctx, ... );
        elseif finalizer then
            finalizer( ctx, err, fd, ... );
        end

        return len, err, timeout;
    end

    -- put into send queue
    self:sendfileq( fd, bytes, offset, finalizer, ctx, ... );

    return self:flushq();
end


--- sendfileq
-- @param fd
-- @param bytes
-- @param offset
-- @param finalizer
--  finalizer( ctx, err, fd, ... )
-- @param ctx
-- @param ...
function Socket:sendfileq( fd, bytes, offset, finalizer, ctx, ... )
    self.msgqtail = self.msgqtail + 1;
    self.msgq[self.msgqtail] = {
        fn = sendfileqred,
        fd,
        bytes,
        offset,
        finalizer,
        ctx,
        ...
    };
end


Socket = Socket.exports;



-- MARK: class Server
local Server = require('halo').class.Server;


Server.inherits {
    'net.stream.Socket'
};


--- listen
-- @param backlog
-- @return err
function Server:listen( backlog )
    return self.sock:listen( backlog );
end


--- accept
-- @return Socket
-- @return err
function Server:accept()
    while true do
        local sock, err, again = self.sock:accept();

        if sock then
            local tls;

            if self.tls then
                tls, err = self.tls:accept_socket( sock:fd() );
                if err then
                    sock:close();
                    return nil, err;
                end
            end

            return Socket.new( sock, self.nonblock, tls );
        elseif not again then
            return nil, err;
        -- wait until readable
        else
            local ok, perr = readable( self:fd() );

            if not ok then
                return nil, perr;
            end
        end
    end
end


Server = Server.exports;


--- getaddrinfoin
-- @param opts
--  opts.host
--  opts.port
--  opts.passive
--  opts.canonname
--  opts.numeric
-- @return addrs
-- @return err
local function getaddrinfoin( opts )
    return getaddrinfoInet(
        opts.host,
        type( opts.port ) == 'number' and tostring( opts.port ) or opts.port,
        SOCK_STREAM, IPPROTO_TCP,
        opts.passive == true and AI_PASSIVE or nil,
        opts.canonname == true and AI_CANONNAME or nil,
        opts.numeric == true and AI_NUMERICHOST or nil
    );
end


--- getaddrinfoun
-- @param opts
--  opts.path
--  opts.passive
-- @return addrs
-- @return err
local function getaddrinfoun( opts )
    return getaddrinfoUnix(
        opts.path, SOCK_STREAM, nil, opts.passive == true and AI_PASSIVE or nil
    );
end


--- wrap
-- @param fd
-- @return Socket
-- @return err
local function wrap( fd )
    local nonblock = pollable();
    local sock, err = socket.wrap( fd );

    if err then
        return nil, err;
    end

    return Socket.new( sock, nonblock );
end



return {
    wrap = wrap,
    getaddrinfoin = getaddrinfoin,
    getaddrinfoun = getaddrinfoun
};


