--
-- Copyright (C) 2014 Masatoshi Teruya
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
local is_int = require('isa').int

--- @class iovec
--- get a number of bytes used
--- @field bytes fun(self:iovec):integer
--- delete the specified number of bytes of data
--- @field consume fun(self:iovec, nbyte:integer):integer?
--- concatenate all data of elements in use into a string
--- @field concat fun(self:iovec, offset?:integer, nbyte?:integer):(str:string?, err:any)
--- add an element with specified string.
--- @field add fun(self:iovec, str:string):integer?
--- add an element that size of specified number of bytes
--- @field addn fun(self:iovec, nbyte:integer):(idx:integer?, err:any)
--- get a string of element at specified index.
--- @field get fun(self:iovec, idx:integer):string?
--- delete an element at specified index
--- @field del fun(self:iovec, idx:integer):string?
--- read the messages from fd into iovec
--- @field readv fun(self:iovec, fd:integer, offset?:integer, nbyte?:integer):(nbyte:integer?, err:any, again:boolean?)
--- write iovec messages at once to fd
--- @field writev fun(self:iovec, fd:integer, offset?:integer, nbyte?:integer):(nbyte:integer?, err:any, again:boolean?)

--- @type fun():iovec
local iovec_new = require('iovec').new

--- @class cmsghdrs

--- @class msghdr
--- @field name fun(self:msghdr, ai: addrinfo?):addrinfo?
--- @field control fun(self:msghdr, cmsgs: cmsghdrs?):cmsghdrs?
--- @field iov fun(self:msghdr, iov: iovec?):iovec

--- @type fun():msghdr
local msghdr_new = require('llsocket.msghdr').new
--- @type fun():cmsghdrs
local cmsghdrs_new = require('llsocket.cmsghdrs').new

--- @class net.MsgHdr
--- @field msg msghdr
--- @field iov iovec?
local MsgHdr = {}

--- init
--- @return net.MsgHdr
function MsgHdr:init()
    self.msg = msghdr_new()
    return self
end

--- name
--- @param ... addrinfo?
--- @return addrinfo? ai
function MsgHdr:name(...)
    return self.msg:name(...)
end

--- control
--- @return cmsghdrs? cmsgs
function MsgHdr:control()
    local cmsgs = self.msg:control()

    if cmsgs then
        return cmsgs
    end
    -- create new
    cmsgs = cmsghdrs_new()
    self.msg:control(cmsgs)

    return cmsgs
end

--- bytes
--- @return integer bytes
function MsgHdr:bytes()
    local iov = self.iov

    if iov then
        return iov:bytes()
    end

    return 0
end

--- consume
--- @param bytes integer
--- @return integer bytes
function MsgHdr:consume(bytes)
    if not is_int(bytes) then
        error('bytes must be int', 2)
    end

    local iov = self.iov
    if iov then
        return iov:consume(bytes)
    end

    return 0
end

--- concat
--- @return string? str
--- @return string? err
function MsgHdr:concat()
    local iov = self.iov

    if iov then
        return iov:concat()
    end

    return ''
end

--- add
--- @param str string
--- @return integer idx
--- @return string? err
function MsgHdr:add(str)
    -- create new iovec
    if not self.iov then
        self.iov = iovec_new()
        self.msg:iov(self.iov)
    end

    return self.iov:add(str)
end

--- addn
--- @param bytes integer
--- @return integer idx
--- @return string? err
function MsgHdr:addn(bytes)
    -- create new iovec
    if not self.iov then
        self.iov = iovec_new()
        self.msg:iov(self.iov)
    end

    return self.iov:addn(bytes)
end

--- get
--- @param idx integer
--- @return string? str
function MsgHdr:get(idx)
    if not is_int(idx) then
        error('idx must be int', 2)
    elseif self.iov then
        return self.iov:get(idx)
    end

    return nil
end

--- del
--- @param idx integer
--- @return string? str
function MsgHdr:del(idx)
    if not is_int(idx) then
        error('idx must be int', 2)
    elseif self.iov then
        return self.iov:del(idx)
    end

    return nil
end

MsgHdr = require('metamodule').new.MsgHdr(MsgHdr)

return {
    new = MsgHdr,
}

