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

  lib/stream/pair.lua
  lua-net
  Created by Masatoshi Teruya on 15/12/10.

--]]

-- assign to local
local llsocket = require('llsocket');
local socketpair = llsocket.socket.pair;
-- constants
local SOCK_STREAM = llsocket.SOCK_STREAM;

-- MARK: class Socket
local Socket = require('halo').class.Socket;

Socket.inherits {
    'net.stream.Socket'
};

Socket = Socket.exports;


--- init
-- @param opts
--  opts.nonblock
-- @return pair
--  pair[1]
--  pair[2]
-- @return err
local function new( opts )
    local sp, err = socketpair(
        SOCK_STREAM, opts and opts.nonblock == true
    );

    if err then
        return nil, err;
    end

    sp[1], sp[2] = Socket.new( sp[1] ), Socket.new( sp[2] );

    return sp;
end


return {
    new = new
};

