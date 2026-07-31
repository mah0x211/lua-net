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
local format = string.format
local tostring = tostring
local new_errno = require('errno').new
local new_deadline = require('time.clock.deadline').new
--- constants
local WANT_POLLIN = require('net.tls.context').WANT_READ
local WANT_POLLOUT = require('net.tls.context').WANT_WRITE

--- @class net.tls.Socket : net.Socket
local Socket = {}

--- bio_fill
--- @private
--- @param sec number?
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Socket:bio_fill(sec)
    local bio = self.tls_bio
    if not bio then
        return true
    end

    local deadline = sec and new_deadline(sec)
    while true do
        if deadline then
            sec = deadline:remain()
            if sec <= 0 then
                return false, nil, true
            end
        end

        local n, err, again = bio:fill()
        if n then
            return true
        elseif not again then
            return false, err
        end

        local ok, timeout
        ok, err, timeout = self:wait_readable(sec)
        if not ok then
            return false, err, timeout
        end
        -- do read again
    end
end

--- bio_drain
--- @private
--- @param sec number?
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Socket:bio_drain(sec)
    local bio = self.tls_bio
    if not bio then
        return true
    end

    local deadline = sec and new_deadline(sec)
    while true do
        if deadline then
            sec = deadline:remain()
            if sec <= 0 then
                return false, nil, true
            end
        end

        local n, err, again = bio:drain()
        if n then
            return true
        elseif not again then
            return false, err
        end

        local ok, timeout
        ok, err, timeout = self:wait_writable(sec)
        if not ok then
            return false, err, timeout
        end
        -- do write again
    end
end

--- poll_wait
--- @param want integer
--- @param sec number?
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Socket:poll_wait(want, sec)
    -- wait by poll function
    if want == WANT_POLLIN then
        -- if use BIO, drain any pending encrypted record(s) to fd first (the
        -- peer may be waiting for our outgoing data, e.g. handshake flights),
        -- then fill the buffer with newly received ciphertext(s) from fd.
        if self.tls_bio then
            local ok, err, timeout = self:bio_drain(sec)
            if not ok then
                return false, err, timeout
            end
            return self:bio_fill(sec)
        end
        return self:wait_readable(sec)
    elseif want == WANT_POLLOUT then
        -- if use BIO, drain the newly encrypted record(s) to fd
        if self.tls_bio then
            return self:bio_drain(sec)
        end
        return self:wait_writable(sec)
    end
    return false,
           new_errno('EINVAL', format('unknown want type %q', tostring(want)))
end

--- closer
--- @return boolean ok
--- @return any err
function Socket:closer()
    -- the tls socket cannot be partially shut down
    -- EOPNOTSUPP: Operation not supported on socket
    return false, new_errno('EOPNOTSUPP')
end

--- closew
--- @return boolean ok
--- @return any err
function Socket:closew()
    -- the tls socket cannot be partially shut down
    -- EOPNOTSUPP: Operation not supported on socket
    return false, new_errno('EOPNOTSUPP')
end

--- tls_close
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Socket:tls_close()
    local tls, close = self.tls, self.tls.close
    local deadline = self:get_send_deadline()

    while true do
        local ok, err, want = close(tls)
        local timeout

        if not want then
            if not ok then
                -- close failed
                return false, err
            end

            -- close succeeded
            -- if use BIO, drain the newly encrypted record(s) to fd
            local done, sec = deadline:is_done()
            if done then
                return false, nil, true
            end
            ok, err, timeout = self:bio_drain(sec)
            if not ok then
                return false, err, timeout
            end
            return true
        end

        local done, sec = deadline:is_done()
        if done then
            return false, nil, true
        end

        ok, err, timeout = self:poll_wait(want, sec)
        if not ok then
            return false, err, timeout
        end
        -- do close again
    end
end

--- close
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Socket:close()
    -- dispose io-events
    local ok, err, timeout = self:tls_close()
    if not ok then
        self.sock:close()
        return ok, err, timeout
    end

    return self.sock:close()
end

--- get_alpn
--- Returns the protocol negotiated via ALPN, or nil if none was negotiated.
--- Must be called after the handshake completes.
--- @return string? protocol
function Socket:get_alpn()
    return self.tls:get_alpn()
end

--- handshake
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Socket:handshake()
    if self.handshaked then
        return true
    end

    local tls, handshake = self.tls, self.tls.handshake
    local deadline = self:get_send_deadline()

    while true do
        local ok, err, want = handshake(tls)
        local timeout

        if not want then
            if not ok then
                -- handshake failed
                return false, err
            end

            -- handshake succeeded
            -- if use BIO, drain the newly encrypted record(s) to fd
            local done, sec = deadline:is_done()
            if done then
                return false, nil, true
            end
            self.handshaked, err, timeout = self:bio_drain(sec)
            return self.handshaked, err, timeout
        end

        local done, sec = deadline:is_done()
        if done then
            return false, nil, true
        end

        ok, err, timeout = self:poll_wait(want, sec)
        if not ok then
            -- error or timeout occurred
            return false, err, timeout
        end
        -- do handshake again
    end
end

--- read
--- @param bufsize integer
--- @return string? msg
--- @return any err
--- @return boolean? timeout
function Socket:read(bufsize)
    local deadline = self:get_recv_deadline()

    -- perform handshake if not yet
    if not self.handshaked then
        local ok, err, timeout = self:handshake()
        if not ok then
            return nil, err, timeout
        end
    end

    local sock, read = self.tls, self.tls.read
    -- NOTE: in the edge trigger mode on macOS with kqueue,
    -- If the read function returns WANT_POLLIN several times, the event will
    -- no longer occur.
    -- As a workaround, after waiting for an event, call the read function
    -- several times to ensure that the event occurs.
    local nread = 0

    while true do
        local done, sec = deadline:is_done()
        if done then
            return nil, nil, true
        end

        nread = nread + 1
        local str, err, want = read(sock, bufsize)
        local ok, timeout

        if not want then
            if not str then
                -- read failed
                return nil, err
            end

            -- read succeeded
            -- if use BIO, drain the newly encrypted record(s) to fd
            ok, err, timeout = self:bio_drain(sec)
            if not ok then
                return nil, err, timeout
            end
            return str
        end

        if nread > 5 then
            nread = 0
            ok, err, timeout = self:poll_wait(want, sec)
            if not ok then
                return nil, err, timeout
            end
        end
        -- do read again
    end
end

--- recv
--- @param bufsize integer
--- @return string? msg
--- @return any err
--- @return boolean? timeout
function Socket:recv(bufsize)
    return self:read(bufsize)
end

--- recvmsg
--- @return table? msg { data:string?, cmsgs:table[]?, addr:addrinfo? }
--- @return any err
function Socket:recvmsg()
    -- currently, does not support recvmsg on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, new_errno('EOPNOTSUPP')
end

--- readv
--- @return integer? len
--- @return any err
function Socket:readv()
    -- currently, does not support readv on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, new_errno('EOPNOTSUPP')
end

--- write
--- @param str string
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Socket:write(str)
    local deadline = self:get_send_deadline()

    -- perform handshake if not yet
    if not self.handshaked then
        local ok, err, timeout = self:handshake()
        if not ok then
            return 0, err, timeout
        end
    end

    local sock, write = self.tls, self.tls.write
    local sent = 0

    while true do
        local done, sec = deadline:is_done()
        if done then
            return sent, nil, true
        end

        local len, err, want = write(sock, str)
        if not len then
            return nil, err
        end
        -- update a bytes sent
        sent = sent + len

        local ok, timeout
        if not want then
            -- write succeeded
            -- if use BIO, drain the newly encrypted record(s) to fd
            ok, err, timeout = self:bio_drain(sec)
            if not ok then
                return nil, err, timeout
            end
            return sent
        end

        ok, err, timeout = self:poll_wait(want, sec)
        if not ok then
            return sent, err, timeout
        end

        str = str:sub(len + 1)
        -- do write again
    end
end

--- send
--- @param str string
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Socket:send(str)
    return self:write(str)
end

--- sendmsg
--- @return integer? len
--- @return any err
function Socket:sendmsg()
    -- currently, does not support sendmsg on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, new_errno('EOPNOTSUPP')
end

--- writev
--- @return integer? len
--- @return any err
function Socket:writev()
    -- currently, does not support sendmsg on tls connection
    -- EOPNOTSUPP: Operation not supported on socket
    return nil, new_errno('EOPNOTSUPP')
end

require('metamodule').new.Socket(Socket, 'net.Socket')

