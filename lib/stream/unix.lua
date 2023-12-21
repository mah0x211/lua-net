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
local isa = require('isa')
local is_string = isa.string
local is_table = isa.table
local is_finite = isa.finite
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')
local tls_connect = require('net.tls.context').connect
local socket = require('net.socket')
local socket_connect = socket.connect_unix_stream
local socket_bind = socket.bind_unix_stream
local socket_wrap = socket.wrap
local socket_pair_stream = socket.pair_stream
local tls_stream_unix = require('net.tls.stream.unix')

--- @class net.stream.unix.Socket : net.stream.Socket, net.unix.Socket
local Socket = require('metamodule').new.Socket({}, 'net.stream.Socket',
                                                'net.unix.Socket')

--- @class net.stream.unix.Client : net.stream.unix.Socket
local Client = require('metamodule').new.Client({}, 'net.stream.unix.Socket')

--- @class net.stream.unix.Server : net.stream.Server
local Server = {}

--- new_connection
--- @param sock socket
--- @return net.stream.unix.Socket sock
--- @return any err
function Server:new_connection(sock)
    return Socket(sock)
end

Server = require('metamodule').new.Server(Server, 'net.stream.Server')

--- new_client
--- @param pathname string
--- @param opts table<string, any>?
--- @return net.stream.unix.Client? sock
--- @return any err
--- @return boolean? timeout
--- @return addrinfo? ai
local function new_client(pathname, opts)
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

    local sock, err, timeout, ai = socket_connect(pathname, opts.deadline)
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
            return tls_stream_unix.Client(sock, ctx), nil, nil, ai
        end
        return Client(sock), nil, nil, ai
    end

    return nil, err, timeout
end

--- new_server
--- @param pathname string
--- @param tlscfg table<string, any>?
--- @return net.stream.unix.Server? server
--- @return any err
--- @return addrinfo? ai
local function new_server(pathname, tlscfg)
    local tls

    if not is_string(pathname) then
        error('pathname must be string', 2)
    elseif tlscfg ~= nil and not is_table(tlscfg) then
        error('tlscfg must be table', 2)
    elseif tlscfg then
        -- create tls server context
        local ctx, err = tls_server(tlscfg.cert, tlscfg.key, tlscfg.protocol,
                                    tlscfg.ciphers, tlscfg.session_timeout,
                                    tlscfg.session_cache_size)
        if err then
            return nil, err
        end
        tls = ctx
    end

    local sock, err, ai = socket_bind(pathname)
    if sock then
        if tls then
            return tls_stream_unix.Server(sock, tls), nil, ai
        end
        return Server(sock), nil, ai
    end

    return nil, err
end

--- pair
--- @return net.stream.unix.Socket[]? socketpair
--- @return any err
local function pair()
    local sp, err = socket_pair_stream()

    if not sp then
        return nil, err
    end

    return {
        Socket(sp[1]),
        Socket(sp[2]),
    }
end

--- wrap
--- @param fd integer
--- @return net.stream.unix.Socket? sock
--- @return any err
local function wrap(fd)
    local sock, err = socket_wrap(fd)

    if not sock then
        return nil, err
    end

    return Socket(sock)
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

