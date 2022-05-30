--
-- Copyright (C) 2021 Masatoshi Fukunaga
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
-- assign to local
local type = type
local tostring = tostring
local find = string.find
local llsocket = require('llsocket')
local addrinfo_getaddrinfo = llsocket.addrinfo.getaddrinfo
local addrinfo_inet = llsocket.addrinfo.inet
local addrinfo_unix = llsocket.addrinfo.unix
-- constants
local SOCK_STREAM = llsocket.SOCK_STREAM
local SOCK_DGRAM = llsocket.SOCK_DGRAM
local IPPROTO_TCP = llsocket.IPPROTO_TCP
local IPPROTO_UDP = llsocket.IPPROTO_UDP
local AF_INET = llsocket.AF_INET
local AI_PASSIVE = llsocket.AI_PASSIVE
local AI_CANONNAME = llsocket.AI_CANONNAME
local AI_NUMERICHOST = llsocket.AI_NUMERICHOST

--- getaddrinfo
--- @param host? string
--- @param port? string|integer
--- @param socktype integer
--- @param protocol integer
--- @param passive? boolean
--- @param canonname? boolean
--- @return llsocket.addrinfo[]? ai
--- @return string? err
local function getaddrinfo(host, port, socktype, protocol, passive, canonname)
    if passive ~= nil and type(passive) ~= 'boolean' then
        error('passive must be boolean', 2)
    elseif canonname ~= nil and type(canonname) ~= 'boolean' then
        error('canonname must be boolean', 2)
    end

    local numerichost = type(host) == 'string' and
                            find(host, '^%d+%.%d+%.%d+%.%d+$') and
                            AI_NUMERICHOST or nil

    return addrinfo_getaddrinfo(host,
                                type(port) == 'number' and tostring(port) or
                                    port, AF_INET, socktype, protocol,
                                passive and AI_PASSIVE or nil,
                                canonname and AI_CANONNAME or nil, numerichost)
end

--- getaddrinfo_dgram
--- @param host? string
--- @param port? string|integer
--- @param passive? boolean
--- @param canonname? boolean
--- @return llsocket.addrinfo[]? ai
--- @return string? err
local function getaddrinfo_dgram(host, port, passive, canonname)
    return getaddrinfo(host, port, SOCK_DGRAM, IPPROTO_UDP, passive, canonname)
end

--- getaddrinfo_stream
--- @param host? string
--- @param port? string|integer
--- @param passive? boolean
--- @param canonname? boolean
--- @return llsocket.addrinfo[]? ai
--- @return string? err
local function getaddrinfo_stream(host, port, passive, canonname)
    return getaddrinfo(host, port, SOCK_STREAM, IPPROTO_TCP, passive, canonname)
end

--- new_inet
--- @param host? string
--- @param port? string|integer
--- @param socktype integer
--- @param protocol integer
--- @param passive? boolean
--- @return llsocket.addrinfo? ai
--- @return string? err
local function new_inet(host, port, socktype, protocol, passive)
    if passive ~= nil and type(passive) ~= 'boolean' then
        error('passive must be boolean', 2)
    end

    return addrinfo_inet(host, port, socktype, protocol,
                         passive and AI_PASSIVE or nil)
end

--- new_inet_stream
--- @param host? string
--- @param port? string|integer
--- @param passive? boolean
--- @return llsocket.addrinfo? ai
--- @return string? err
local function new_inet_stream(host, port, passive)
    return new_inet(host, port, SOCK_STREAM, IPPROTO_TCP, passive)
end

--- new_inet_dgram
--- @param host? string
--- @param port? string|integer
--- @param passive? boolean
--- @return llsocket.addrinfo? ai
--- @return string? err
local function new_inet_dgram(host, port, passive)
    return new_inet(host, port, SOCK_DGRAM, IPPROTO_UDP, passive)
end

--- new_unix
--- @param pathname string
--- @param socktype integer
--- @param protocol integer
--- @param passive? boolean
--- @return llsocket.addrinfo? ai
--- @return string? err
local function new_unix(pathname, socktype, protocol, passive)
    if passive ~= nil and type(passive) ~= 'boolean' then
        error('passive must be boolean', 2)
    end

    return addrinfo_unix(pathname, socktype, protocol,
                         passive and AI_PASSIVE or nil)
end

--- new_unix_stream
--- @param pathname string
--- @param passive? boolean
--- @return llsocket.addrinfo? ai
--- @return string? err
local function new_unix_stream(pathname, passive)
    return new_unix(pathname, SOCK_STREAM, 0, passive)
end

--- new_unix_dgram
--- @param pathname string
--- @param passive? boolean
--- @return llsocket.addrinfo? ai
--- @return string? err
local function new_unix_dgram(pathname, passive)
    return new_unix(pathname, SOCK_DGRAM, 0, passive)
end

return {
    new_unix_dgram = new_unix_dgram,
    new_unix_stream = new_unix_stream,
    new_unix = new_unix,
    new_inet_dgram = new_inet_dgram,
    new_inet_stream = new_inet_stream,
    new_inet = new_inet,
    getaddrinfo_dgram = getaddrinfo_dgram,
    getaddrinfo_stream = getaddrinfo_stream,
    getaddrinfo = getaddrinfo,
}
