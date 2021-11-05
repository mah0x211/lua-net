--
-- Copyright (C) 2015 Masatoshi Teruya
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
-- lib/dgram/unix.lua
-- lua-net
-- Created by Masatoshi Teruya on 15/11/15.
--
-- assign to local
local new_unix_dgram_ai = require('net.addrinfo').new_unix_dgram
local socket = require('net.socket')
local socket_new_unix_dgram = socket.new_unix_dgram
local socket_pair_dgram = socket.pair_dgram
local socket_wrap = socket.wrap

--- @class net.dgram.unix.Socket : net.dgram.Socket, net.unix.Socket
local Socket = {}

--- connect
--- @param pathname string
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
--- @return llsocket.addrinfo? ai
function Socket:connect(pathname)
    local ai, err = new_unix_dgram_ai(pathname)
    if err then
        return false, err
    end

    local ok, cerr, timeout = self.sock:connect(ai)
    if not ok then
        return false, cerr, timeout
    end

    return true, nil, nil, ai
end

--- bind
--- @param pathname string
--- @return boolean ok
--- @return string? err
--- @return llsocket.addrinfo? ai
function Socket:bind(pathname)
    local ai, err = new_unix_dgram_ai(pathname, true)

    if err then
        return false, err
    end

    local ok, berr = self.sock:bind(ai)
    if not ok then
        return false, berr
    end

    return true, nil, ai
end

Socket = require('metamodule').new.Socket(Socket, 'net.dgram.Socket',
                                          'net.unix.Socket')

--- new
--- @return net.dgram.unix.Socket? sock
--- @return string? err
local function new()
    local sock, err, nonblock = socket_new_unix_dgram()

    if err then
        return nil, err
    end

    return Socket(sock, nonblock)
end

--- pair
--- @return net.dgram.unix.Socket[] pair
--- @return string? err
local function pair()
    local sp, err, nonblock = socket_pair_dgram()

    if err then
        return nil, err
    end

    sp[1], err = Socket(sp[1], nonblock)
    if err then
        return nil, err
    end

    sp[2], err = Socket(sp[2], nonblock)
    if err then
        return nil, err
    end

    return sp
end

--- wrap
--- @param fd integer
--- @return net.dgram.unix.Socket sock
--- @return string? err
local function wrap(fd)
    local sock, err, nonblock = socket_wrap(fd)

    if err then
        return nil, err
    end

    return Socket(sock, nonblock)
end

return {
    wrap = wrap,
    pair = pair,
    new = new,
}
