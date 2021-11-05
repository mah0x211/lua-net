local unix = require('net.stream.unix')

local function printf(fmt, ...)
    print(fmt:format(...))
end

local s = assert(unix.pair())

local req = 'hello' .. os.time()
printf('send: %q', req)
assert(s[1]:send(req))

local msg = assert(s[2]:recv())
assert(s[2]:send(msg))

local rsp = assert(s[1]:recv())
printf('recv: %q', rsp)
assert(req == rsp, 'invalid response')

s[1]:close()
s[2]:close()
