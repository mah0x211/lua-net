local inet = require('net.dgram.inet')
local device = require('net.device')
local addrinfo = require('net.addrinfo')

local function printf(fmt, ...)
    print(fmt:format(...))
end

local c = assert(inet.new())

local dev
for k, v in pairs(assert(device.getifaddrs())) do
    if v.loopback then
        dev = k
        break
    end
end
printf('mcastif: %q', dev)
local _, err = c:mcastif(dev)
assert(not err, err)

local req = 'hello ' .. os.time()
local ai = assert(addrinfo.inet('224.0.0.251', 5000, {
    socktype = 'dgram',
    protocol = 'udp',
}))
printf('  sendto: %q -> %s:%s', req, ai:addr(), ai:port())
assert(c:sendto(req, ai))

local rsp, _, _, sai = assert(c:recvfrom())
printf('recvfrom: %q <- %s:%s', rsp, sai:addr(), sai:port())
assert(req == rsp, 'invalid response')

c:close()
