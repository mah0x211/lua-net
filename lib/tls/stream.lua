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
local pread = require('io.pread')
local fstat = require('fstat')
local is_uint = require('lauxhlib.is').uint
local new_errno = require('errno').new
local errorf = require('error').format
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
--- @param bytes integer?
--- @param offset? integer
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Socket:sendfile(f, bytes, offset)
    local file, err = tofile(f)
    if not file then
        return nil, errorf('failed to tofile()', err)
    end
    -- a file opened from a path / fd is owned by this call: waiting for
    -- the GC to close it would hold the descriptor open (one per call)
    -- and can exhaust the process open-file limit
    local close_file = function()
        if f ~= file then
            file:close()
        end
    end

    if offset == nil then
        offset = 0
    elseif not is_uint(offset) then
        close_file()
        return nil, new_errno('EINVAL', 'offset must be an nil or uint')
    end

    if bytes == nil then
        -- send remaining content starting at offset; without subtracting the
        -- offset, sendfile(f, nil, N>0) would try to transfer stat.size
        -- bytes and drive pread past EOF.
        local stat
        stat, err = fstat(file)
        if not stat then
            close_file()
            return nil, err
        end

        -- calculate remaining bytes to send
        bytes = stat.size - offset
        if bytes <= 0 then
            close_file()
            return 0
        end
    elseif not is_uint(bytes) then
        close_file()
        return nil, new_errno('EINVAL', 'bytes must be an nil or uint')
    elseif bytes <= 0 then
        -- nothing to send
        close_file()
        return 0
    end

    local bufsiz
    bufsiz, err = self:sndbuf()
    if err then
        close_file()
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
            local s
            s, err = pread(file, nread, offset + sent)
            if not s then
                close_file()
                return sent, err
            elseif #s == 0 then
                -- reached end-of-file before satisfying the requested byte
                -- count; return what has been sent rather than spinning on
                -- a pread that keeps returning the empty string.
                close_file()
                return sent
            end
            data = data .. s
        end

        -- send a content
        local len, serr, timeout = self:send(data)
        -- Go style: send always reports a numeric sent count.
        sent = sent + len

        if serr then
            close_file()
            return sent, serr
        elseif timeout then
            close_file()
            return sent, nil, timeout
        end

        -- update a remain bytes
        data = sub(data, len + 1)
        remain = remain - len
    until remain == 0 and #data == 0

    close_file()
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

--- set_verify
--- @param opts table { mode:'none'|'request'|'require'?, cafile:string?, capath:string?, depth:integer? }
--- @return boolean ok
--- @return any err
function Server:set_verify(opts)
    return self.tls:set_verify(opts)
end

require('metamodule').new.Server(Server, 'net.stream.Server',
                                 'net.tls.stream.Socket')

