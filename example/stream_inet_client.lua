local client = require('net.stream.inet').client

local function printf(fmt, ...)
    print(fmt:format(...))
end

local host, port = '127.0.0.1', 5000

print('create client: %s:%s', host, port)
local c = assert(client.new(host, port))

local req = 'hello' .. os.time()

printf('send: %q', req)
assert(c:send(req))

local rsp = assert(c:recv())
printf('recv: %q', rsp)
assert(req == rsp, 'invalid response')

c:close()

