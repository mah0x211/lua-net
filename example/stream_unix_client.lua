local client = require('net.stream.unix').client

local function printf(fmt, ...)
    print(fmt:format(...))
end

local pathname = 'stream-unix.sock'
printf('create client: %q', pathname)
local c = assert(client.new(pathname))

local req = 'hello' .. os.time()
printf('send: %q', req)
assert(c:send(req))

local rsp = assert(c:recv())
printf('recv: %q', rsp)
assert(req == rsp)

c:close()
