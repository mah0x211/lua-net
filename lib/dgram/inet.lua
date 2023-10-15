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
local ipairs = ipairs
local getaddrinfo_dgram = require('net.addrinfo').getaddrinfo_dgram
local socket = require('net.socket')
local socket_new_inet_dgram = socket.new_inet_dgram
local socket_wrap = socket.wrap

--- @class net.dgram.inet.Socket : net.dgram.Socket
local Socket = {}

--- connect
--- @param host string
--- @param port string|integer
--- @return boolean ok
--- @return any err
--- @return addrinfo? ai
function Socket:connect(host, port)
    local addrs, err = getaddrinfo_dgram(host, port)
    if err then
        return false, err
    end

    local ok
    for _, ai in ipairs(addrs) do
        ok, err = self.sock:connect(ai)
        if ok then
            return true, nil, ai
        end
    end

    return false, err
end

--- bind
--- @param host string
--- @param port string|integer
--- @param opts table<string, any>?
--- @return boolean ok
--- @return any err
--- @return addrinfo? ai
function Socket:bind(host, port, opts)
    if opts == nil then
        opts = {}
    else
        assert(type(opts) == 'table', 'opts must be table')
        assert(opts.reuseaddr == nil or type(opts.reuseaddr) == 'boolean',
               'opts.reuseaddr must be boolean')
        assert(opts.reuseport == nil or type(opts.reuseport) == 'boolean',
               'opts.reuseport must be boolean')
    end

    if opts.reuseaddr then
        local _, err = self.sock:reuseaddr(true)
        if err then
            return false, err
        end
    end

    if opts.reuseport then
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
--- @return any err
local function new()
    local sock, err = socket_new_inet_dgram()

    if err then
        return nil, err
    end

    return Socket(sock)
end

--- wrap
--- @param fd integer
--- @return net.dgram.inet.Socket? sock
--- @return any err
local function wrap(fd)
    local sock, err = socket_wrap(fd)

    if err then
        return nil, err
    end

    return Socket(sock)
end

return {
    wrap = wrap,
    new = new,
}
