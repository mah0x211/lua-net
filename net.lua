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

-- assign to local
local unpack = unpack or table.unpack;
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
-- @return self
function Socket:init( sock )
    self.sock = sock;
    -- init message queue if non-blocking mode
    if sock:nonblock() then
        self:initq();
    end

    return self;
end


--- initq
function Socket:initq()
    self.msgq, self.msgqhead, self.msgqtail = {}, 1, 0;
end


--- fd
-- @return fd
function Socket:fd()
    return self.sock:fd();
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
-- @return err
function Socket:close()
    local sock = self.sock;

    self.sock = nil;
    if self.msgq then
        self.msgq, self.msgqhead, self.msgqtail = nil, nil, nil;
    end

    return sock:close( SHUT_RDWR );
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
    -- init message queue if non-blocking mode
    if bool and bool == true and not self.msgq then
        self:initq();
    end

    return self.sock:nonblock( bool );
end


--- socktype
-- @return socktype
-- @return err
function Socket:socktype()
    return self.sock:socktype();
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


--- recv
-- @param bufsize
-- @return str
-- @return err
-- @return again
function Socket:recv( bufsize )
    return self.sock:recv( bufsize );
end


--- send
-- @param str
-- @return len number of bytes sent
-- @return err
-- @return again
function Socket:send( str )
    return self.sock:send( str );
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
                fn = self.redqsend,
                len == 0 and str or str:sub( len + 1 )
            };
        end

        return len, err, again;
    end

    -- put str into message queue
    self.msgqtail = self.msgqtail + 1;
    self.msgq[self.msgqtail] = {
        fn = self.redqsend,
        str
    };

    return 0, nil, true;
end


--- redqsend
-- @param args
--  [1] str
-- @return len number of bytes sent or queued
-- @return err
-- @return again
function Socket:redqsend( args )
    local len, err, again = self:send( args[1] );

    -- update message string
    if again and len > 0 then
        args[1] = args[1]:sub( len + 1 );
    end

    return len, err, again;
end


return Socket.exports


