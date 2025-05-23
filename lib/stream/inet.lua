--
-- Copyright (C) 2016-2022 Masatoshi Fukunaga
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
local is_boolean = require('lauxhlib.is').bool
local is_string = require('lauxhlib.is').str
local is_table = require('lauxhlib.is').table
local is_finite = require('lauxhlib.is').finite
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')
local tls_connect = require('net.tls.context').connect
local socket = require('net.socket')
local socket_wrap = socket.wrap
local socket_connect = socket.connect_inet_stream
local socket_bind = socket.bind_inet_stream
local tls_stream_inet = require('net.tls.stream.inet')

--- @class net.stream.inet.Socket : net.stream.Socket
local Socket = require('metamodule').new.Socket({}, 'net.stream.Socket')

--- @class net.stream.inet.Client : net.stream.inet.Socket
local Client = require('metamodule').new.Client({}, 'net.stream.inet.Socket')

--- @class net.stream.inet.Server : net.stream.Server
local Server = {}

--- new_connection
--- @param sock socket
--- @return net.stream.inet.Socket sock
--- @return string? err
function Server:new_connection(sock)
    return Socket(sock)
end

Server = require('metamodule').new.Server(Server, 'net.stream.Server')

--- new_client
--- @param host string?
--- @param port string|integer
--- @param opts table<string, any>?
--- @return net.stream.inet.Client? sock
--- @return any err
--- @return boolean? timeout
--- @return addrinfo? ai
local function new_client(host, port, opts)
    local tls

    if opts == nil then
        opts = {}
    elseif not is_table(opts) then
        error('opts must be table', 2)
    elseif opts.deadline ~= nil and not is_finite(opts.deadline) then
        error('opts.deadline must be finite number', 2)
    elseif opts.tlscfg ~= nil and not is_table(opts.tlscfg) then
        error('opts.tlscfg must be table', 2)
    elseif opts.tlscfg then
        if opts.servername == nil then
            opts.servername = host
        elseif not is_string(opts.servername) then
            error('opts.servername must be string', 2)
        end

        -- create tls client context
        local ctx, err = tls_client(opts.tlscfg.protocol, opts.tlscfg.ciphers,
                                    opts.tlscfg.session_cache_timeout,
                                    opts.tlscfg.session_cache_size,
                                    opts.tlscfg.prefer_client_ciphers,
                                    opts.tlscfg.ocsp_error_callback)
        if err then
            return nil, err
        end
        tls = ctx
    end

    local sock, err, timeout, ai = socket_connect(host, port, opts.deadline)
    if sock then
        if tls then
            local ctx
            ctx, err = tls_connect(tls, sock:fd(), opts.servername,
                                   opts.tlscfg.noverify_name,
                                   opts.tlscfg.noverify_time,
                                   opts.tlscfg.noverify_cert)
            if not ctx then
                sock:close()
                return nil, err
            end
            return tls_stream_inet.Client(sock, ctx), nil, nil, ai
        end
        return Client(sock), nil, nil, ai
    end

    return nil, err, timeout
end

--- new_server
--- @param host string?
--- @param port string|integer?
--- @param opts table<string, any>?
--- @return net.stream.inet.Server? server
--- @return any err
--- @return addrinfo? ai
local function new_server(host, port, opts)
    local tls

    if opts == nil then
        opts = {}
    elseif not is_table(opts) then
        error('opts must be table', 2)
    elseif opts.reuseaddr ~= nil and not is_boolean(opts.reuseaddr) then
        error('opts.reuseaddr must be boolean', 2)
    elseif opts.reuseport ~= nil and not is_boolean(opts.reuseport) then
        error('opts.reuseport must be boolean', 2)
    elseif opts.tlscfg ~= nil and not is_table(opts.tlscfg) then
        error('opts.tlscfg must be table', 2)
    elseif opts.tlscfg then
        -- create tls server context
        local ctx, err = tls_server(opts.tlscfg.cert, opts.tlscfg.key,
                                    opts.tlscfg.protocol, opts.tlscfg.ciphers,
                                    opts.tlscfg.session_timeout,
                                    opts.tlscfg.session_cache_size)
        if err then
            return nil, err
        end
        tls = ctx
    end

    local sock, err, ai =
        socket_bind(host, port, opts.reuseaddr, opts.reuseport)
    if sock then
        if tls then
            return tls_stream_inet.Server(sock, tls), nil, ai
        end
        return Server(sock), nil, ai
    end

    return nil, err
end

--- wrap
--- @param fd integer
--- @return net.stream.Socket? sock
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
    client = {
        new = new_client,
    },
    server = {
        new = new_server,
    },
}

