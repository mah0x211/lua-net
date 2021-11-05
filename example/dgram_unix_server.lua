local unix = require('net.dgram.unix')

local function printf(fmt, ...)
    print(fmt:format(...))
end

local server_sock = 'dgram-unix-server.sock'
os.remove(server_sock)

local s = assert(unix.new())

printf('bind: %q', server_sock)
assert(s:bind(server_sock))

local msg, _, _, ai = assert(s:recvfrom())
printf('recvfrom: %q <- %s:%s', msg, ai:addr(), ai:port())

print('  sendto: %q -> %s:%s', msg, ai:addr(), ai:port())
assert(s:sendto(msg, ai))

s:close()
os.remove(server_sock)

