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
--- @class net.unix.Socket : net.Socket
local Socket = {}

--- sendfd
--- @param fd integer
--- @param ai addrinfo?
--- @param ... integer flags
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Socket:sendfd(fd, ai, ...)
    local sock, sendfd = self.sock, self.sock.sendfd
    local deadline, sec = self:get_send_deadline()

    while true do
        local len, err, again = sendfd(sock, fd, ai, ...)

        if not len then
            return nil, err
        elseif not again then
            return len
        elseif deadline then
            sec = deadline:remain()
            if sec <= 0 then
                return len, nil, true
            end
        end

        -- wait until writable
        local ok, perr, timeout = self:wait_writable(sec)
        if not ok then
            return len, perr, timeout
        end
    end
end

--- sendfdsync
--- @param fd integer
--- @param ai addrinfo?
--- @param ... integer flags
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Socket:sendfdsync(fd, ai, ...)
    return self:syncwrite(self.sendfd, fd, ai, ...)
end

--- recvfd
--- @param ... integer flags
--- @return integer? fd
--- @return any err
--- @return boolean? timeout
function Socket:recvfd(...)
    local sock, recvfd = self.sock, self.sock.recvfd
    local deadline, sec = self:get_recv_deadline()

    while true do
        local fd, err, again = recvfd(sock, ...)

        if not again then
            return fd, err, again
        elseif deadline then
            sec = deadline:remain()
            if sec <= 0 then
                return nil, nil, true
            end
        end

        -- wait until readable
        local ok, perr, timeout = self:wait_readable()
        if not ok then
            return nil, perr, timeout
        end
    end
end

--- recvfdsync
--- @param ... integer flags
--- @return integer? fd
--- @return any err
--- @return boolean? timeout
function Socket:recvfdsync(...)
    return self:syncread(self.recvfd, ...)
end

require('metamodule').new.Socket(Socket, 'net.Socket')
