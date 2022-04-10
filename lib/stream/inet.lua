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
-- lib/stream/inet.lua
-- lua-net
-- Created by Masatoshi Teruya on 16/05/16.
--
-- assign to local
local assert = assert
local type = type
local isa = require('isa')
local is_string = isa.string
local is_table = isa.table
local is_uint = isa.uint
local libtls = require('libtls')
local tls_client = libtls.client
local getaddrinfo_stream = require('net.addrinfo').getaddrinfo_stream
local socket = require('net.socket')
local socket_wrap = socket.wrap
local socket_connect = socket.connect
local socket_bind = socket.bind
local tls_stream_inet = require('net.tls.stream.inet')

--- @class net.stream.inet.Socket : net.stream.Socket
local Socket = require('metamodule').new.Socket({}, 'net.stream.Socket')

--- @class net.stream.inet.Client : net.stream.inet.Socket
local Client = require('metamodule').new.Client({}, 'net.stream.inet.Socket')

--- @class net.stream.inet.Server : net.stream.Server
local Server = {}

--- new_connection
--- @param sock llsocket.socket
--- @param nonblock boolean
--- @return net.stream.inet.Socket sock
--- @return string? err
function Server:new_connection(sock, nonblock)
    return Socket(sock, nonblock)
end

Server = require('metamodule').new.Server(Server, 'net.stream.Server')

--- new_client
--- @param host? string
--- @param port string|integer
--- @param opts? table<string, any>
--- @return net.stream.inet.Client? sock
--- @return string? err
--- @return boolean? timeout
--- @return llsocket.addrinfo? ai
local function new_client(host, port, opts)
    local tls

    if opts == nil then
        opts = {}
    elseif not is_table(opts) then
        error('opts must be table', 2)
    elseif opts.deadline ~= nil and not is_uint(opts.deadline) then
        error('opts.deadline must be uint', 2)
    elseif opts.tlscfg then
        if opts.servername == nil then
            opts.servername = host
        elseif not is_string(opts.servername) then
            error('opts.servername must be string', 2)
        end

        -- create tls client context
        local ctx, err = tls_client(opts.tlscfg)
        if err then
            return nil, err
        end
        tls = ctx
    end

    local addrs, err = getaddrinfo_stream(host, port)
    if err then
        return false, err
    end

    local timeout
    for _, ai in ipairs(addrs) do
        local sock, nonblock
        sock, err, timeout, nonblock = socket_connect(ai, opts.deadline)
        if sock then
            if tls then
                local ok
                ok, err = tls:connect_socket(sock:fd(), opts.servername)
                if not ok then
                    sock:close()
                    return nil, err
                end
                return tls_stream_inet.Client(sock, nonblock, tls), nil, nil, ai
            end
            return Client(sock, nonblock), nil, nil, ai
        end
    end

    return nil, err, timeout
end

--- new_server
--- @param host? string
--- @param port? string|integer
--- @param opts? table<string, any>
--- @return net.stream.inet.Server? server
--- @return string? err
--- @return llsocket.addrinfo? ai
local function new_server(host, port, opts)
    if opts == nil then
        opts = {}
    else
        assert(type(opts) == 'table', 'opts must be table')
        assert(opts.reuseaddr == nil or type(opts.reuseaddr) == 'boolean',
               'opts.reuseaddr must be boolean')
        assert(opts.reuseport == nil or type(opts.reuseport) == 'boolean',
               'opts.reuseport must be boolean')
    end

    local addrs, err = getaddrinfo_stream(host, port, true)
    if err then
        return nil, err
    end

    for _, ai in ipairs(addrs) do
        local sock, nonblock
        sock, err, nonblock = socket_bind(ai, opts.reuseaddr, opts.reuseport)
        if sock then
            return Server(sock, nonblock), nil, ai
        end
    end

    return nil, err
end

--- wrap
--- @param fd integer
--- @return net.stream.Socket? sock
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
    client = {
        new = new_client,
    },
    server = {
        new = new_server,
    },
}

