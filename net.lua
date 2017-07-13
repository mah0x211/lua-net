--[[

  Copyright (C) 2014 Masatoshi Teruya

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


  net.lua
  lua-net
  Created by Masatoshi Teruya on 14/05/16.

--]]

--- assign to local
local pollable = require('net.poll').pollable;
local readable = require('net.poll').readable;
local writable = require('net.poll').writable;
-- constants
local SHUT_RD = require('llsocket').SHUT_RD;
local SHUT_WR = require('llsocket').SHUT_WR;
local SHUT_RDWR = require('llsocket').SHUT_RDWR;


-- MARK: class Socket
local Socket = require('halo').class.Socket;


--[[
function Socket:__newindex( prop )
    error( ('attempt to access unknown property: %q'):format( prop ), 2 );
end
--]]


--- init
-- @param sock
-- @param tls
-- @return self
function Socket:init( sock, tls )
    self.sock = sock;
    self.tls = tls;
    -- init message queue if non-blocking mode
    self:initq();

    return self;
end


--- initq
function Socket:initq()
    self.msgq, self.msgqhead, self.msgqtail = {}, 1, 0;
end


--- sendqlen
-- @return len
function Socket:sendqlen()
    if self.msgqtail == 0 then
        return 0;
    end

    return self.msgqtail - self.msgqhead + 1;
end


--- fd
-- @return fd
function Socket:fd()
    return self.sock:fd();
end


--- family
-- @return af
function Socket:family()
    return self.sock:family();
end


--- sockname
-- @return addr
-- @return err
function Socket:getsockname()
    return self.sock:getsockname();
end


--- peername
-- @return addr
-- @return err
function Socket:getpeername()
    return self.sock:getpeername();
end


--- closer
-- @return err
function Socket:closer()
    return self.sock:shutdown( SHUT_RD );
end


--- closew
-- @return err
function Socket:closew()
    return self.sock:shutdown( SHUT_WR );
end


--- close
-- @param shutrd
-- @param shutwr
-- @return err
function Socket:close( shutrd, shutwr )
    local sock = self.sock;
    local tls = self.tls;

    self.sock = nil;
    self.tls = nil;
    self.msgq, self.msgqhead, self.msgqtail = nil, nil, nil;

    if tls then
        return tls:close();
    elseif shutrd == true and shutwr == true then
        return sock:close( SHUT_RDWR );
    elseif shutrd == true then
        return sock:close( SHUT_RD );
    elseif shutwr == true then
        return sock:close( SHUT_WR );
    end

    return sock:close();
end


--- atmark
-- @return bool
-- @return err
function Socket:atmark()
    return self.sock:atmark();
end


--- cloexec
-- @param bool
-- @return bool
-- @return err
function Socket:cloexec( bool )
    return self.sock:cloexec( bool );
end


--- nonblock
-- @param bool
-- @return bool
-- @return err
function Socket:nonblock( bool )
    return self.sock:nonblock( bool );
end


--- socktype
-- @return socktype
-- @return err
function Socket:socktype()
    return self.sock:socktype();
end


--- protocol
-- @return proto
function Socket:protocol()
    return self.sock:protocol();
end


--- error
-- @return errno
-- @return err
function Socket:error()
    return self.sock:error();
end


--- reuseport
-- @param bool
-- @return bool
-- @return err
function Socket:reuseport( bool )
    return self.sock:reuseport( bool );
end


--- reuseaddr
-- @param bool
-- @return bool
-- @return err
function Socket:reuseaddr( bool )
    return self.sock:reuseaddr( bool );
end


--- debug
-- @param bool
-- @return bool
-- @return err
function Socket:debug( bool )
    return self.sock:debug( bool );
end


--- dontroute
-- @param bool
-- @return bool
-- @return err
function Socket:dontroute( bool )
    return self.sock:dontroute( bool );
end


--- timestamp
-- @param bool
-- @return bool
-- @return err
function Socket:timestamp( bool )
    return self.sock:timestamp( bool );
end


--- rcvbuf
-- @param bytes
-- @return bytes
-- @return err
function Socket:rcvbuf( bytes )
    return self.sock:rcvbuf( bytes );
end


--- rcvlowat
-- @param bytes
-- @return bytes
-- @return err
function Socket:rcvlowat( bytes )
    return self.sock:rcvlowat( bytes );
end


--- sndbuf
-- @param bytes
-- @return bytes
-- @return err
function Socket:sndbuf( bytes )
    return self.sock:sndbuf( bytes );
end


--- sndlowat
-- @param bytes
-- @return bytes
-- @return err
function Socket:sndlowat( bytes )
    return self.sock:sndlowat( bytes );
end


--- rcvtimeo
-- @param sec
-- @return sec
-- @return err
function Socket:rcvtimeo( sec )
    return self.sock:rcvtimeo( sec );
end


--- sndtimeo
-- @param sec
-- @return sec
-- @return err
function Socket:sndtimeo( sec )
    return self.sock:sndtimeo( sec );
end


--- linger
-- @param sec
-- @return sec
-- @return err
function Socket:linger( sec )
    return self.sock:linger( sec );
end


--- recv
-- @param bufsize
-- @return str
-- @return err
-- @return again
function Socket:recv( bufsize )
    local sock, fn;

    if self.tls then
        sock, fn = self.tls, self.tls.read;
    else
        sock, fn = self.sock, self.sock.recv;
    end

    while true do
        local str, err, again = fn( sock, bufsize );

        if not again or not pollable() then
            return str, err, again;
        else
            local ok, perr, timeout = readable( self:fd(), self.rcvdeadl );

            if not ok then
                return nil, perr, timeout;
            end
        end
    end
end


--- send
-- @param str
-- @return len number of bytes sent
-- @return err
-- @return again
function Socket:send( str )
    local sent = 0;
    local sock, fn;

    if self.tls then
        sock, fn = self.tls, self.tls.write;
    else
        sock, fn = self.sock, self.sock.send;
    end

    while true do
        local len, err, again = fn( sock, str );

        if not len then
            return nil, err;
        end

        -- update a bytes sent
        sent = sent + len;

        if not again or not pollable() then
            return sent, err, again;
        else
            local ok, perr, timeout = writable( self:fd(), self.snddeadl );

            if not ok then
                return sent, perr, timeout;
            end

            str = str:sub( len + 1 );
        end
    end
end


--- flushq
-- @return len number of bytes sent
-- @return err
-- @return again
function Socket:flushq()
    -- has queued messages
    if self.msgqtail > 0 then
        local msgq, head, tail = self.msgq, self.msgqhead, self.msgqtail;
        local bytes = 0;
        local len, err, again;

        for i = head, tail do
            len, err, again = msgq[i].fn( self, msgq[i] );

            -- send buffer is full
            if again then
                self.msgqhead = i;
                return bytes + len, nil, true;
            -- got error
            elseif err then
                return nil, err;
            -- closed by peer
            elseif not len then
                return;
            end

            -- update a number of bytes sent
            bytes = bytes + len;
            -- remove sent message
            msgq[i] = nil;
        end

        -- reset message queue head and tail
        self.msgqhead, self.msgqtail = 1, 0;

        return bytes;
    end

    return 0;
end


--- sendq
-- @param str
-- @return len number of bytes sent or queued
-- @return err
-- @return again
function Socket:sendq( str )
    if self.msgqtail == 0 then
        local len, err, again = self:send( str );

        if again then
            self.msgqtail = 1;
            self.msgq[1] = {
                fn = self.sendqred,
                len == 0 and str or str:sub( len + 1 )
            };
        end

        return len, err, again;
    end

    -- put str into message queue
    self.msgqtail = self.msgqtail + 1;
    self.msgq[self.msgqtail] = {
        fn = self.sendqred,
        str
    };

    return self:flushq();
end


--- sendqred
-- @param args
--  [1] str
-- @return len number of bytes sent or queued
-- @return err
-- @return again
function Socket:sendqred( args )
    local len, err, again = self:send( args[1] );

    -- update message string
    if again and len > 0 then
        args[1] = args[1]:sub( len + 1 );
    end

    return len, err, again;
end


return Socket.exports;


