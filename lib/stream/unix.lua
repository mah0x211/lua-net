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
local is_string = require('lauxhlib.is').str
local is_table = require('lauxhlib.is').table
local is_finite = require('lauxhlib.is').finite
local is_uint = require('lauxhlib.is').uint
local poll_wait_writable = require('gpoll').wait_writable
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')
local tls_connect = require('net.tls.context').connect
local socket = require('net.socket')
local socket_connect_unix = socket.connect_unix
local socket_bind_unix = socket.bind_unix
local socket_wrap = socket.wrap
local socket_pair = socket.pair
local tls_stream_unix = require('net.tls.stream.unix')

--- unix_stream_connect
--- Non-blocking connect to `pathname` as an AF_UNIX / SOCK_STREAM socket.
--- On EINPROGRESS the connect completes asynchronously; wait for writability
--- up to `deadline` and then read SO_ERROR via sock:error() to confirm.
--- @param pathname string
--- @param deadline number?
--- @return socket? sock
--- @return any err
--- @return boolean? timeout
--- @return addrinfo? ai
local function unix_stream_connect(pathname, deadline)
    local sock, err, again = socket_connect_unix(pathname, {
        socktype = 'stream',
    })
    if not sock then
        return nil, err
    end
    if again then
        local ok, perr, timeout = poll_wait_writable(sock:fd(), deadline)
        if not ok or perr or timeout then
            sock:close()
            return nil, perr, timeout
        end
        local soerr, cerr = sock:error()
        if cerr then
            sock:close()
            return nil, cerr
        elseif soerr then
            sock:close()
            return nil, soerr
        end
    end
    return sock, nil, nil, sock:getpeername()
end

--- unix_stream_bind
--- Bind an AF_UNIX / SOCK_STREAM socket to `pathname`.
--- @param pathname string
--- @return socket? sock
--- @return any err
--- @return addrinfo? ai
local function unix_stream_bind(pathname)
    local sock, err = socket_bind_unix(pathname, {
        socktype = 'stream',
    })
    if not sock then
        return nil, err
    end
    return sock, nil, sock:getsockname()
end

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
    elseif opts.tlscfg and opts.tlscfg.bufcap ~= nil and
        not is_uint(opts.tlscfg.bufcap) then
        error('opts.tlscfg.bufcap must be uint', 2)
    elseif opts.tlscfg and opts.tlscfg.cafile ~= nil and
        not is_string(opts.tlscfg.cafile) then
        error('opts.tlscfg.cafile must be string', 2)
    elseif opts.tlscfg and opts.tlscfg.capath ~= nil and
        not is_string(opts.tlscfg.capath) then
        error('opts.tlscfg.capath must be string', 2)
    elseif opts.tlscfg and opts.tlscfg.verify_depth ~= nil and
        not is_uint(opts.tlscfg.verify_depth) then
        error('opts.tlscfg.verify_depth must be uint', 2)
    elseif opts.tlscfg then
        if opts.servername ~= nil and not is_string(opts.servername) then
            error('opts.servername must be string', 2)
        end

        -- create tls client context
        local ctx, err = tls_client(opts.tlscfg.protocol, opts.tlscfg.ciphers,
                                    opts.tlscfg.alpn,
                                    opts.tlscfg.session_cache_timeout,
                                    opts.tlscfg.session_cache_size)
        if err then
            return nil, err
        end

        -- load the trusted CA locations before the handshake
        if opts.tlscfg.cafile or opts.tlscfg.capath then
            local ok
            ok, err = ctx:load_verify_locations(opts.tlscfg.cafile,
                                                opts.tlscfg.capath)
            if not ok then
                return nil, err
            end
        end
        if opts.tlscfg.verify_depth then
            ctx:set_verify_depth(opts.tlscfg.verify_depth)
        end
        tls = ctx
    end

    local sock, err, timeout, ai = unix_stream_connect(pathname, opts.deadline)
    if sock then
        if tls then
            local ctx
            ctx, err = tls_connect(tls, sock:fd(), opts.servername,
                                   opts.tlscfg.noverify_name,
                                   opts.tlscfg.noverify_time,
                                   opts.tlscfg.noverify_cert,
                                   opts.tlscfg.use_bio, opts.tlscfg.bufcap)
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
    elseif tlscfg and tlscfg.bufcap ~= nil and not is_uint(tlscfg.bufcap) then
        error('tlscfg.bufcap must be uint', 2)
    elseif tlscfg then
        -- create tls server context
        local ctx, err = tls_server(tlscfg.cert, tlscfg.key, tlscfg.protocol,
                                    tlscfg.ciphers, tlscfg.alpn,
                                    tlscfg.session_timeout,
                                    tlscfg.session_cache_size,
                                    tlscfg.prefer_client_ciphers)
        if err then
            return nil, err
        end
        tls = ctx
    end

    local sock, err, ai = unix_stream_bind(pathname)
    if sock then
        if tls then
            return tls_stream_unix.Server(sock, tls, tlscfg.use_bio,
                                          tlscfg.bufcap), nil, ai
        end
        return Server(sock), nil, ai
    end

    return nil, err
end

--- pair
--- @return net.stream.unix.Socket[]? socketpair
--- @return any err
local function pair()
    local sp, err = socket_pair({
        socktype = 'stream',
    })

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

