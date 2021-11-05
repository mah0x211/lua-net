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
-- lib/dgram/inet.lua
-- lua-net
-- Created by Masatoshi Teruya on 15/11/15.
--
-- assign to local
local assert = assert
local type = type
local is_uint = require('isa').uint
local getaddrinfo_dgram = require('net.addrinfo').getaddrinfo_dgram
local socket = require('net.socket')
local socket_new_inet_dgram = socket.new_inet_dgram
local socket_wrap = socket.wrap

--- @class net.dgram.inet.Socket : net.dgram.Socket
local Socket = {}

--- connect
--- @param host string
--- @param port string|integer
--- @param conndeadl? integer
--- @return boolean ok
--- @return string? err
--- @return boolean? timeout
--- @return llsocket.addrinfo? ai
function Socket:connect(host, port, conndeadl)
    assert(conndeadl == nil or is_uint(conndeadl), 'conndeadl must be uint')
    local addrs, err = getaddrinfo_dgram(host, port)

    if err then
        return false, err
    end

    local ok, timeout
    for _, ai in ipairs(addrs) do
        ok, err, timeout = self.sock:connect(ai)
        if ok then
            return true, nil, nil, ai
        end
    end

    return false, err, timeout
end

--- bind
--- @param host string
--- @param port string|integer
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return boolean ok
--- @return string? err
--- @return llsocket.addrinfo? ai
function Socket:bind(host, port, reuseaddr, reuseport)
    assert(reuseaddr == nil or type(reuseaddr) == 'boolean',
           'reuseaddr must be boolean')
    assert(reuseport == nil or type(reuseport) == 'boolean',
           'reuseport must be boolean')

    if reuseaddr then
        local _, err = self.sock:reuseaddr(true)
        if err then
            return false, err
        end
    end

    if reuseport then
        local _, err = self.sock:reuseport(true)
        if err then
            return false, err
        end
    end

    local addrs, err = getaddrinfo_dgram(host, port, true)
    if err then
        return false, err
    end

    local ok
    for _, ai in ipairs(addrs) do
        ok, err = self.sock:bind(ai)
        if ok then
            return true, nil, ai
        end
    end

    return false, err
end

Socket = require('metamodule').new.Socket(Socket, 'net.dgram.Socket')

--- new
--- @return net.dgram.inet.Socket sock
--- @return string? err
local function new()
    local sock, err, nonblock = socket_new_inet_dgram()

    if err then
        return nil, err
    end

    return Socket(sock, nonblock)
end

--- wrap
--- @param fd integer
--- @return net.dgram.inet.Socket? sock
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
    new = new,
}
