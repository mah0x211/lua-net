local config = require("libtls.config")
local Unix = require("net.stream.unix")

local cfg = config.new()
cfg:set_keypair_file( './cert.pem', './cert.key' )

local s = Unix.server.new({
    path = './example.sock',
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
