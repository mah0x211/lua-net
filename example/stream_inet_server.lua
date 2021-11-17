local server = require('net.stream.inet').server

local function printf(fmt, ...)
    print(fmt:format(...))
end

local host, port = '127.0.0.1', 5000
printf('create server:', host, port)
local s = assert(server.new(host, port, {
    reuseaddr = true,
}))

print('listen')
assert(s:listen())

print('accept')
local c = assert(s:accept())

local msg = assert(c:recv())
printf('recv: %q', msg)

printf('send: %q', msg)
assert(c:send(msg))

c:close()
s:close()
