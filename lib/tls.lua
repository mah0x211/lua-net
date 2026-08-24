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
--- @field private handshaked boolean
local Socket = {}

--- bio_fill core: use the caller's deadline object directly instead of
--- creating a fresh one so callers can share their total budget across
--- bio_drain / bio_fill / poll_wait iterations.
--- @param self net.tls.Socket
--- @param deadline time.clock.deadline
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
--- @return boolean? eof
local function bio_fill(self, deadline)
    local bio = self.tls_bio
    if not bio then
        return true
    end

    while true do
        if deadline:is_done() then
            return false, nil, true
        end

        local n, err, again, eof = bio:fill()
        if n then
            return true, nil, nil, eof
        elseif not again then
            return false, err, nil, eof
        end

        local done, sec = deadline:is_done()
        if done then
            return false, nil, true
        end

        local ok, timeout
        ok, err, timeout = self:wait_readable(sec)
        if not ok then
            return false, err, timeout
        end
        -- do read again
    end
end

--- bio_fill
--- If sec is omitted, the deadline falls back to rcvtimeo (or the default
--- max timeout when unset) so the EAGAIN path always has a deadline.
--- @private
--- @param sec number?
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
--- @return boolean? eof
function Socket:bio_fill(sec)
    local deadline = sec and new_deadline(sec) or self:get_recv_deadline()
    return bio_fill(self, deadline)
end

--- bio_drain core: same rationale as bio_fill.
--- @param self net.tls.Socket
--- @param deadline time.clock.deadline
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
local function bio_drain(self, deadline)
    local bio = self.tls_bio
    if not bio then
        return true
    end

    while true do
        if deadline:is_done() then
            return false, nil, true
        end

        local n, err, again = bio:drain()
        if n then
            return true
        elseif not again then
            return false, err
        end

        local done, sec = deadline:is_done()
        if done then
            return false, nil, true
        end

        local ok, timeout
        ok, err, timeout = self:wait_writable(sec)
        if not ok then
            return false, err, timeout
        end
        -- do write again
    end
end

--- bio_drain
--- If sec is omitted, the deadline falls back to sndtimeo (or the default
--- max timeout when unset) so the EAGAIN path always has a deadline.
--- @private
--- @param sec number?
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Socket:bio_drain(sec)
    local deadline = sec and new_deadline(sec) or self:get_send_deadline()
    return bio_drain(self, deadline)
end

--- poll_wait core: caller passes its deadline so bio_drain + bio_fill share
--- one budget instead of each restarting a fresh sec timer.
--- @param self net.tls.Socket
--- @param want integer
--- @param deadline time.clock.deadline
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
--- @return boolean? eof
local function poll_wait(self, want, deadline)
    local ok, err, timeout
    if want == WANT_POLLIN then
        -- if use BIO, drain any pending encrypted record(s) to fd first (the
        -- peer may be waiting for our outgoing data, e.g. handshake flights),
        -- then fill the buffer with newly received ciphertext(s) from fd.
        if self.tls_bio then
            ok, err, timeout = bio_drain(self, deadline)
            if not ok then
                return false, err, timeout
            end
            return bio_fill(self, deadline)
        end

        local done, sec = deadline:is_done()
        if done then
            return false, nil, true
        end
        ok, err, timeout = self:wait_readable(sec)
        return ok, err, timeout
    elseif want == WANT_POLLOUT then
        -- if use BIO, drain the newly encrypted record(s) to fd
        if self.tls_bio then
            return bio_drain(self, deadline)
        end
        local done, sec = deadline:is_done()
        if done then
            return false, nil, true
        end
        ok, err, timeout = self:wait_writable(sec)
        return ok, err, timeout
    end

    return false,
           new_errno('EINVAL', format('unknown want type %q', tostring(want)))
end

--- poll_wait
--- If sec is omitted, the deadline falls back to rcvtimeo or sndtimeo
--- according to the want direction (or the default max timeout when the
--- corresponding timeout is unset).
--- @param want integer
--- @param sec number?
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
--- @return boolean? eof
function Socket:poll_wait(want, sec)
    local deadline
    if sec then
        deadline = new_deadline(sec)
    elseif want == WANT_POLLIN then
        deadline = self:get_recv_deadline()
    elseif want == WANT_POLLOUT then
        deadline = self:get_send_deadline()
    end
    return poll_wait(self, want, deadline)
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

--- tls_shutdown
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
--- @return boolean? eof
function Socket:tls_shutdown()
    local tls, shutdown = self.tls, self.tls.shutdown
    local deadline = self:get_send_deadline()

    while true do
        local ok, err, want = shutdown(tls)
        local timeout, eof

        if not want then
            if not ok then
                -- shutdown failed
                return false, err
            end

            -- shutdown succeeded
            -- if use BIO, the custom TX BIO may still hold the final
            -- close_notify ciphertext; drain it to the socket.  draining an
            -- empty buffer is a no-op.
            ok, err, timeout = bio_drain(self, deadline)
            if not ok then
                return false, err, timeout
            end
            return true
        end

        ok, err, timeout, eof = poll_wait(self, want, deadline)
        if not ok and not eof then
            return false, err, timeout, eof
        end
        -- do shutdown again
    end
end

--- tls_close
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
function Socket:tls_close()
    local ok, err, timeout = self:tls_shutdown()
    -- the TLS context is disposed on every exit path; shutdown failure does
    -- not justify keeping the SSL/BIO objects alive until the GC runs.
    self.tls_bio = nil
    self.tls:close()
    return ok, err, timeout
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

--- handshake_core: run the handshake against a caller-provided deadline
--- (falls back to sndtimeo when called outside of read/write).
--- @param self net.tls.Socket
--- @param deadline time.clock.deadline
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
--- @return boolean? eof
local function handshake(self, deadline)
    if self.handshaked then
        return true
    end

    local tls, handshake_fn = self.tls, self.tls.handshake
    while true do
        local ok, err, want = handshake_fn(tls)
        local timeout, eof

        if not want then
            if not ok then
                -- handshake failed
                return false, err
            end

            -- handshake succeeded
            -- if use BIO, drain the newly encrypted record(s) to fd
            self.handshaked, err, timeout = bio_drain(self, deadline)
            return self.handshaked, err, timeout
        end

        ok, err, timeout, eof = poll_wait(self, want, deadline)
        if not ok and not eof then
            -- error or timeout occurred
            return false, err, timeout, eof
        end
        -- do handshake again
    end
end

--- handshake
--- @return boolean ok
--- @return any err
--- @return boolean? timeout
--- @return boolean? eof
function Socket:handshake()
    if self.handshaked then
        return true
    end
    return handshake(self, self:get_send_deadline())
end

--- read
--- @param bufsize integer
--- @return string? msg
--- @return any err
--- @return boolean? timeout
--- @return boolean? eof
function Socket:read(bufsize)
    local deadline = self:get_recv_deadline()
    local ok, err, timeout, eof

    -- perform handshake if not yet, sharing the read deadline so
    -- handshake + read together fit within rcvtimeo instead of taking a
    -- fresh sndtimeo budget on top.
    if not self.handshaked then
        ok, err, timeout, eof = handshake(self, deadline)
        if not ok then
            return nil, err, timeout, eof
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
        if deadline:is_done() then
            return nil, nil, true
        end

        nread = nread + 1
        local str, want
        str, err, want = read(sock, bufsize)
        if not want then
            if not str then
                -- read failed
                return nil, err
            end

            -- read succeeded; return the plaintext as-is.  Any pending
            -- ciphertext in the TX BIO is not the read's concern: it is
            -- flushed by poll_wait()'s leading drain, the next write or
            -- tls_shutdown().
            return str
        end

        if nread > 5 then
            nread = 0
            ok, err, timeout, eof = poll_wait(self, want, deadline)
            if not ok and not eof then
                return nil, err, timeout, eof
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
--- @return boolean? eof
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
--- @return boolean? eof
function Socket:write(str)
    local deadline = self:get_send_deadline()
    local ok, err, timeout, eof

    -- perform handshake if not yet, sharing the write deadline (see
    -- Socket:read for the rationale).
    if not self.handshaked then
        ok, err, timeout, eof = handshake(self, deadline)
        if not ok then
            return 0, err, timeout, eof
        end
    end

    local sock, write = self.tls, self.tls.write
    local sent = 0

    while true do
        if deadline:is_done() then
            return sent, nil, true
        end

        local len, want
        len, err, want = write(sock, str)
        if not len then
            return sent, err
        end
        -- update a bytes sent
        sent = sent + len

        if not want then
            -- write succeeded
            -- if use BIO, drain the newly encrypted record(s) to fd
            ok, err, timeout = bio_drain(self, deadline)
            if not ok then
                return sent, err, timeout
            end
            return sent
        end

        ok, err, timeout, eof = poll_wait(self, want, deadline)
        if not ok and not eof then
            return sent, err, timeout, eof
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
--- @return boolean? eof
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

