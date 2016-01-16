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
function Socket:tcpintvl( intvl )
    return self.sock:tcpintvl( intvl );
end


--- tcpkeepcnt
-- @param cnt
-- @return cnt
-- @return err
function Socket:tcpkeepcnt( cnt )
    return self.sock:tcpkeepcnt( cnt );
end


Socket = Socket.exports;



-- MARK: class Server
local Server = require('halo').class.Server;


Server.inherits {
    'net.stream.Socket'
};


--- listen
-- @param   backlog
-- @return  err
function Server:listen( backlog )
    return self.sock:listen( backlog );
end


--- accept
-- @return  Socket
-- @return  err
-- @return  again
function Server:accept()
    local sock, err, again = self.sock:accept();

    if sock then
        return Socket.new( sock );
    end

    return nil, err, again;
end


Server = Server.exports;


