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
local socketpair = llsocket.socket.pair;
local getaddrinfoInet = llsocket.inet.getaddrinfo;
local getaddrinfoUnix = llsocket.unix.getaddrinfo;
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
-- @param fd
-- @param bytes
-- @param offset
-- @return len number of bytes sent
-- @return err
-- @return again
function Socket:sendfile( fd, bytes, offset  )
    return self.sock:sendfile( fd, bytes, offset );
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
-- @return again
function Server:accept()
    local sock, err, again = self.sock:accept();

    if sock then
        return Socket.new( sock );
    end

    return nil, err, again;
end


Server = Server.exports;


--- pair
-- @param opts
--  opts.nonblock
-- @return pair
--  pair[1]
--  pair[2]
-- @return err
local function pair( opts )
    local nonblock = opts and opts.nonblock == true;
    local sp, err = socketpair( SOCK_STREAM, nonblock );

    if err then
        return nil, err;
    end

    sp[1], sp[2] = Socket.new( sp[1] ), Socket.new( sp[2] );

    return sp;
end



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
        opts.host, opts.port, SOCK_STREAM, IPPROTO_TCP,
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


return {
    pair = pair,
    getaddrinfoin = getaddrinfoin,
    getaddrinfoun = getaddrinfoun
};


