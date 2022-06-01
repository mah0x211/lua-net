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
--- assign to local
local isa = require('isa')
local is_boolean = isa.boolean
local is_int = isa.int
local is_uint = isa.uint
local poll = require('net.poll')
local pollable = poll.pollable
local waitsend = poll.waitsend
local llsocket = require('llsocket')
local socket = llsocket.socket
local socket_new = socket.new
local socket_wrap = socket.wrap
local socket_pair = socket.pair
local addrinfo = require('net.addrinfo')
local getaddrinfo_stream = addrinfo.getaddrinfo_stream
local new_unix_stream_ai = addrinfo.new_unix_stream
--- constants
local SOCK_DRAM = llsocket.SOCK_DGRAM
local SOCK_STREAM = llsocket.SOCK_STREAM
local IPPROTO_UDP = llsocket.IPPROTO_UDP
local IPPROTO_TCP = llsocket.IPPROTO_TCP
local AF_INET = llsocket.AF_INET
local AF_UNIX = llsocket.AF_UNIX

--- new
--- @param family integer
--- @param socktype integer
--- @param protocol integer
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return socket sock
--- @return error? err
--- @return boolean? nonblock
local function new(family, socktype, protocol, reuseaddr, reuseport)
    if not is_int(family) then
        error('family must be int', 2)
    elseif not is_int(socktype) then
        error('socktype must be int', 2)
    elseif not is_int(protocol) then
        error('protocol must be int', 2)
    elseif reuseaddr ~= nil and not is_boolean(reuseaddr) then
        error('reuseaddr must be boolean', 2)
    elseif reuseport ~= nil and not is_boolean(reuseport) then
        error('reuseport must be boolean', 2)
    end

    local is_pollable = pollable()
    local sock, err = socket_new(family, socktype, protocol, is_pollable)
    if err then
        return nil, err
    end

    -- enable reuseaddr
    local _
    if reuseaddr then
        _, err = sock:reuseaddr(true)
        if err then
            sock:close()
            return nil, err
        end
    end

    -- enable reuseport
    if reuseport then
        _, err = sock:reuseport(true)
        if err then
            sock:close()
            return nil, err
        end
    end

    return sock, nil, is_pollable
end

--- new_inet
--- @param socktype integer
--- @param protocol integer
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return socket sock
--- @return error? err
--- @return boolean? nonblock
local function new_inet(socktype, protocol, reuseaddr, reuseport)
    return new(AF_INET, socktype, protocol, reuseaddr, reuseport)
end

--- new_inet_stream
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return socket sock
--- @return error? err
--- @return boolean? nonblock
local function new_inet_stream(reuseaddr, reuseport)
    return new(AF_INET, SOCK_STREAM, IPPROTO_TCP, reuseaddr, reuseport)
end

--- new_inet_dgram
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return socket sock
--- @return error? err
--- @return boolean? nonblock
local function new_inet_dgram(reuseaddr, reuseport)
    return new(AF_INET, SOCK_DRAM, IPPROTO_UDP, reuseaddr, reuseport)
end

--- new_unix
--- @param socktype integer
--- @param protocol integer
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return socket sock
--- @return error? err
--- @return boolean? nonblock
local function new_unix(socktype, protocol, reuseaddr, reuseport)
    return new(AF_UNIX, socktype, protocol, reuseaddr, reuseport)
end

--- new_unix_stream
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return socket sock
--- @return error? err
--- @return boolean? nonblock
local function new_unix_stream(reuseaddr, reuseport)
    return new(AF_UNIX, SOCK_STREAM, 0, reuseaddr, reuseport)
end

--- new_unix_dgram
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return socket sock
--- @return error? err
--- @return boolean? nonblock
local function new_unix_dgram(reuseaddr, reuseport)
    return new(AF_UNIX, SOCK_DRAM, 0, reuseaddr, reuseport)
end

--- pair
--- @param socktype integer
--- @return socket? sock
--- @return error? err
--- @return boolean? nonblock
local function pair(socktype)
    local is_pollable = pollable()
    local socks, err = socket_pair(socktype, 0, is_pollable)

    if err then
        return nil, err
    end

    return socks, nil, is_pollable
end

--- pair_stream
--- @return socket? sock
--- @return error? err
--- @return boolean? nonblock
local function pair_stream()
    return pair(SOCK_STREAM)
end

--- pair_dgram
--- @return socket? sock
--- @return error? err
--- @return boolean? nonblock
local function pair_dgram()
    return pair(SOCK_DRAM)
end

--- bind
--- @param ai llsocket.addrinfo
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return socket? sock
--- @return error? err
--- @return boolean? nonblock
local function bind(ai, reuseaddr, reuseport)
    if reuseaddr ~= nil and not is_boolean(reuseaddr) then
        error('reuseaddr must be boolean', 2)
    elseif reuseport ~= nil and not is_boolean(reuseport) then
        error('reuseport must be boolean', 2)
    end

    local sock, err, nonblock = new(ai:family(), ai:socktype(), ai:protocol(),
                                    reuseaddr, reuseport)
    if err then
        return nil, err
    end

    local ok
    ok, err = sock:bind(ai)
    if ok then
        return sock, nil, nonblock
    end

    return nil, err
end

--- bind_inet_stream
--- @param host string
--- @param port string|integer
--- @param reuseaddr? boolean
--- @param reuseport? boolean
--- @return socket? sock
--- @return error? err
--- @return boolean? nonblock
--- @return llsocket.addrinfo? ai
local function bind_inet_stream(host, port, reuseaddr, reuseport)
    local addrs, err = getaddrinfo_stream(host, port, true)
    if err then
        return nil, err
    end

    for _, ai in ipairs(addrs) do
        local sock, nonblock
        sock, err, nonblock = bind(ai, reuseaddr, reuseport)
        if sock then
            return sock, nil, nonblock, ai
        end
    end

    return nil, err
end

--- bind_unix_stream
--- @param pathname string
--- @return socket sock
--- @return error? err
--- @return boolean? nonblock
--- @return llsocket.addrinfo? ai
local function bind_unix_stream(pathname)
    local ai, err = new_unix_stream_ai(pathname, true)
    if err then
        return nil, err
    end

    local sock, nonblock
    sock, err, nonblock = bind(ai)
    if err then
        return nil, err
    end

    return sock, nil, nonblock, ai
end

--- connect
--- @param ai llsocket.addrinfo
--- @param conndeadl? integer
--- @return socket? sock
--- @return string? err
--- @return boolean? timeout
--- @return boolean? nonblock
local function connect(ai, conndeadl)
    if ai == nil then
        error('ai must not be nil', 2)
    elseif conndeadl ~= nil and not is_uint(conndeadl) then
        error('conndeadl must be uint', 2)
    end

    local is_pollable = pollable()
    local is_nonblock = is_pollable or conndeadl ~= nil
    local sock, err = socket_new(ai:family(), ai:socktype(), ai:protocol(),
                                 is_nonblock)
    if err then
        return nil, err
    end

    -- sync connect
    if not is_nonblock then
        local ok, cerr = sock:connect(ai)
        if not ok then
            sock:close()
            return nil, cerr
        end
        return sock
    end

    -- async connect
    local ok
    ok, err = sock:connect(ai)
    if not ok then
        sock:close()
        return nil, err
    elseif not err then
        return sock, nil, nil, is_pollable
    end

    -- wait until sendable
    local timeout
    if is_pollable then
        -- with the poller
        ok, err, timeout = waitsend(sock:fd(), conndeadl)
    else
        -- with builtin poller
        ok, err, timeout = sock:sendable(conndeadl)
        -- disable nonblock mode
        local _, nerr = sock:nonblock(false)
        if nerr then
            sock:close()
            return nil, err
        end
    end

    -- got error or timeout
    if not ok or err or timeout then
        sock:close()
        return nil, err, timeout
    end

    -- check errno from socket
    local soerr
    soerr, err = sock:error()
    if err then
        sock:close()
        return nil, err
    elseif soerr then
        sock:close()
        return nil, soerr
    end

    return sock, nil, nil, is_pollable
end

--- wrap
--- @param fd integer
--- @return socket? sock
--- @return error? err
--- @return boolean? nonblock
local function wrap(fd)
    local sock, err = socket_wrap(fd)
    if not err then
        return nil, err
    end

    local is_pollable = pollable()
    if is_pollable then
        local _, nerr = sock:nonblock(true)
        if nerr then
            return nil, err
        end
    end

    return sock, nil, is_pollable
end

return {
    wrap = wrap,
    connect = connect,
    bind_unix_stream = bind_unix_stream,
    bind_inet_stream = bind_inet_stream,
    bind = bind,
    pair_dgram = pair_dgram,
    pair_stream = pair_stream,
    pair = pair,
    new_unix_dgram = new_unix_dgram,
    new_unix_stream = new_unix_stream,
    new_unix = new_unix,
    new_inet_dgram = new_inet_dgram,
    new_inet_stream = new_inet_stream,
    new_inet = new_inet,
    close = socket.close,
    shutdown = socket.shutdown,
}
