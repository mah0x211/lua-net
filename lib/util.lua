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
  
  
  util.lua
  lua-net
  Created by Masatoshi Teruya on 14/05/24.
  
--]]
-- constants
local SOCK_STREAM = require('llsocket').opt.SOCK_STREAM;
local SOCK_DGRAM = require('llsocket').opt.SOCK_DGRAM;
local SOCK_SEQPACKET = require('llsocket').opt.SOCK_SEQPACKET;
local SOCK_RAW = require('llsocket').opt.SOCK_RAW;

-- internal functions
local function setSockInet( self, host, port )
    self.sock = {
        host = host,
        port = port
    };
end

local function setSockUnix( self, path )
    self.sock = {
        path = path
    };
end


-- class
local Util = require('halo').class.Util;

Util:property {
    public = {
        opts = {}
    }
};


function Util:checkInit( socktype, family, opts, ... )
    local t,opt;
    
    -- check family and set arguments
    if family == 'inet' then
        setSockInet( self, ... );
    elseif family == 'unix' then
        setSockUnix( self, ... );
    else
        error( ('unsupported protocol family: %q'):format( family ), 3 );
    end
    -- set family
    self.sock.family = family;
    
    -- check socktype
    if socktype ~= SOCK_STREAM and
       socktype ~= SOCK_DGRAM and
       socktype ~= SOCK_SEQPACKET and
       socktype ~= SOCK_RAW then
       error( ('unsupported socktype: %q'):format( socktype ), 3 );
    end
    -- set socktype
    self.sock.type = socktype;
    
    -- check options
    opts = opts or {};
    for k,v in pairs( self.opts ) do
        opt = opts[k];
        if opt then
            t = type( v );
            if type( opt ) ~= t then
                error( ('option %q must be type of %s'):format( k, t ), 3 );
            end
            rawset( self.opts, k, opt );
        end
    end
end


return Util.exports;
