local net = require('net')
local inet = require('net.dgram.inet')
local addrinfo = require('net.addrinfo')

local function printf(fmt, ...)
    print(fmt:format(...))
end

local ai = assert(addrinfo.new_inet('127.0.0.1', 5000, net.SOCK_DGRAM))
local c = assert(inet.new())

local req = 'hello ' .. os.time()
printf('sendto: %q -> %s:%s', req, ai:addr(), ai:port())
assert(c:sendto(req, ai))

local rsp = assert(c:recv())
printf('recv: %q', rsp)
assert(req == rsp, 'invalid response')

c:close()
