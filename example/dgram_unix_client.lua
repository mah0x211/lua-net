local unix = require('net.dgram.unix')

local function printf(fmt, ...)
    print(fmt:format(...))
end

local server_sock = 'dgram-unix-server.sock'
local client_sock = 'dgram-unix-client.sock'
os.remove(client_sock)

local c = assert(unix.new())

printf('bind: %q', client_sock)
assert(c:bind(client_sock))

printf('connect: %q', server_sock)
assert(c:connect(server_sock))

local req = 'hello' .. os.time()

printf('send: %q', req)
assert(c:send(req))

local rsp = assert(c:recv())
printf('recv: %q', rsp)
assert(req == rsp, 'invalid response')

c:close()
os.remove(client_sock)
