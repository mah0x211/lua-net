--
-- Copyright (C) 2017 Masatoshi Fukunaga
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
-- lib/unix.lua
-- lua-net
-- Created by Masatoshi Teruya on 17/09/05.
--
-- assign to local
local poll = require('gpoll')
local wait_readable = poll.wait_readable
local wait_writable = poll.wait_writable

--- @class net.unix.Socket : net.Socket
local Socket = {}

--- sendfd
--- @param fd integer
--- @param ai llsocket.addrinfo
--- @vararg integer flags
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:sendfd(fd, ai, ...)
    local sock, sendfd = self.sock, self.sock.sendfd

    while true do
        local len, err, again = sendfd(sock, fd, ai, ...)

        if not len then
            return nil, err
        elseif not again then
            return len
        end

        -- wait until writable
        local ok, perr, timeout = wait_writable(sock:fd(), self.snddeadl,
                                                self.sndhook, self.sndhookctx)
        if not ok then
            return len, perr, timeout
        end
    end
end

--- sendfdsync
--- @param fd integer
--- @param ai llsocket.addrinfo
--- @vararg integer flags
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:sendfdsync(fd, ai, ...)
    return self:syncwrite(self.sendfd, fd, ai, ...)
end

--- recvfd
--- @vararg integer flags
--- @return integer? fd
--- @return error? err
--- @return boolean? timeout
function Socket:recvfd(...)
    local sock, recvfd = self.sock, self.sock.recvfd

    while true do
        local fd, err, again = recvfd(sock, ...)

        if not again or not self.nonblock then
            return fd, err, again
        end

        -- wait until readable
        local ok, perr, timeout = wait_readable(sock:fd(), self.rcvdeadl,
                                                self.rcvhook, self.rcvhookctx)
        if not ok then
            return nil, perr, timeout
        end
    end
end

--- recvfdsync
--- @vararg integer flags
--- @return integer? fd
--- @return error? err
--- @return boolean? timeout
function Socket:recvfdsync(...)
    return self:syncread(self.recvfd, ...)
end

require('metamodule').new.Socket(Socket, 'net.Socket')
