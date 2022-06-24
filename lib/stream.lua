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
local poll = require('gpoll')
local wait_readable = poll.wait_readable
local wait_writable = poll.wait_writable

--- @class net.stream.Socket : net.Socket
local Socket = {}

--- acceptconn
--- @return boolean enabled
--- @return error? err
function Socket:acceptconn()
    return self.sock:acceptconn()
end

--- oobinline
--- @param enable boolean
--- @return boolean enabled
--- @return error? err
function Socket:oobinline(enable)
    return self.sock:oobinline(enable)
end

--- keepalive
--- @param enable boolean
--- @return boolean enabled
--- @return error? err
function Socket:keepalive(enable)
    return self.sock:keepalive(enable)
end

--- tcpnodelay
--- @param enable boolean
--- @return boolean enabled
--- @return error? err
function Socket:tcpnodelay(enable)
    return self.sock:tcpnodelay(enable)
end

--- tcpcork
--- @param enable boolean
--- @return boolean enabled
--- @return error? err
function Socket:tcpcork(enable)
    return self.sock:tcpcork(enable)
end

--- tcpkeepalive
--- @param sec integer
--- @return integer? sec
--- @return error? err
function Socket:tcpkeepalive(sec)
    return self.sock:tcpkeepalive(sec)
end

--- tcpkeepintvl
--- @param sec integer
--- @return integer? sec
--- @return error? err
function Socket:tcpkeepintvl(sec)
    return self.sock:tcpkeepintvl(sec)
end

--- tcpkeepcnt
--- @param cnt integer
--- @return integer? cnt
--- @return error? err
function Socket:tcpkeepcnt(cnt)
    return self.sock:tcpkeepcnt(cnt)
end

--- sendfile
--- @param fd integer
--- @param bytes integer
--- @param offset integer
--- @return integer? len
--- @return error? err
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

        if not again then
            return sent, err
        end

        -- wait until writable
        local ok, perr, timeout = wait_writable(sock:fd(), self.snddeadl,
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
--- @return error? err
--- @return boolean? timeout
function Socket:sendfilesync(fd, bytes, offset)
    return self:syncwrite(self.sendfile, fd, bytes, offset)
end

Socket = require('metamodule').new.Socket(Socket, 'net.Socket')

--- @class net.stream.Server : net.stream.Socket
local Server = {}

--- new_connection
--- @param sock net.Socket
--- @param nonblock boolean
--- @return net.stream.Socket
--- @return error? err
function Server:new_connection(sock, nonblock)
    return Socket(sock, nonblock)
end

--- listen
--- @param backlog integer
--- @return boolean ok
--- @return error? err
function Server:listen(backlog)
    return self.sock:listen(backlog)
end

--- accept
--- @param with_ai? boolean
--- @return net.stream.Socket? csock
--- @return error? err
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
            return self:accepted(csock, self.nonblock, ai)
        elseif not again then
            return nil, err
        end

        -- wait until readable
        local ok, perr = wait_readable(sock:fd())
        if not ok then
            return nil, perr
        end
    end
end

--- accepted
--- @param sock net.stream.Socket
--- @param nonblock boolean
--- @param ai llsocket.addrinfo?
--- @return net.stream.Socket? csock
--- @return error? err
--- @return llsocket.addrinfo? ai
function Server:accepted(sock, nonblock, ai)
    return sock, nil, ai
end

--- acceptfd
--- @return integer? fd
--- @return error? err
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
        local ok, perr = wait_readable(self:fd())
        if not ok then
            return nil, perr
        end
    end
end

require('metamodule').new.Server(Server, 'net.stream.Socket')
