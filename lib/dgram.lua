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
-- lib/dgram.lua
-- lua-net
-- Created by Masatoshi Teruya on 15/11/15.
--
--- @class net.dgram.Socket : net.Socket
local Socket = {}

--- mcastloop
--- @param enable boolean?
--- @return boolean? enabled
--- @return any err
function Socket:mcastloop(enable)
    return self.sock:mcastloop(enable)
end

--- mcastttl
--- @param ttl integer?
--- @return integer? ttl
--- @return any err
function Socket:mcastttl(ttl)
    return self.sock:mcastttl(ttl)
end

--- mcastif
--- @param ifname string?
--- @return string? ifname
--- @return any err
function Socket:mcastif(ifname)
    return self.sock:mcastif(ifname)
end

--- mcastjoin
--- @param grp addrinfo
--- @param ifname string?
--- @return boolean ok
--- @return any err
function Socket:mcastjoin(grp, ifname)
    return self.sock:mcastjoin(grp, ifname)
end

--- mcastleave
--- @param grp addrinfo
--- @param ifname string?
--- @return boolean ok
--- @return any err
function Socket:mcastleave(grp, ifname)
    return self.sock:mcastleave(grp, ifname)
end

--- mcastjoinsrc
--- @param grp addrinfo
--- @param src addrinfo
--- @param ifname string?
--- @return boolean ok
--- @return any err
function Socket:mcastjoinsrc(grp, src, ifname)
    return self.sock:mcastjoinsrc(grp, src, ifname)
end

--- mcastleavesrc
--- @param grp addrinfo
--- @param src addrinfo
--- @param ifname string?
--- @return boolean ok
--- @return any err
function Socket:mcastleavesrc(grp, src, ifname)
    return self.sock:mcastleavesrc(grp, src, ifname)
end

--- mcastblocksrc
--- @param grp addrinfo
--- @param src addrinfo
--- @param ifname string?
--- @return boolean ok
--- @return any err
function Socket:mcastblocksrc(grp, src, ifname)
    return self.sock:mcastblocksrc(grp, src, ifname)
end

--- mcastunblocksrc
--- @param src addrinfo
--- @param grp addrinfo
--- @param ifname string?
--- @return boolean ok
--- @return any err
function Socket:mcastunblocksrc(grp, src, ifname)
    return self.sock:mcastunblocksrc(grp, src, ifname)
end

--- broadcast
--- @param enable boolean?
--- @return boolean enabled
--- @return any err
function Socket:broadcast(enable)
    return self.sock:broadcast(enable)
end

--- recvfrom
--- @param ... integer flags
--- @return string? str
--- @return any err
--- @return boolean? timeout
--- @return addrinfo? ai
function Socket:recvfrom(...)
    local sock, recvfrom = self.sock, self.sock.recvfrom
    local deadline, sec = self:get_recv_deadline()

    while true do
        local str, err, again, ai = recvfrom(sock, ...)

        if not again then
            return str, err, again, ai
        elseif deadline then
            sec = deadline:remain()
            if sec <= 0 then
                return nil, nil, true
            end
        end

        -- wait until readable
        local ok, perr, timeout = self:wait_readable(sec)
        if not ok then
            return nil, perr, timeout
        end
    end
end

--- recvfromsync
--- @param ... integer flags
--- @return string? str
--- @return any err
--- @return boolean? timeout
--- @return addrinfo? ai
function Socket:recvfromsync(...)
    return self:syncread(self.recvfrom, ...)
end

--- sendto
--- @param str string
--- @param ai addrinfo
--- @param ... integer flags
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Socket:sendto(str, ai, ...)
    local sock, sendto = self.sock, self.sock.sendto
    local deadline, sec = self:get_send_deadline()
    local sent = 0

    while true do
        local len, err, again = sendto(sock, str, ai, ...)

        if not len then
            return nil, err
        end
        -- update a bytes sent
        sent = len + sent

        if not again then
            return sent
        elseif deadline then
            sec = deadline:remain()
            if sec <= 0 then
                return sent, nil, true
            end
        end

        -- wait until writable
        local ok, perr, timeout = self:wait_writable(sec)
        if not ok then
            return sent, perr, timeout
        end

        str = str:sub(len + 1)
    end
end

--- sendtosync
--- @param str string
--- @param ai addrinfo
--- @param ... integer flags
--- @return integer? len
--- @return any err
--- @return boolean? timeout
function Socket:sendtosync(str, ai, ...)
    return self:syncwrite(self.sendto, str, ai, ...)
end

require('metamodule').new.Socket(Socket, 'net.Socket')

