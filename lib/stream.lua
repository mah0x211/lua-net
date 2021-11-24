--
-- Copyright (C) 2015 Masatoshi Teruya
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
-- lib/stream.lua
-- lua-net
-- Created by Masatoshi Teruya on 15/11/15.
--
-- assign to local
local poll = require('net.poll')
local waitrecv = poll.waitrecv
local waitsend = poll.waitsend

--- @class net.stream.Socket : net.Socket
local Socket = {}

--- acceptconn
--- @return boolean enabled
--- @return string? err
function Socket:acceptconn()
    return self.sock:acceptconn()
end

--- oobinline
--- @param enable boolean
--- @return boolean enabled
--- @return string? err
function Socket:oobinline(enable)
    return self.sock:oobinline(enable)
end

--- keepalive
--- @param enable boolean
--- @return boolean enabled
--- @return string? err
function Socket:keepalive(enable)
    return self.sock:keepalive(enable)
end

--- tcpnodelay
--- @param enable boolean
--- @return boolean enabled
--- @return string? err
function Socket:tcpnodelay(enable)
    return self.sock:tcpnodelay(enable)
end

--- tcpcork
--- @param enable boolean
--- @return boolean enabled
--- @return string? err
function Socket:tcpcork(enable)
    return self.sock:tcpcork(enable)
end

--- tcpkeepalive
--- @param sec integer
--- @return integer? sec
--- @return string? err
function Socket:tcpkeepalive(sec)
    return self.sock:tcpkeepalive(sec)
end

--- tcpkeepintvl
--- @param sec integer
--- @return integer? sec
--- @return string? err
function Socket:tcpkeepintvl(sec)
    return self.sock:tcpkeepintvl(sec)
end

--- tcpkeepcnt
--- @param cnt integer
--- @return integer? cnt
--- @return string? err
function Socket:tcpkeepcnt(cnt)
    return self.sock:tcpkeepcnt(cnt)
end

--- sendfile
--- @param fd integer
--- @param bytes integer
--- @param offset integer
--- @return integer? len
--- @return string? err
--- @return boolean? timeout
function Socket:sendfile(fd, bytes, offset)
    local sent = 0
    local sock, sendfile = self.sock, self.sock.sendfile

    if not offset then
        offset = 0
    end

    while true do
        local len, err, again = sendfile(sock, fd, bytes, offset)

        if not len then
            return nil, err
        end
        -- update a bytes sent
        sent = sent + len

        if not again or not self.nonblock then
            return sent, err, again
        end

        -- wait until writable
        local ok, perr, timeout = waitsend(sock:fd(), self.snddeadl,
                                           self.sndhook, self.sndhookctx)
        if not ok then
            return sent, perr, timeout
        end

        bytes = bytes - len
        offset = offset + len
    end
end

--- sendfilesync
--- @param fd integer
--- @param bytes integer
--- @param offset integer
--- @return integer? len
--- @return string? err
--- @return boolean? timeout
function Socket:sendfilesync(fd, bytes, offset)
    return self:writesync(self.sendfile, fd, bytes, offset)
end

Socket = require('metamodule').new.Socket(Socket, 'net.Socket')

--- @class net.stream.Server : net.stream.Socket
local Server = {}

--- new_connection
--- @param sock net.Socket
--- @param nonblock boolean
--- @return net.stream.Socket
function Server:new_connection(sock, nonblock)
    return Socket(sock, nonblock)
end

--- listen
--- @param backlog integer
--- @return boolean ok
--- @return string? err
function Server:listen(backlog)
    return self.sock:listen(backlog)
end

--- accept
--- @param with_ai? boolean
--- @return net.stream.Socket? csock
--- @return string? err
--- @return llsocket.addrinfo? ai
function Server:accept(with_ai)
    local sock, accept = self.sock, self.sock.accept

    while true do
        local csock, err, again, ai = accept(sock, with_ai)

        if csock then
            csock, err = self:new_connection(csock, self.nonblock)
            if err then
                return nil, err
            end
            return csock, nil, ai
        elseif not again then
            return nil, err
        end

        -- wait until readable
        local ok, perr = waitrecv(sock:fd())
        if not ok then
            return nil, perr
        end
    end
end

--- acceptfd
--- @return integer? fd
--- @return string? err
function Server:acceptfd()
    local sock, acceptfd = self.sock, self.sock.acceptfd

    while true do
        local fd, err, again = acceptfd(sock)

        if fd then
            return fd
        elseif not again then
            return nil, err
        end

        -- wait until readable
        local ok, perr = waitrecv(self:fd())
        if not ok then
            return nil, perr
        end
    end
end

require('metamodule').new.Server(Server, 'net.stream.Socket')
