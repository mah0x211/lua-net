local config = require("libtls.config")
local Inet = require("net.stream.inet")

local cfg = config.new()
cfg:set_keypair_file( './cert.pem', './cert.key' )

local s = Inet.server.new({
    host = '127.0.0.1',
    port = '8443',
    reuseaddr = true,
    tlscfg = cfg
})
s:listen()

local c = s:accept()
local msg = c:recv()
print( 'recv:', msg )

c:send( 'hello from server' )
c:close()
s:close()
