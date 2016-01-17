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

-- MARK: class Socket
local Socket = require('halo').class.Socket;


Socket.inherits {
    'net.Socket'
};


--- addmembership
-- @param mcaddr
-- @param ifaddr
-- @return bool
-- @return err
function Socket:addmembership( mcaddr, ifaddr )
    return self.sock:addmembership( mcaddr, ifaddr );
end


--- dropmembership
-- @param mcaddr
-- @param ifaddr
-- @return bool
-- @return err
function Socket:dropmembership( mcaddr, ifaddr )
    return self.sock:dropmembership( mcaddr, ifaddr );
end


--- addsrcmembership
-- @param mcaddr
-- @param srcaddr
-- @param ifaddr
-- @return bool
-- @return err
function Socket:addsrcmembership( mcaddr, srcaddr, ifaddr )
    return self.sock:addsrcmembership( mcaddr, srcaddr, ifaddr );
end


--- dropsrcmembership
-- @param mcaddr
-- @param srcaddr
-- @param ifaddr
-- @return bool
-- @return err
function Socket:dropsrcmembership( mcaddr, srcaddr, ifaddr )
    return self.sock:dropsrcmembership( mcaddr, srcaddr, ifaddr );
end


--- blocksrc
-- @param mcaddr
-- @param srcaddr
-- @param ifaddr
-- @return bool
-- @return err
function Socket:blocksrc( mcaddr, srcaddr, ifaddr )
    return self.sock:blocksrc( mcaddr, srcaddr, ifaddr );
end


--- unblocksrc
-- @param mcaddr
-- @param srcaddr
-- @param ifaddr
-- @return bool
-- @return err
function Socket:unblocksrc( mcaddr, srcaddr, ifaddr )
    return self.sock:unblocksrc( mcaddr, srcaddr, ifaddr );
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


Socket = Socket.exports;



