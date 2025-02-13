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
local sub = string.sub
local fopen = require('io.fopen')
local isfile = require('io.isfile')
local fstat = require('fstat')
local is_uint = require('lauxhlib.is').uint
local new_errno = require('errno').new
-- constants
local DEFAULT_SEND_BUFSIZ = 4096 * 4 -- 16KB

--- @class net.tls.stream.Socket : net.stream.Socket, net.tls.Socket
local Socket = {}

--- tofile
--- @param f file*|integer|string
--- @return file*? f
--- @return any err
local function tofile(f)
    if isfile(f) then
        return f --[[@as file*]]
    end
    return fopen(f)
end

--- sendfile
--- @param f file*|integer|string
--- @param bytes integer
--- @param offset? integer
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Socket:sendfile(f, bytes, offset)
    local file, err = tofile(f)
    if not file then
        return nil, err
    end

    if bytes == nil then
        -- send all content of the file
        local stat
        stat, err = fstat(file)
        if not stat then
            return nil, err
        end
        bytes = stat.size
    elseif not is_uint(bytes) then
        return nil, new_errno('EINVAL', 'bytes must be an nil or uint')
    elseif bytes <= 0 then
        -- nothing to send
        return 0
    end

    if offset == nil then
        offset = 0
    end

    local ok, errno
    ok, err, errno = file:seek('set', offset)
    if not ok then
        return nil, new_errno(errno, err)
    end

    local bufsiz
    bufsiz, err = self:sndbuf()
    if err then
        return nil, err
    elseif bufsiz > DEFAULT_SEND_BUFSIZ then
        -- prevent to allocate a large buffer size
        bufsiz = DEFAULT_SEND_BUFSIZ
    end

    local remain = bytes
    local sent = 0
    local data = ''
    repeat
        if remain > 0 then
            local nread = remain < bufsiz and remain or bufsiz
            local s = file:read(nread)
            if not s then
                -- reached to eof
                return sent
            end
            data = data .. s
        end

        -- send a content
        local len, serr, timeout = self:send(data)
        if not len then
            return sent, serr, timeout
        end
        -- update a bytes sent
        sent = sent + len
        if serr or timeout then
            return sent, serr, timeout
        end
        data = sub(data, len + 1)
        remain = remain - len
    until remain == 0 and #data == 0

    return sent
end

require('metamodule').new.Socket(Socket, 'net.stream.Socket', 'net.tls.Socket')

--- @class net.tls.server

--- @class net.tls.stream.Server : net.stream.Server, net.tls.stream.Socket
--- @field tls net.tls.server
local Server = {}

--- close
--- @return boolean ok
--- @return string? err
function Server:close()
    -- dispose io-events
    self:unwait()

    -- NOTE: non server-connection (TLS_SERVER_CONN) should not be closed
    -- self.tls:close()

    return self.sock:close()
end

--- set_sni_callback
--- @param callback fun(..., hostname: string): net.tls.server
--- @param ... any
function Server:set_sni_callback(callback, ...)
    self.tls:set_sni_callback(callback, ...)
end

require('metamodule').new.Server(Server, 'net.stream.Server',
                                 'net.tls.stream.Socket')

