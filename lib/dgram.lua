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

  lib/dgram.lua
  lua-net
  Created by Masatoshi Teruya on 15/11/15.

--]]

-- assign to local
local llsocket = require('llsocket');
local socketpair = llsocket.socket.pair;
local getaddrinfoInet = llsocket.inet.getaddrinfo;
local getaddrinfoUnix = llsocket.unix.getaddrinfo;

-- constants
local SOCK_DGRAM = llsocket.SOCK_DGRAM;
local IPPROTO_UDP = llsocket.IPPROTO_UDP;
local AI_PASSIVE = llsocket.AI_PASSIVE;
local AI_CANONNAME = llsocket.AI_CANONNAME;
local AI_NUMERICHOST = llsocket.AI_NUMERICHOST;

-- MARK: class Socket
local Socket = require('halo').class.Socket;


Socket.inherits {
    'net.Socket'
};


--- mcastloop
-- @param bool
-- @return bool
-- @return err
function Socket:mcastloop( bool )
    return self.sock:mcastloop( bool );
end


--- mcastttl
-- @param ttl
-- @return ttl
-- @return err
function Socket:mcastttl( ttl )
    return self.sock:mcastttl( ttl );
end


--- mcastif
-- @param ifname
-- @return ifname
-- @return err
function Socket:mcastif( ifname )
    return self.sock:mcastif( ifname );
end


--- mcastjoin
-- @param mcaddr
-- @param ifname
-- @return err
function Socket:mcastjoin( mcaddr, ifname )
    return self.sock:mcastjoin( mcaddr, ifname );
end


--- mcastleave
-- @param mcaddr
-- @param ifname
-- @return err
function Socket:mcastleave( mcaddr, ifname )
    return self.sock:mcastleave( mcaddr, ifname );
end


--- mcastjoinsrc
-- @param mcaddr
-- @param srcaddr
-- @param ifname
-- @return err
function Socket:mcastjoinsrc( mcaddr, srcaddr, ifname )
    return self.sock:mcastjoinsrc( mcaddr, srcaddr, ifname );
end


--- mcastleavesrc
-- @param mcaddr
-- @param srcaddr
-- @param ifname
-- @return err
function Socket:mcastleavesrc( mcaddr, srcaddr, ifname )
    return self.sock:mcastleavesrc( mcaddr, srcaddr, ifname );
end


--- mcastblocksrc
-- @param mcaddr
-- @param srcaddr
-- @param ifname
-- @return err
function Socket:mcastblocksrc( mcaddr, srcaddr, ifname )
    return self.sock:blocksrc( mcaddr, srcaddr, ifname );
end


--- mcastunblocksrc
-- @param mcaddr
-- @param srcaddr
-- @param ifname
-- @return err
function Socket:mcastunblocksrc( mcaddr, srcaddr, ifname )
    return self.sock:mcastunblocksrc( mcaddr, srcaddr, ifname );
end


--- broadcast
-- @param bool
-- @return bool
-- @return err
function Socket:broadcast( bool )
    return self.sock:broadcast( bool );
end


--- recvfrom
-- @return str
-- @return addrinfo
-- @return err
-- @return again
function Socket:recvfrom()
    return self.sock:recvfrom();
end


--- sendto
-- @param msg
-- @param addrinfo
-- @return len
-- @return err
-- @return again
function Socket:sendto( msg, addrinfo )
    return self.sock:sendto( msg, addrinfo );
end


--- sendqto
-- @param msg
-- @param addrinfo
-- @return len number of bytes sent or queued
-- @return err
-- @return again
function Socket:sendqto( msg, addrinfo )
    return self:sendqvia( self.sock.sendto, msg, addrinfo );
end


--- flushqto
-- @param addrinfo
-- @return  len number of bytes sent
-- @return  err
-- @return  again
function Socket:flushqto( addrinfo )
    return self:flushqvia( self.sock.sendto, addrinfo );
end


Socket = Socket.exports;



--- pair
-- @param opts
--  opts.nonblock
-- @return pair
--  pair[1]
--  pair[2]
-- @return err
local function pair( opts )
    local nonblock = opts and opts.nonblock == true;
    local sp, err = socketpair( SOCK_DGRAM, nonblock );

    if err then
        return nil, err;
    end

    sp[1], sp[2] = Socket.new( sp[1] ), Socket.new( sp[2] );
    -- init message queue if non-blocking mode
    if nonblock then
        sp[1]:initq();
        sp[2]:initq();
    end

    return sp;
end


--- getaddrinfoin
-- @param opts
--  opts.host
--  opts.port
--  opts.passive
--  opts.canonname
--  opts.numeric
-- @return addrinfos
-- @return err
local function getaddrinfoin( opts )
    return getaddrinfoInet(
        opts.host, opts.port, SOCK_DGRAM, IPPROTO_UDP,
        opts.passive == true and AI_PASSIVE or nil,
        opts.canonname == true and AI_CANONNAME or nil,
        opts.numeric == true and AI_NUMERICHOST or nil
    );
end


--- getaddrinfoun
-- @param opts
--  opts.path
-- @return addrinfos
-- @return err
local function getaddrinfoun( opts )
    return getaddrinfoUnix( opts.path, SOCK_DGRAM );
end


return {
    pair = pair,
    getaddrinfoin = getaddrinfoin,
    getaddrinfoun = getaddrinfoun
};


