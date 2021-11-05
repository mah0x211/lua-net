local inet = require('net.dgram.inet')

local function printf(fmt, ...)
    print(fmt:format(...))
end

local c = assert(inet.new())

local host, port = '127.0.0.1', 5000
printf('connect: %s:%s', host, port)
assert(c:connect(host, port))

local req = 'hello ' .. os.time()
printf('send: %q', req)
assert(c:send(req))

local rsp = assert(c:recv())
printf('recv: %q', rsp)
assert(req == rsp, 'invalid response')

c:close()
