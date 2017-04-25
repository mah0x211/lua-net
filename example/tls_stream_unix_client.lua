local config = require("libtls.config")
local Unix = require("net.stream.unix")

local cfg = config.new()
cfg:insecure_noverifycert()
cfg:insecure_noverifyname()

local c = assert( Unix.client.new({
    path = './example.sock',
    tlscfg = cfg,
    servername = 'example.com'
}));

c:send('hello from client')
print( 'recv:', c:recv() )

