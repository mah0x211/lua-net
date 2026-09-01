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
local is_uint = require('lauxhlib.is').uint
local poll_wait_writable = require('gpoll').wait_writable
local new_deadline = require('time.clock.deadline').new
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')
local tls_connect = require('net.tls.context').connect
local socket = require('net.socket')
local socket_wrap = socket.wrap
local socket_connect_inet = socket.connect_inet
local socket_bind_inet = socket.bind_inet
local getaddrinfo = require('net.addrinfo').getaddrinfo
local tls_stream_inet = require('net.tls.stream.inet')

local DEFAULT_CONNECT_TIMEOUT = 30 -- seconds

--- inet_stream_connect
--- Non-blocking connect to (host, port) as an AF_INET / SOCK_STREAM socket.
--- The host is resolved here so that every resolved address can be tried:
--- a non-blocking connect completes asynchronously, and when the outcome is
--- a failure the next resolved address is attempted instead of giving up.
--- @param host string?
--- @param port string|integer
--- @param sec number?
--- @return socket? sock
--- @return any err
--- @return boolean? timeout
--- @return addrinfo? ai
local function inet_stream_connect(host, port, sec)
    local addrs, err = getaddrinfo(host, port, {
        socktype = 'stream',
        protocol = 'tcp',
    })
    if err then
        return nil, err
    end

    -- the deadline is one budget shared by every resolved address, not a
    -- per-address timeout
    local sndtimeo = sec
    local timeout_sec = sec or DEFAULT_CONNECT_TIMEOUT
    local deadline = new_deadline(timeout_sec)

    for _, ai in ipairs(addrs) do
        local done = deadline:is_done()
        if done then
            return nil, nil, true
        end

        local sock, cerr, again = socket_connect_inet(ai)
        if not sock then
            -- socket creation or the synchronous phase of connect() failed;
            -- keep the error and try the next resolved address
            err = cerr
        elseif not again then
            -- completed synchronously
            return sock, nil, nil, sock:getpeername()
        else
            if not sndtimeo then
                sndtimeo = sock:sndtimeo()
                -- a kernel timeout of zero means "no timeout"; keep the
                -- default budget instead of turning it into an instant
                -- deadline
                if sndtimeo and sndtimeo > 0 then
                    local elapsed = timeout_sec - deadline:remain()
                    deadline = new_deadline(sndtimeo - elapsed)
                end
            end

            -- non-blocking connect in progress; wait for writability within
            -- the remaining budget and read SO_ERROR to confirm the outcomes
            done, sec = deadline:is_done()
            if done then
                sock:close()
                return nil, nil, true
            end

            local ok, timeout
            ok, cerr, timeout = poll_wait_writable(sock:fd(), sec)
            if timeout then
                -- deadline expired while waiting for writability
                sock:close()
                return nil, nil, true
            elseif cerr then
                err = cerr
            elseif ok then
                cerr, err = sock:error()
                if cerr then
                    err = cerr
                elseif not err then
                    -- connect completed successfully
                    return sock, nil, nil, sock:getpeername()
                end
            end

            -- asynchronous failure (e.g. ECONNREFUSED); keep the error
            -- and try the next resolved address
            sock:close()
        end
    end

    return nil, err
end

--- inet_stream_bind
--- Bind an AF_INET / SOCK_STREAM socket to (host, port), applying
--- reuseaddr / reuseport as requested.
--- @param host string?
--- @param port string|integer?
--- @param reuseaddr boolean?
--- @param reuseport boolean?
--- @return socket? sock
--- @return any err
--- @return addrinfo? ai
local function inet_stream_bind(host, port, reuseaddr, reuseport)
    local sock, err = socket_bind_inet(host, port, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = reuseaddr,
        reuseport = reuseport,
    })
    if not sock then
        return nil, err
    end
    return sock, nil, sock:getsockname()
end

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
        if opts.servername == nil then
            opts.servername = host
        elseif not is_string(opts.servername) then
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

    local sock, err, timeout, ai =
        inet_stream_connect(host, port, opts.deadline)
    if sock then
        if tls then
            local ctx
            ctx, err = tls_connect(tls, sock:fd(), opts.servername,
                                   opts.tlscfg.verify_name,
                                   opts.tlscfg.verify_time,
                                   opts.tlscfg.verify_cert, opts.tlscfg.use_bio,
                                   opts.tlscfg.bufcap)
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
    elseif opts.tlscfg and opts.tlscfg.bufcap ~= nil and
        not is_uint(opts.tlscfg.bufcap) then
        error('opts.tlscfg.bufcap must be uint', 2)
    elseif opts.tlscfg then
        -- create tls server context
        local ctx, err = tls_server(opts.tlscfg.cert, opts.tlscfg.key,
                                    opts.tlscfg.protocol, opts.tlscfg.ciphers,
                                    opts.tlscfg.alpn,
                                    opts.tlscfg.session_timeout,
                                    opts.tlscfg.session_cache_size,
                                    opts.tlscfg.prefer_client_ciphers)
        if err then
            return nil, err
        end
        tls = ctx
    end

    local sock, err, ai = inet_stream_bind(host, port, opts.reuseaddr,
                                           opts.reuseport)
    if sock then
        if tls then
            return tls_stream_inet.Server(sock, tls, opts.tlscfg.use_bio,
                                          opts.tlscfg.bufcap), nil, ai
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

