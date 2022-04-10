--
-- Copyright (C) 2017-2022 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- lib/tls/unix.lua
-- lua-net
-- Created by Masatoshi Teruya on 17/09/05.
--
--- @class net.tls.unix.Socket : net.unix.Socket, net.tls.Socket
local Socket = {}

--- sendfd
--- @return integer? len
--- @return string err
--- @return boolean? timeout
function Socket:sendfd()
    -- currently, does not support sendfd on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, 'Operation not supported on socket'
end

--- recvfd
--- @return integer? fd
--- @return string? err
--- @return boolean? timeout
function Socket:recvfd()
    -- currently, does not support recvmsg on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, 'Operation not supported on socket'
end

require('metamodule').new.Socket(Socket, 'net.unix.Socket', 'net.tls.Socket')

