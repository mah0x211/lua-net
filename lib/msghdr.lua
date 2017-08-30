--[[

  Copyright (C) 2017 Masatoshi Teruya

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

  lib/msghdr.lua
  lua-net
  Created by Masatoshi Teruya on 17/08/29.

--]]

--- assign to local
local msghdr = require('llsocket').msghdr;
local iovec = require('llsocket').iovec;
local cmsghdr = require('llsocket').cmsghdr;


-- MARK: class MsgHdr
local MsgHdr = require('halo').class.MsgHdr;


--- init
-- @return self
function MsgHdr:init()
    self.msg = msghdr.new();
    return self;
end


--- name
-- @param ai
-- @return ai
function MsgHdr:name( ai )
    return self.msg:name( ai );
end


--- bytes
-- @return bytes
function MsgHdr:bytes()
    local iov = self.iov;

    if iov then
        return iov:bytes();
    end

    return 0;
end


--- consume
-- @param bytes
-- @return bytes
function MsgHdr:consume( bytes )
    local iov = self.iov;

    if iov then
        return iov:consume( bytes );
    end

    return 0;
end


--- concat
-- @return str
function MsgHdr:concat()
    local iov = self.iov;

    if iov then
        return iov:concat();
    end

    return '';
end


--- add
-- @param str
-- @return used
-- @return err
function MsgHdr:add( str )
    local iov = self.iov;
    local err;

    -- create new iovec
    if not iov then
        iov, err = iovec.new();
        if not iov then
            return nil, err;
        end

        self.iov = self.msg:iov( iov );
    end

    return iov:add( str );
end


--- addn
-- @param bytes
-- @return used
-- @return err
function MsgHdr:addn( bytes )
    local iov = self.iov;
    local err;

    -- create new iovec
    if not iov then
        iov, err = iovec.new();
        if not iov then
            return nil, err;
        end

        self.iov = self.msg:iov( iov );
    end

    return iov:addn( bytes );
end


--- get
-- @param idx
-- @return str
function MsgHdr:get( idx )
    local iov = self.iov;

    if iov then
        return iov:get( idx );
    end

    return nil;
end


--- del
-- @param idx
-- @return str
-- @return midx
function MsgHdr:del( idx )
    local iov = self.iov;

    if iov then
        return iov:del( idx );
    end

    return nil;
end


--- socket
-- @param ...
-- @return err
function MsgHdr:socket( ... )
    local args = {...};
    local cmsg = self.cmsg;
    local err;

    -- create new cmsghdr
    if not cmsg then
        -- do nothing
        if args[1] == nil then
            return nil;
        end

        cmsg, err = cmsghdr.new();
        if not cmsg then
            return nil, err;
        end

        self.cmsg = self.msg:control( cmsg );
    -- remove cmsg
    elseif select( '#', ... ) > 0 and args[1] == nil then
        self.cmsg = self.msg:control( nil );
        return nil;
    end

    return cmsg:socket( ... );
end


return MsgHdr.exports;
