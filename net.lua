--
-- Copyright (C) 2014-2022 Masatoshi Fukunaga
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
-- net.lua
-- lua-net
-- Created by Masatoshi Teruya on 14/05/16.
--
--- assign to local
local pairs = pairs
local type = type
local find = string.find
local floor = math.floor
local is_finite = require('isa').finite
local poll = require('gpoll')
local wait_readable = poll.wait_readable
local wait_writable = poll.wait_writable
local unwait_readable = poll.unwait_readable
local unwait_writable = poll.unwait_writable
local unwait = poll.unwait
local read_lock = poll.read_lock
local read_unlock = poll.read_unlock
local write_lock = poll.write_lock
local write_unlock = poll.write_unlock
local llsocket = require('llsocket')
--- constants
local SHUT_RD = llsocket.SHUT_RD
local SHUT_WR = llsocket.SHUT_WR
local SHUT_RDWR = llsocket.SHUT_RDWR

--- @class net.Socket
local Socket = {}

--[[
function Socket:__newindex( prop )
    error( ('attempt to access unknown property: %q'):format( prop ), 2 )
end
--]]

--- init
--- @param sock llsocket.socket
--- @param nonblock boolean
--- @param tls? userdata
--- @return net.Socket? self
function Socket:init(sock, nonblock, tls)
    self.sock = sock
    self.nonblock = nonblock
    self.tls = tls
    return self
end

--- onwaithook
--- @param self net.Socket
--- @param name string
--- @param fn? function
--- @param ctx? any
--- @return function? fn
local function onwaithook(self, name, fn, ctx)
    if fn ~= nil and type(fn) ~= 'function' then
        error('fn must be function', 2)
    end

    local oldfn = self[name]

    if fn then
        self[name] = fn
        self[name .. 'ctx'] = ctx
    else
        self[name] = nil
        self[name .. 'ctx'] = nil
    end

    return oldfn
end

--- onwait_readable
--- @param fn? function
--- @param ctx? any
--- @return function? fn
function Socket:onwait_readable(fn, ctx)
    return onwaithook(self, 'rcvhook', fn, ctx)
end

--- onwait_writable
--- @param fn? function
--- @param ctx? any
--- @return function? fn
function Socket:onwait_writable(fn, ctx)
    return onwaithook(self, 'sndhook', fn, ctx)
end

--- fd
--- @return integer fd
function Socket:fd()
    return self.sock:fd()
end

--- family
--- @return string af
function Socket:family()
    return self.sock:family()
end

--- sockname
--- @return llsocket.addrinfo? ai
--- @return error? err
function Socket:getsockname()
    return self.sock:getsockname()
end

--- peername
--- @return llsocket.addrinfo? ai
--- @return error? err
function Socket:getpeername()
    return self.sock:getpeername()
end

--- closer
--- @return boolean ok
--- @return error? err
function Socket:closer()
    if self.nonblock then
        unwait_readable(self:fd())
    end
    return self.sock:shutdown(SHUT_RD)
end

--- closew
--- @return boolean ok
--- @return error? err
function Socket:closew()
    if self.nonblock then
        unwait_writable(self:fd())
    end
    return self.sock:shutdown(SHUT_WR)
end

--- close
--- @param shutrd boolean
--- @param shutwr boolean
--- @return boolean ok
--- @return error? err
function Socket:close(shutrd, shutwr)
    if shutrd ~= nil and type(shutrd) ~= 'boolean' then
        error('shutrd must be boolean', 2)
    elseif shutwr ~= nil and type(shutwr) ~= 'boolean' then
        error('shutwr must be boolean', 2)
    end

    if self.nonblock then
        unwait(self:fd())
    end

    if shutrd and shutwr then
        return self.sock:close(SHUT_RDWR)
    elseif shutrd then
        return self.sock:close(SHUT_RD)
    elseif shutwr then
        return self.sock:close(SHUT_WR)
    end

    return self.sock:close()
end

--- atmark
--- @return boolean? ok
--- @return error? err
function Socket:atmark()
    return self.sock:atmark()
end

--- cloexec
--- @param enable boolean
--- @return boolean? enabled
--- @return error? err
function Socket:cloexec(enable)
    return self.sock:cloexec(enable)
end

--- isnonblock
--- @return boolean enabled
function Socket:isnonblock()
    return self.nonblock
end

--- socktype
--- @return integer socktype
function Socket:socktype()
    return self.sock:socktype()
end

--- protocol
--- @return integer protocol
function Socket:protocol()
    return self.sock:protocol()
end

--- error
--- @return error? errstr
--- @return error? err
function Socket:error()
    local soerr, err = self.sock:error()

    if err then
        return nil, err
    elseif soerr then
        return soerr
    end
end

--- reuseport
--- @param enable boolean
--- @return boolean? enabled
--- @return error? err
function Socket:reuseport(enable)
    return self.sock:reuseport(enable)
end

--- reuseaddr
--- @param enable boolean
--- @return boolean? enabled
--- @return error? err
function Socket:reuseaddr(enable)
    return self.sock:reuseaddr(enable)
end

--- debug
--- @param enable boolean
--- @return string? enabled
--- @return error? err
function Socket:debug(enable)
    return self.sock:debug(enable)
end

--- dontroute
--- @param enable boolean
--- @return boolean? enabled
--- @return error? err
function Socket:dontroute(enable)
    return self.sock:dontroute(enable)
end

--- timestamp
--- @param enable boolean
--- @return boolean? enabled
--- @return error? err
function Socket:timestamp(enable)
    return self.sock:timestamp(enable)
end

--- rcvbuf
--- @param nbyte integer
--- @return integer? nbyte
--- @return error? err
function Socket:rcvbuf(nbyte)
    return self.sock:rcvbuf(nbyte)
end

--- rcvlowat
--- @param nbyte integer
--- @return integer? nbyte
--- @return error? err
function Socket:rcvlowat(nbyte)
    return self.sock:rcvlowat(nbyte)
end

--- sndbuf
--- @param nbyte integer
--- @return integer? nbyte
--- @return error? err
function Socket:sndbuf(nbyte)
    return self.sock:sndbuf(nbyte)
end

--- sndlowat
--- @param nbyte integer
--- @return integer? nbyte
--- @return error? err
function Socket:sndlowat(nbyte)
    return self.sock:sndlowat(nbyte)
end

--- settimeo
--- @param sec number
--- @return number? sec
--- @return error? err
--- @return integer? deadl
local function settimeo(sock, fn, sec)
    local old, err, deadl

    if sec == nil then
        old, err = fn(sock)
    elseif not is_finite(sec) then
        error('sec must be finite-number', 3)
    elseif sec == 0 then
        old, err = fn(sock, 0)
    else
        old, err = fn(sock, sec)
        -- convert seconds to milliseconds
        deadl = floor(sec * 1000)
    end

    if err then
        return nil, err
    end

    return old, nil, deadl
end

--- rcvtimeo
--- @param sec number
--- @return number? sec
--- @return error? err
function Socket:rcvtimeo(sec)
    local old, err, deadl = settimeo(self.sock, self.sock.rcvtimeo, sec)

    if err then
        return nil, err
    elseif self.nonblock then
        self.rcvdeadl = deadl
    end

    return old
end

--- sndtimeo
--- @param sec number
--- @return number? sec
--- @return error? err
function Socket:sndtimeo(sec)
    local old, err, deadl = settimeo(self.sock, self.sock.sndtimeo, sec)

    if err then
        return nil, err
    elseif self.nonblock then
        self.snddeadl = deadl
    end

    return old
end

--- linger
--- @param sec integer
--- @return integer? sec
--- @return error? err
function Socket:linger(sec)
    return self.sock:linger(sec)
end

--- syncread
--- @param fn function
--- @vararg any arguments
--- @return any? val
--- @return error? err
--- @return boolean? timeout
--- @return any? extra
function Socket:syncread(fn, ...)
    -- wait until another coroutine releases the right to read
    local fd = self.sock:fd()
    local ok, err, timeout = read_lock(fd, self.rcvdeadl)
    local v, extra

    if ok then
        v, err, timeout, extra = fn(self, ...)
        read_unlock(fd)
    end

    return v, err, timeout, extra
end

--- read
--- @param bufsize integer
--- @return string? msg
--- @return error? err
--- @return boolean? timeout
function Socket:read(bufsize)
    local sock, read = self.sock, self.sock.read

    while true do
        local str, err, again = read(sock, bufsize)

        if not again then
            return str, err
        end

        -- wait until readable
        local ok, perr, timeout = wait_readable(sock:fd(), self.rcvdeadl,
                                                self.rcvhook, self.rcvhookctx)
        if not ok then
            return nil, perr, timeout
        end
    end
end

--- readsync
--- @param bufsize integer
--- @return string? msg
--- @return error? err
--- @return boolean? timeout
function Socket:readsync(bufsize)
    return self:syncread(self.read, bufsize)
end

--- recv
--- @param bufsize integer
--- @vararg integer flags
--- @return string? msg
--- @return error? err
--- @return boolean? timeout
function Socket:recv(bufsize, ...)
    local sock, recv = self.sock, self.sock.recv

    while true do
        local str, err, again = recv(sock, bufsize, ...)

        if not again then
            return str, err
        end

        -- wait until readable
        local ok, perr, timeout = wait_readable(sock:fd(), self.rcvdeadl,
                                                self.rcvhook, self.rcvhookctx)
        if not ok then
            return nil, perr, timeout
        end
    end
end

--- recvsync
--- @param bufsize integer
--- @vararg integer flags
--- @return string? msg
--- @return error? err
--- @return boolean? timeout
function Socket:recvsync(bufsize, ...)
    return self:syncread(self.recv, bufsize, ...)
end

--- recvmsg
--- @param mh net.MsgHdr
--- @vararg integer flags
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:recvmsg(mh, ...)
    local sock, recvmsg = self.sock, self.sock.recvmsg

    while true do
        local len, err, again = recvmsg(sock, mh.msg, ...)

        if not again then
            return len, err
        end

        -- wait until readable
        local ok, perr, timeout = wait_readable(sock:fd(), self.rcvdeadl,
                                                self.rcvhook, self.rcvhookctx)
        if not ok then
            return nil, perr, timeout
        end
    end
end

--- recvmsgsync
--- @param mh net.MsgHdr
--- @vararg integer flags
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:recvmsgsync(mh, ...)
    return self:syncread(self.recvmsg, mh, ...)
end

--- readv
--- @param iov iovec
--- @param offset? integer
--- @param nbyte? integer
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:readv(iov, offset, nbyte)
    local sock, readv = self.sock, iov.readv

    if offset == nil then
        offset = 0
    end

    while true do
        local len, err, again = readv(iov, sock:fd(), offset, nbyte)

        if not again then
            return len, err
        end

        -- wait until readable
        local ok, perr, timeout = wait_readable(sock:fd(), self.rcvdeadl,
                                                self.rcvhook, self.rcvhookctx)
        if not ok then
            return nil, perr, timeout
        end
    end
end

--- readvsync
--- @param iov iovec
--- @param offset? integer
--- @param nbyte? integer
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:readvsync(iov, offset, nbyte)
    return self:syncread(self.readv, iov, offset, nbyte)
end

--- syncwrite
--- @param fn function
--- @vararg any arguments
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:syncwrite(fn, ...)
    -- wait until another coroutine releases the right to write
    local fd = self.sock:fd()
    local ok, err, timeout = write_lock(fd, self.snddeadl)
    local len = 0

    if ok then
        len, err, timeout = fn(self, ...)
        write_unlock(fd)
    end

    return len, err, timeout
end

--- write
--- @param str string
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:write(str)
    local sent = 0
    local sock, write = self.sock, self.sock.write

    while true do
        local len, err, again = write(sock, str)

        if not len then
            return nil, err
        end
        -- update a bytes sent
        sent = sent + len

        if not again then
            return sent
        end

        -- wait until writable
        local ok, perr, timeout = wait_writable(sock:fd(), self.snddeadl,
                                                self.sndhook, self.sndhookctx)
        if not ok then
            return sent, perr, timeout
        end

        str = str:sub(len + 1)
    end
end

--- writesync
--- @param str string
--- @vararg integer flags
--- @return integer? len
--- @return string? err
--- @return boolean? timeout
function Socket:writesync(str)
    return self:syncwrite(self.write, str)
end

--- send
--- @param str string
--- @vararg integer flags
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:send(str, ...)
    local sent = 0
    local sock, send = self.sock, self.sock.send

    while true do
        local len, err, again = send(sock, str, ...)

        if not len then
            return nil, err
        end
        -- update a bytes sent
        sent = sent + len

        if not again then
            return sent
        end

        -- wait until writable
        local ok, perr, timeout = wait_writable(sock:fd(), self.snddeadl,
                                                self.sndhook, self.sndhookctx)
        if not ok then
            return sent, perr, timeout
        end

        str = str:sub(len + 1)
    end
end

--- sendsync
--- @param str string
--- @vararg integer flags
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:sendsync(str, ...)
    return self:syncwrite(self.send, str, ...)
end

--- sendmsg
--- @param mh net.MsgHdr
--- @vararg integer flags
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:sendmsg(mh, ...)
    local sock, sendmsg = self.sock, self.sock.sendmsg
    local iov = mh.iov
    local sent = 0

    while true do
        local len, err, again = sendmsg(sock, mh.msg, ...)

        if not len then
            return nil, err
        elseif len > 0 then
            -- update a bytes sent
            sent = sent + len
            iov:consume(len)
        end

        if not again then
            return sent
        end

        -- wait until writable
        local ok, perr, timeout = wait_writable(sock:fd(), self.snddeadl,
                                                self.sndhook, self.sndhookctx)
        if not ok then
            return sent, perr, timeout
        end
    end
end

--- sendmsgsync
--- @param mh net.MsgHdr
--- @vararg integer flags
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:sendmsgsync(mh, ...)
    return self:syncwrite(self.sendmsg, mh, ...)
end

--- writev
--- @param iov iovec
--- @param offset? integer
--- @param nbyte? integer
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:writev(iov, offset, nbyte)
    local sock, writev = self.sock, iov.writev
    local sent = 0

    if offset == nil then
        offset = 0
    end

    while true do
        local len, err, again = writev(iov, sock:fd(), offset, nbyte)

        if not len then
            return nil, err
        elseif len > 0 then
            -- update a bytes sent
            sent = sent + len
            offset = offset + len
        end

        if not again then
            return sent, err
        end

        -- wait until writable
        local ok, perr, timeout = wait_writable(sock:fd(), self.snddeadl,
                                                self.sndhook, self.sndhookctx)
        if not ok then
            return sent, perr, timeout
        end
    end
end

--- writevsync
--- @param iov iovec
--- @param offset? integer
--- @param nbyte? integer
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:writevsync(iov, offset, nbyte)
    return self:syncwrite(self.writev, iov, offset, nbyte)
end

require('metamodule').new.Socket(Socket)

--- net module table
local _M = {}
-- exports llsocket constants
for k, v in pairs(llsocket) do
    if find(k, '^%u+') and type(v) == 'number' then
        _M[k] = v
    end
end

return _M
