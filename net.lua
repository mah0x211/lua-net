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
function Socket:init( sock )
    self.sock = sock;

    return self;
end


--- fd
-- @return  fd
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
-- @return  err
function Socket:closer()
    return self.sock:shutdown( SHUT_RD );
end


--- closew
-- @return  err
function Socket:closew()
    return self.sock:shutdown( SHUT_WR );
end


--- close
-- @param   opt [net.shut.RD, net.shut.WR, net.shut.RDWR]
-- @return  err
function Socket:close()
    local sock;

    sock, self.sock = self.sock, nil;

    return sock:close( SHUT_RDWR );
end


--- atmark
-- @return bool
-- @return err
function Socket:atmark()
    return self.sock:atmark();
end


--- cloexec
-- @param  bool
-- @return bool
-- @return err
function Socket:cloexec( bool )
    return self.sock:cloexec( bool );
end


--- nonblock
-- @param  bool
-- @return bool
-- @return err
function Socket:nonblock( bool )
    return self.sock:nonblock( bool );
end


--- type
-- @return socktype
-- @return err
function Socket:type()
    return self.sock:type();
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
-- @return  str
-- @return  err 
-- @return  again
function Socket:recv( bufsize )
    return self.sock:recv( bufsize );
end


--- send
-- @return  len number of bytes sent
-- @return  err
-- @return  again
function Socket:send( str )
    return self.sock:send( str );
end


--- recvy
-- @return  str data
-- @return  err
function Socket:recvy( bufsize )
    local data, err, again = self:recv( bufsize );

    while again do
        yield();
        data, err, again = self:recv( bufsize );
    end

    return data, err;
end


--- sendy
-- @return  len number of bytes snt
-- @return  err
function Socket:sendy( str )
    local len, err, again = self:send( str );
    
    -- no space of send buffer
    if again then
        yield();
        len, err, again = self:send( str );
    end

    return len, err;
end



return Socket.exports


