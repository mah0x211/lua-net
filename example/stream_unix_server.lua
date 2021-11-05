local server = require('net.stream.unix').server

local function printf(fmt, ...)
    print(fmt:format(...))
end

local pathname = 'stream-unix.sock'
os.remove(pathname)

printf('create server: %q', pathname)
local s = assert(server.new(pathname))

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
os.remove(pathname)
