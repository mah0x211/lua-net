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
--- assign to local
local clock = os.clock
local pairs = pairs
local type = type
local find = string.find
local format = string.format
local tostring = tostring
local new_errno = require('errno').new
local is_unsigned = require('isa').unsigned
local poll = require('gpoll')
local wait_readable = poll.wait_readable
local wait_writable = poll.wait_writable
local unwait = poll.unwait
--- constants
local libtls = require('libtls')
local WANT_POLLIN = libtls.WANT_POLLIN
local WANT_POLLOUT = libtls.WANT_POLLOUT
local DEFAULT_CLOCK_LIMIT = 0.01

--- @class net.tls.Socket : net.Socket
local Socket = {}

--- setclocklimit
--- @param sec number
function Socket:setclocklimit(sec)
    if sec ~= nil and not is_unsigned(sec) then
        error('sec must be unsigned number', 2)
    end
    self.clocklimit = sec or DEFAULT_CLOCK_LIMIT
end

--- getclocklimit
--- @return number sec
function Socket:getclocklimit()
    if not self.clocklimit then
        self.clocklimit = DEFAULT_CLOCK_LIMIT
    end
    return self.clocklimit
end

--- poll_wait
--- @param want integer
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
function Socket:poll_wait(want)
    -- wait by poll function
    if want == WANT_POLLIN then
        return wait_readable(self:fd(), self.rcvdeadl)
    elseif want == WANT_POLLOUT then
        return wait_writable(self:fd(), self.snddeadl)
    end
    return false,
           new_errno('EINVAL', format('unknown want type %q', tostring(want)))
end

--- closer
--- @return boolean ok
--- @return error err
function Socket:closer()
    -- the tls socket cannot be partially shut down
    -- EOPNOTSUPP: Operation not supported on socket
    return false, new_errno('EOPNOTSUPP')
end

--- closew
--- @return boolean ok
--- @return error err
function Socket:closew()
    -- the tls socket cannot be partially shut down
    -- EOPNOTSUPP: Operation not supported on socket
    return false, new_errno('EOPNOTSUPP')
end

--- tls_close
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
function Socket:tls_close()
    local tls, close = self.tls, self.tls.close
    local clocklimit = self:getclocklimit()
    local cost = clock()

    while true do
        local ok, err, want = close(tls)

        if not want then
            return ok, err
        elseif self.nonblock then
            local timeout

            ok, err, timeout = self:poll_wait(want)
            if not ok then
                return false, err, timeout
            end
        elseif clock() - cost >= clocklimit then
            -- busy loop timed out
            return false, new_errno('ETIMEDOUT'), true
        end
        -- do close again
    end
end

--- close
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
function Socket:close()
    if self.nonblock then
        unwait(self:fd())
    end

    local ok, err, timeout = self:tls_close()
    if not ok then
        self.sock:close()
        return ok, err, timeout
    end

    return self.sock:close()
end

--- handshake
--- @return boolean ok
--- @return error? err
--- @return boolean? timeout
function Socket:handshake()
    if self.handshaked then
        return true
    end

    local tls, handshake = self.tls, self.tls.handshake
    local clocklimit = self:getclocklimit()
    local cost = clock()

    while true do
        local ok, err, want = handshake(tls)

        if not want then
            self.handshaked = ok
            return ok, err
        elseif self.nonblock then
            local timeout
            ok, err, timeout = self:poll_wait(want)
            if not ok then
                -- error or timeout occurred
                return false, err, timeout
            end
        elseif clock() - cost >= clocklimit then
            -- busy loop timed out
            return false, new_errno('ETIMEDOUT'), true
        end
        -- do handshake again
    end
end

--- read
--- @param bufsize integer
--- @return string? msg
--- @return error? err
--- @return boolean? timeout
function Socket:read(bufsize)
    if not self.handshaked then
        local ok, err, timeout = self:handshake()
        if not ok then
            return nil, err, timeout
        end
    end

    local sock, read = self.tls, self.tls.read
    local clocklimit = self:getclocklimit()
    local cost = clock()

    while true do
        local str, err, _, want = read(sock, bufsize)

        if not want then
            return str, err
        elseif self.nonblock then
            local ok, perr, timeout = self:poll_wait(want)
            if not ok then
                return nil, perr, timeout
            end
        elseif clock() - cost >= clocklimit then
            -- busy loop timed out
            return nil, new_errno('ETIMEDOUT'), true
        end
        -- do read again
    end
end

--- recv
--- @param bufsize integer
--- @return string? msg
--- @return error? err
--- @return boolean? timeout
function Socket:recv(bufsize)
    return self:read(bufsize)
end

--- recvmsg
--- @return integer? len
--- @return error err
function Socket:recvmsg()
    -- currently, does not support recvmsg on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, new_errno('EOPNOTSUPP')
end

--- readv
--- @return integer? len
--- @return error err
function Socket:readv()
    -- currently, does not support readv on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, new_errno('EOPNOTSUPP')
end

--- write
--- @param str string
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:write(str)
    if not self.handshaked then
        local ok, err, timeout = self:handshake()
        if not ok then
            return 0, err, timeout
        end
    end

    local sock, write = self.tls, self.tls.write
    local clocklimit = self:getclocklimit()
    local sent = 0
    local cost = clock()

    while true do
        local len, err, again, want = write(sock, str)

        if not again then
            return len, err
        end
        -- update a bytes sent
        sent = sent + len

        --
        -- In the case of blocking file descriptors:
        --   the same function call should be repeated immediately.
        --
        -- In the case of non-blocking file descriptors:
        --   the same function call should be repeated when the required
        --   condition has been met.
        --
        if self.nonblock and want then
            local ok, perr, timeout = self:poll_wait(want)
            if not ok then
                return sent, perr, timeout
            end
        elseif clock() - cost >= clocklimit then
            return sent, new_errno('ETIMEDOUT'), true
        end

        str = str:sub(len + 1)
        -- do write again
    end
end

--- send
--- @param str string
--- @return integer? len
--- @return error? err
--- @return boolean? timeout
function Socket:send(str)
    return self:write(str)
end

--- sendmsg
--- @return integer? len
--- @return error err
function Socket:sendmsg()
    -- currently, does not support sendmsg on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, new_errno('EOPNOTSUPP')
end

--- writev
--- @return integer? len
--- @return error err
function Socket:writev()
    -- currently, does not support sendmsg on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, new_errno('EOPNOTSUPP')
end

require('metamodule').new.Socket(Socket, 'net.Socket')

-- exports libtls constants
local _M = {}
for k, v in pairs(libtls) do
    if find(k, '^%u+') and type(v) == 'number' then
        _M[k] = v
    end
end

return _M
