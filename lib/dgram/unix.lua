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

  lib/dgram/unix.lua
  lua-net
  Created by Masatoshi Teruya on 15/11/15.

--]]

-- assign to local
local getaddrinfo = require('net.dgram.addrinfo').getunix;
local llsocket = require('llsocket');
local socket = llsocket.socket;

-- constants
local SOCK_DGRAM = llsocket.SOCK_DGRAM;

-- MARK: class Unix
local Unix = require('halo').class.Unix;


Unix.inherits {
    'net.dgram.Socket'
};


--- init
-- @param opts
--  opts.path
--  opts.nonblock
-- @return Unix
-- @return err
function Unix:init( opts )
    local addrinfo, err = getaddrinfo( opts );

    if not err then
        local sock;

        sock, err = socket.new( addrinfo, opts.nonblock == true );
        if not err then
            self.sock = sock;
            return self;
        end
    end

    return nil, err;
end


--- connect
-- @param opts
--  opts.path
-- @return err
function Unix:connect( opts )
    if not opts then
        return self.sock:connect();
    else
        local addrinfo, err = getaddrinfo( opts );

        if not err then
            err = self.sock:connect( addrinfo );
        end

        return err;
    end
end


--- bind
-- @param opts
--  opts.path
-- @return err
function Unix:bind( opts )
    if not opts then
        return self.sock:bind();
    else
        local addrinfo, err = getaddrinfo( opts );

        if not err then
            err = sock:bind( addrinfo );
        end

        return err;
    end
end



return Unix.exports;