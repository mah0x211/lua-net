--
-- Copyright (C) 2015-2022 Masatoshi Fukunaga
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
-- lib/tls/stream.lua
-- lua-net
-- Created by Masatoshi Teruya on 15/11/15.
--
-- assign to local
local floor = math.floor
local fopen = require('io.fopen')
local isfile = require('io.isfile')
local poll = require('gpoll')
local unwait = poll.unwait
local new_errno = require('errno').new
-- constants
local BUFSIZ = 1024
local DEFAULT_SEND_BUFSIZ = BUFSIZ * 8

--- @class net.tls.stream.Socket : net.stream.Socket, net.tls.Socket
local Socket = {}

--- sendfile
--- @param f file*|integer|string
--- @param bytes integer
--- @param offset? integer
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Socket:sendfile(f, bytes, offset)
    if not isfile(f) then
        local err
        f, err = fopen(f)
        if not f then
            return nil, err
        end
    end

    if not offset then
        offset = 0
    end
    local ok, err, errno = f:seek('set', offset)
    if not ok then
        return nil, new_errno(errno, err)
    end

    local bufsiz
    bufsiz, err = self:sndbuf()
    if err then
        return nil, err
    elseif bufsiz > DEFAULT_SEND_BUFSIZ then
        bufsiz = DEFAULT_SEND_BUFSIZ
    elseif bufsiz == DEFAULT_SEND_BUFSIZ then
        bufsiz = DEFAULT_SEND_BUFSIZ - BUFSIZ
    else
        bufsiz = floor(bufsiz * 0.80)
    end

    local sent = 0

    while true do
        local s = f:read(bufsiz)
        if not s then
            -- reached to eof
            return sent
        end

        local len, serr, timeout = self:send(s)
        if not len then
            return sent, serr, timeout
        end

        -- update a bytes sent
        sent = sent + len

        if serr or timeout then
            return sent, serr, timeout
        end
    end
end

Socket = require('metamodule').new.Socket(Socket, 'net.stream.Socket',
                                          'net.tls.Socket')

--- @class net.tls.stream.Server : net.stream.Server, net.tls.stream.Socket
local Server = {}

--- new_connection
--- @param sock llsocket.socket
--- @param nonblock boolean
--- @return net.tls.Socket sock
--- @return string? err
function Server:new_connection(sock, nonblock)
    local tls, err = self.tls:accept_socket(sock:fd())

    if err then
        sock:close()
        return nil, err
    end

    return Socket(sock, nonblock, tls)
end

--- close
--- @return boolean ok
--- @return string? err
function Server:close()
    if self.nonblock then
        unwait(self:fd())
    end

    -- NOTE: non server-connection (TLS_SERVER_CONN) should not be closed
    -- self:tls_close()

    return self.sock:close()
end

require('metamodule').new.Server(Server, 'net.stream.Server',
                                 'net.tls.stream.Socket')

