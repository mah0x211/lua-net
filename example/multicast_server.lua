local inet = require('net.dgram.inet')
local device = require('net.device')
local new_inet_dgram_ai = require('net.addrinfo').new_inet_dgram

local function printf(fmt, ...)
    print(fmt:format(...))
end

local s = assert(inet.new())

printf('bind: :5000')
assert(s:bind(nil, 5000, true))

local dev
for k, v in pairs(assert(device.getifaddrs())) do
    if v.loopback then
        dev = k
        break
    end
end

local ai = new_inet_dgram_ai('224.0.0.251')
printf('mcastjoin: %s:%s %s', ai:addr(), ai:port(), dev)
assert(s:mcastjoin(ai, dev))

local msg, _, _, cai = assert(s:recvfrom())
printf('recvfrom: %q <- %s:%s', msg, cai:addr(), cai:port())

printf('  sendto: %q -> %s:%s', msg, cai:addr(), cai:port())
assert(s:sendto(msg, cai))

s:close()

