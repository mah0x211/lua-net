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
local assert = assert
local is_int = require('isa').int
local iovec_new = require('iovec').new
local msghdr_new = require('llsocket.msghdr').new
local cmsghdrs_new = require('llsocket.cmsghdrs').new

--- @class net.MsgHdr
--- @field msg userdata
local MsgHdr = {}

--- init
--- @return net.MsgHdr
function MsgHdr:init()
    self.msg = msghdr_new()
    return self
end

--- name
--- @param ai? llsocket.addrinfo
--- @return llsocket.addrinfo? ai
function MsgHdr:name(ai)
    return self.msg:name(ai)
end

--- control
--- @return userdata? cmsgs
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
    assert(is_int(bytes), 'bytes must be int')
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
    assert(is_int(idx), 'idx must be int')
    if self.iov then
        return self.iov:get(idx)
    end

    return nil
end

--- del
--- @param idx integer
--- @return string? str
function MsgHdr:del(idx)
    assert(is_int(idx), 'idx must be int')
    if self.iov then
        return self.iov:del(idx)
    end

    return nil
end

MsgHdr = require('metamodule').new.MsgHdr(MsgHdr)

return {
    new = MsgHdr,
}

