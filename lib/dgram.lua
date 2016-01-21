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


Socket = Socket.exports;



