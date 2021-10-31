--[[

  Copyright (C) 2014 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.


  net.lua
  lua-net
  Created by Masatoshi Teruya on 14/05/16.

--]] --- assign to local
local assert = assert
local pairs = pairs
local type = type
local find = string.find
local floor = math.floor
local is_uint = require('isa').uint
local strerror = require('net.syscall').strerror
local poll = require('net.poll')
local waitrecv = poll.waitrecv
local waitsend = poll.waitsend
local unwaitrecv = poll.unwaitrecv
local unwaitsend = poll.unwaitsend
local unwait = poll.unwait
local recvsync = poll.recvsync
local sendsync = poll.sendsync
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
--- @return net.Socket? self
--- @return string? err
function Socket:init(sock, nonblock)
    self.sock = sock
    self.nonblock = nonblock
    return self
end

--- deadlines
--- @param rcvdeadl? integer
--- @param snddeadl? integer
--- @return integer? rcvdeadl
--- @return integer? snddeadl
function Socket:deadlines(rcvdeadl, snddeadl)
    -- verify
    assert(rcvdeadl == nil or is_uint(rcvdeadl), 'rcvdeadl must be uint')
    assert(snddeadl == nil or is_uint(snddeadl), 'snddeadl must be uint')

    -- set socket timeout
    if not self.nonblock then
        if rcvdeadl then
            -- set rcvtimeo
            local _, err = self:rcvtimeo(rcvdeadl / 1000)
            assert(not err, err)
        else
            -- get rcvtimeo
            rcvdeadl = floor(assert(self:rcvtimeo()) * 1000)
        end

        if snddeadl then
            -- set sndtimeo
            local _, err = self:sndtimeo(snddeadl / 1000)
            assert(not err, err)
        else
            -- get sndtimeo
            snddeadl = floor(assert(self:sndtimeo()) * 1000)
        end

        return rcvdeadl, snddeadl
    end

    -- set to rcvdeadl and snddeadl properties if non-blocking mode
    if rcvdeadl then
        -- disable recv deadline
        if rcvdeadl == 0 then
            self.rcvdeadl = nil
        else
            self.rcvdeadl = rcvdeadl
        end
    end

    if snddeadl then
        -- disable send deadline
        if snddeadl == 0 then
            self.snddeadl = nil
        else
            self.snddeadl = snddeadl
        end
    end

    return self.rcvdeadl, self.snddeadl
end

--- onwaithook
--- @param self net.Socket
--- @param name string
--- @param fn? function
--- @param ctx? any
--- @return function? fn
local function onwaithook(self, name, fn, ctx)
    assert(fn == nil or type(fn) == 'function', 'fn must be function')
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

--- onwaitrecv
--- @param fn? function
--- @param ctx? any
--- @return function? fn
function Socket:onwaitrecv(fn, ctx)
    return onwaithook(self, 'rcvhook', fn, ctx)
end

--- onwaitsend
--- @param fn? function
--- @param ctx? any
--- @return function? fn
function Socket:onwaitsend(fn, ctx)
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
--- @return string? err
function Socket:getsockname()
    return self.sock:getsockname()
end

--- peername
--- @return llsocket.addrinfo? ai
--- @return string? err
function Socket:getpeername()
    return self.sock:getpeername()
end

--- closer
--- @return boolean ok
--- @return string? err
function Socket:closer()
    if self.nonblock then
        unwaitrecv(self:fd())
    end

    return self.sock:shutdown(SHUT_RD)
end

--- closew
--- @return boolean ok
--- @return string? err
function Socket:closew()
    if self.nonblock then
        unwaitsend(self:fd())
    end

    return self.sock:shutdown(SHUT_WR)
end

--- close
--- @param shutrd boolean
--- @param shutwr boolean
--- @return boolean ok
--- @return string? err
function Socket:close(shutrd, shutwr)
    assert(shutrd == nil or type(shutrd) == 'boolean', 'shutrd must be boolean')
    assert(shutwr == nil or type(shutwr) == 'boolean', 'shutwr must be boolean')
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
--- @return string? err
function Socket:atmark()
    return self.sock:atmark()
end

--- cloexec
--- @param enable boolean
--- @return boolean? enabled
--- @return string? err
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
--- @return string? errstr
--- @return string? err
function Socket:error()
    local errno, err = self.sock:error()

    if err then
        return nil, err
    elseif errno ~= 0 then
        return strerror(errno)
    end
end

--- reuseport
--- @param enable boolean
--- @return boolean? enabled
--- @return string? err
function Socket:reuseport(enable)
    return self.sock:reuseport(enable)
end

--- reuseaddr
--- @param enable boolean
--- @return boolean? enabled
--- @return string? err
function Socket:reuseaddr(enable)
    return self.sock:reuseaddr(enable)
end

--- debug
--- @param enable boolean
--- @return string? enabled
--- @return string? err
function Socket:debug(enable)
    return self.sock:debug(enable)
end

--- dontroute
--- @param enable boolean
--- @return boolean? enabled
--- @return string? err
function Socket:dontroute(enable)
    return self.sock:dontroute(enable)
end

--- timestamp
--- @param enable boolean
--- @return boolean? enabled
--- @return string? err
function Socket:timestamp(enable)
    return self.sock:timestamp(enable)
end

--- rcvbuf
--- @param nbyte integer
--- @return integer? nbyte
--- @return string? err
function Socket:rcvbuf(nbyte)
    return self.sock:rcvbuf(nbyte)
end

--- rcvlowat
--- @param nbyte integer
--- @return integer? nbyte
--- @return string? err
function Socket:rcvlowat(nbyte)
    return self.sock:rcvlowat(nbyte)
end

--- sndbuf
--- @param nbyte integer
--- @return integer? nbyte
--- @return string? err
function Socket:sndbuf(nbyte)
    return self.sock:sndbuf(nbyte)
end

--- sndlowat
--- @param nbyte integer
--- @return integer? nbyte
--- @return string? err
function Socket:sndlowat(nbyte)
    return self.sock:sndlowat(nbyte)
end

--- rcvtimeo
--- @param sec number
--- @return number? sec
--- @return string? err
function Socket:rcvtimeo(sec)
    return self.sock:rcvtimeo(sec)
end

--- sndtimeo
--- @param sec number
--- @return number? sec
--- @return string? err
function Socket:sndtimeo(sec)
    return self.sock:sndtimeo(sec)
end

--- linger
--- @param sec integer
--- @return integer? sec
--- @return string? err
function Socket:linger(sec)
    return self.sock:linger(sec)
end

--- recv
--- @param bufsize integer
--- @vararg integer flags
--- @return string? msg
--- @return string? err
--- @return boolean? timeout
function Socket:recv(bufsize, ...)
    local sock, recv = self.sock, self.sock.recv

    while true do
        local str, err, again = recv(sock, bufsize, ...)

        if not again or not self.nonblock then
            return str, err, again
        end

        -- wait until readable
        local ok, perr, timeout = waitrecv(sock:fd(), self.rcvdeadl,
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
--- @return string? err
--- @return boolean? timeout
function Socket:recvsync(bufsize, ...)
    return recvsync(self, self.recv, bufsize, ...)
end

--- recvmsg
--- @param mh net.MsgHdr
--- @vararg integer flags
--- @return integer? len
--- @return string? err
--- @return boolean? timeout
function Socket:recvmsg(mh, ...)
    local sock, recvmsg = self.sock, self.sock.recvmsg

    while true do
        local len, err, again = recvmsg(sock, mh.msg, ...)

        if not again or not self.nonblock then
            return len, err, again
        end

        -- wait until readable
        local ok, perr, timeout = waitrecv(sock:fd(), self.rcvdeadl,
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
--- @return string? err
--- @return boolean? timeout
function Socket:recvmsgsync(mh, ...)
    return recvsync(self, self.recvmsg, mh, ...)
end

--- send
--- @param str string
--- @vararg integer flags
--- @return integer? len
--- @return string? err
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

        if not again or not self.nonblock then
            return sent, err, again
        end

        -- wait until writable
        local ok, perr, timeout = waitsend(sock:fd(), self.snddeadl,
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
--- @return string? err
--- @return boolean? timeout
function Socket:sendsync(str, ...)
    return sendsync(self, self.send, str, ...)
end

--- sendmsg
--- @param mh net.MsgHdr
--- @vararg integer flags
--- @return integer? len
--- @return string? err
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

        if not again or not self.nonblock then
            return sent, err, again
        end

        -- wait until writable
        local ok, perr, timeout = waitsend(sock:fd(), self.snddeadl,
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
--- @return string? err
--- @return boolean? timeout
function Socket:sendmsgsync(mh, ...)
    return sendsync(self, self.sendmsg, mh, ...)
end

--- writev
--- @param iov iovec
--- @param offset integer
--- @return integer? len
--- @return string? err
--- @return boolean? timeout
function Socket:writev(iov, offset)
    local sock, writev = self.sock, self.sock.writev
    local sent = 0

    if offset == nil then
        offset = 0
    end

    while true do
        local len, err, again = writev(iov, sock:fd(), offset)

        if not len then
            return nil, err
        elseif len > 0 then
            -- update a bytes sent
            sent = sent + len
            offset = offset + len
        end

        if not again or not self.nonblock then
            return sent, err, again
        end

        -- wait until writable
        local ok, perr, timeout = waitsend(sock:fd(), self.snddeadl,
                                           self.sndhook, self.sndhookctx)
        if not ok then
            return sent, perr, timeout
        end
    end
end

--- writevsync
--- @param iov iovec
--- @param offset integer
--- @return integer? len
--- @return string? err
--- @return boolean? timeout
function Socket:writevsync(iov, offset, ...)
    return sendsync(self, self.writev, iov, offset, ...)
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
