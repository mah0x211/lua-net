--
-- Copyright (C) 2016 Masatoshi Teruya
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
-- lib/stream/unix.lua
-- lua-net
-- Created by Masatoshi Teruya on 16/05/16.
--
-- assign to local
local assert = assert
local is_uint = require('isa').uint
local new_unix_stream_ai = require('net.addrinfo').new_unix_stream
local socket = require('net.socket')
local socket_connect = socket.connect
local socket_bind = socket.bind
local socket_wrap = socket.wrap
local socket_pair_stream = socket.pair_stream

--- @class net.stream.unix.Socket : net.stream.Socket, net.unix.Socket
local Socket = require('metamodule').new.Socket({}, 'net.stream.Socket',
                                                'net.unix.Socket')

--- @class net.stream.unix.Client : net.stream.unix.Socket
local Client = require('metamodule').new.Client({}, 'net.stream.unix.Socket')

--- @class net.stream.unix.Server : net.stream.Server
local Server = require('metamodule').new.Server({}, 'net.stream.Server')

--- new_client
--- @param pathname string
--- @param conndeadl? integer
--- @return net.stream.inet.Client? sock
--- @return string? err
--- @return boolean? timeout
--- @return llsocket.addrinfo? ai
local function new_client(pathname, conndeadl)
    assert(conndeadl == nil or is_uint(conndeadl), 'conndeadl must be uint')
    local ai, err = new_unix_stream_ai(pathname)

    if err then
        return nil, err
    end

    local sock, timeout, nonblock
    sock, err, timeout, nonblock = socket_connect(ai)
    if err then
        return nil, err, timeout
    end

    return Client(sock, nonblock), nil, nil, ai
end

--- new_server
--- @param pathname string
--- @return net.stream.unix.Server? server
--- @return string? err
--- @return llsocket.addrinfo? ai
local function new_server(pathname)
    local ai, err = new_unix_stream_ai(pathname, true)

    if err then
        return nil, err
    end

    local sock, nonblock
    sock, err, nonblock = socket_bind(ai)
    if err then
        return nil, err
    end

    return Server(sock, nonblock), nil, ai
end

--- pair
--- @return net.stream.unix.Socket[]? socketpair
--- @return string? err
local function pair()
    local sp, err, nonblock = socket_pair_stream()

    if err then
        return nil, err
    end

    return {
        Socket(sp[1], nonblock),
        Socket(sp[2], nonblock),
    }
end

--- wrap
--- @param fd integer
--- @return net.stream.unix.Socket? sock
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
    client = {
        new = new_client,
    },
    server = {
        new = new_server,
    },
}

