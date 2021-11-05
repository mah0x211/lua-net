local inet = require('net.dgram.inet')

local function printf(fmt, ...)
    print(fmt:format(...))
end

local s = assert(inet.new())
local host, port = '127.0.0.1', 5000
local reuseaddr = true

printf('bind %s:%s', host, port)
assert(s:bind(host, port, reuseaddr))

local msg, _, _, ai = assert(s:recvfrom())
printf('recvfrom: %q <- %s:%s', msg, ai:addr(), ai:port())

print('  sendto: %q -> %s:%s', msg, ai:addr(), ai:port())
assert(s:sendto(msg, ai))

s:close()
