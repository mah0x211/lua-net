--[[

  Copyright (C) 2016 Masatoshi Teruya

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

  lib/stream/addrinfo.lua
  lua-net
  Created by Masatoshi Teruya on 16/01/20.

--]]

-- assign to local
local llsocket = require('llsocket');
local getaddrinfoInet = llsocket.inet.getaddrinfo;
local getaddrinfoUnix = llsocket.unix.getaddrinfo;

-- constants
local SOCK_STREAM = llsocket.SOCK_STREAM;
local IPPROTO_TCP = llsocket.IPPROTO_TCP;
local AI_PASSIVE = llsocket.AI_PASSIVE;

-- MARK: class Server
local AddrInfo = require('halo').class.AddrInfo;


--- getinet
-- @param opts
--  opts.host
--  opts.port
--  opts.passive
-- @return addrinfos
-- @return err
function AddrInfo.getinet( opts )
    return getaddrinfoInet(
        opts.host, opts.port, SOCK_STREAM, IPPROTO_TCP,
        opts.passive == true and AI_PASSIVE or nil
    );
end


--- getunix
-- @param opts
--  opts.path
--  opts.passive
-- @return addrinfos
-- @return err
function AddrInfo.getunix( opts )
    return getaddrinfoUnix(
        opts.path, SOCK_STREAM, nil, opts.passive == true and AI_PASSIVE or nil
    );
end


return AddrInfo.exports;

