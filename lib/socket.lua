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
local poll = require('gpoll')
local pollable = poll.pollable
local wait_writable = poll.wait_writable
local llsocket = require('llsocket')
local socket = llsocket.socket

--- @class addrinfo
--- @field family fun(self: addrinfo): (family:integer)
--- @field socktype fun(self: addrinfo): (socktype:integer)
--- @field protocol fun(self: addrinfo): (protocol:integer)

--- @alias gcfn userdata

--- @class socket
--- @field addgcfn fun(self: socket, errfn:function, fn: function, ...):(gcfn:gcfn)
--- @field delgcfn fun(self: socket, errfn:function, fn: function):(ok:boolean)
--- @field fd fun(self: socket): (fd:integer)
--- @field family fun(self: socket): (family:integer)
--- @field socktype fun(self: socket): (socktype:integer)
--- @field protocol fun(self: socket): (protocol:integer)
--- @field cloexec fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field nonblock fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field reuseaddr fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field reuseport fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field debug fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field dontroute fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field oobinline fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field keepalive fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field tcpnodelay fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field tcpcork fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field broadcast fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field tcpkeepalive fun(self: socket, sec: integer?): (sec:integer?, err:any)
--- @field tcpkeepintvl fun(self: socket, sec: integer?): (sec:integer?, err:any)
--- @field tcpkeepcnt fun(self: socket, cnt: integer?): (cnt:integer?, err:any)
--- @field sendable fun(self: socket, msec: integer?): (ok:boolean, err:any, timeout:boolean?)
--- @field acceptconn fun(self: socket): (ok:boolean, err:any)
--- @field timestamp fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field atmark fun(self: socket): (ok:boolean, err:any)
--- @field getsockname fun(self: socket): (ai:addrinfo?, err:any)
--- @field getpeername fun(self: socket): (ai:addrinfo?, err:any)
--- @field error fun(self: socket): (soerr:any, err:any)
--- @field rcvbuf fun(self: socket, size: integer?): (size:integer?, err:any)
--- @field rcvlowat fun(self: socket, size: integer?): (size:integer?, err:any)
--- @field rcvtimeo fun(self: socket, sec: number?): (sec:number?, err:any)
--- @field sndbuf fun(self: socket, size: integer?): (size:integer?, err:any)
--- @field sndlowat fun(self: socket, size: integer?): (size:integer?, err:any)
--- @field sndtimeo fun(self: socket, sec: number?): (sec:number?, err:any)
--- @field linger fun(self: socket, sec: integer?): (sec:integer?, err:any)
--- @field close fun(self: socket, how: integer?): (err:any)
--- @field shutdown fun(self: socket, how: integer): (err:any)
--- @field bind fun(self: socket, ai: addrinfo): (ok:boolean, err:any)
--- @field listen fun(self: socket, backlog: integer?): (ok:boolean, err:any)
--- @field accept fun(self: socket, with_ai: boolean?): (sock:socket?, err:any)
--- @field acceptfd fun(self: socket): (fd:integer?, err:any)
--- @field connect fun(self: socket, ai: addrinfo): (ok:boolean, err:any)
--- @field read fun(self: socket, bufsize: integer?): (str:string?, err:any, again:boolean?)
--- @field recv fun(self: socket, bufsize: integer?, ...:integer): (str:string?, err:any, again:boolean?)
--- @field recvmsg fun(self: socket, msg: msghdr, ...:integer): (len:integer?, err:any, again:boolean?)
--- @field recvfrom fun(self: socket, bufsize: integer?, ...:integer): (str:string?, err:any, again:boolean?, ai:addrinfo?)
--- @field recvfd fun(self: socket, ...: integer): (fd:integer?, err:any, again:boolean?)
--- @field write fun(self: socket, str: string): (len:integer?, err:any, again:boolean?)
--- @field send fun(self: socket, str: string, ...: integer?): (len:integer?, err:any, again:boolean?)
--- @field sendmsg fun(self: socket, msg: msghdr, ...: integer?): (len:integer?, err:any, again:boolean?)
--- @field sendto fun(self: socket, str: string, ai: addrinfo, ...: integer?): (len:integer?, err:any, again:boolean?)
--- @field sendfile fun(self: socket, fd: integer, bytes: integer, offset: integer?): (len:integer?, err:any, again:boolean?)
--- @field sendfd fun(self: socket, fd: integer, ai: addrinfo?, ...: integer): (len:integer?, err:any, again:boolean?)
--- @field mcastloop fun(self: socket, enable: boolean?): (enabled:boolean, err:any)
--- @field mcastttl fun(self: socket, ttl: integer?): (ttl:integer?, err:any)
--- @field mcastif fun(self: socket, ifname: string?): (ifname:string?, err:any)
--- @field mcastjoin fun(self: socket, group: addrinfo, ifname: string?): (ok:boolean, err:any)
--- @field mcastleave fun(self: socket, group: addrinfo, ifname: string?): (ok:boolean, err:any)
--- @field mcastjoinsrc fun(self: socket, group: addrinfo, src: addrinfo, ifname: string?): (ok:boolean, err:any)
--- @field mcastleavesrc fun(self: socket, group: addrinfo, src: addrinfo, ifname: string?): (ok:boolean, err:any)
--- @field mcastblocksrc fun(self: socket, group: addrinfo, src: addrinfo, ifname: string?): (ok:boolean, err:any)
--- @field mcastunblocksrc fun(self: socket, group: addrinfo, src: addrinfo, ifname: string?): (ok:boolean, err:any)

--- @type fun(family: integer, socktype: integer, protocol?: integer, nonblock?: boolean): (sock:socket?, err:any)
local socket_new = socket.new

--- @type fun(fd: integer): (sock:socket?, err:any)
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
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
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
    if not sock then
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
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
local function new_inet(socktype, protocol, reuseaddr, reuseport)
    return new(AF_INET, socktype, protocol, reuseaddr, reuseport)
end

--- new_inet_stream
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
local function new_inet_stream(reuseaddr, reuseport)
    return new(AF_INET, SOCK_STREAM, IPPROTO_TCP, reuseaddr, reuseport)
end

--- new_inet_dgram
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
local function new_inet_dgram(reuseaddr, reuseport)
    return new(AF_INET, SOCK_DRAM, IPPROTO_UDP, reuseaddr, reuseport)
end

--- new_unix
--- @param socktype integer
--- @param protocol integer
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
local function new_unix(socktype, protocol, reuseaddr, reuseport)
    return new(AF_UNIX, socktype, protocol, reuseaddr, reuseport)
end

--- new_unix_stream
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
local function new_unix_stream(reuseaddr, reuseport)
    return new(AF_UNIX, SOCK_STREAM, 0, reuseaddr, reuseport)
end

--- new_unix_dgram
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
local function new_unix_dgram(reuseaddr, reuseport)
    return new(AF_UNIX, SOCK_DRAM, 0, reuseaddr, reuseport)
end

--- pair
--- @param socktype integer
--- @return socket? sock
--- @return any err
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
--- @return any err
--- @return boolean? nonblock
local function pair_stream()
    return pair(SOCK_STREAM)
end

--- pair_dgram
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
local function pair_dgram()
    return pair(SOCK_DRAM)
end

--- bind
--- @param ai addrinfo
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
local function bind(ai, reuseaddr, reuseport)
    if reuseaddr ~= nil and not is_boolean(reuseaddr) then
        error('reuseaddr must be boolean', 2)
    elseif reuseport ~= nil and not is_boolean(reuseport) then
        error('reuseport must be boolean', 2)
    end

    local sock, err, nonblock = new(ai:family(), ai:socktype(), ai:protocol(),
                                    reuseaddr, reuseport)
    if not sock then
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
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
--- @return addrinfo? ai
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
--- @return any err
--- @return boolean? nonblock
--- @return addrinfo? ai
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
--- @param ai addrinfo
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
    if not sock then
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
        ok, err, timeout = wait_writable(sock:fd(), conndeadl)
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

--- connect_inet_stream
--- @param host string
--- @param port string|integer
--- @param conndeadl? integer
--- @return socket? sock
--- @return any err
--- @return boolean? timeout
--- @return boolean? nonblock
--- @return addrinfo? ai
local function connect_inet_stream(host, port, conndeadl)
    local addrs, err = getaddrinfo_stream(host, port)
    if err then
        return nil, err
    end

    local timeout
    for _, ai in ipairs(addrs) do
        local sock, nonblock
        sock, err, timeout, nonblock = connect(ai, conndeadl)
        if sock then
            return sock, nil, nil, nonblock, ai
        end
    end

    return nil, err, timeout
end

--- connect_unix_stream
--- @param pathname string
--- @param conndeadl? integer
--- @return socket? sock
--- @return any err
--- @return boolean? timeout
--- @return boolean? nonblock
--- @return addrinfo? ai
local function connect_unix_stream(pathname, conndeadl)
    local ai, err = new_unix_stream_ai(pathname)
    if err then
        return nil, err
    end

    local sock, timeout, nonblock
    sock, err, timeout, nonblock = connect(ai, conndeadl)
    if sock then
        return sock, nil, nil, nonblock, ai
    end

    return nil, err, timeout
end

--- wrap
--- @param fd integer
--- @return socket? sock
--- @return any err
--- @return boolean? nonblock
local function wrap(fd)
    local sock, err = socket_wrap(fd)
    if not sock then
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
    connect_unix_stream = connect_unix_stream,
    connect_inet_stream = connect_inet_stream,
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
