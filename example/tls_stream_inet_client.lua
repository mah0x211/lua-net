local config = require("libtls.config")
local Inet = require("net.stream.inet")

local cfg = config.new()
cfg:insecure_noverifycert()
cfg:insecure_noverifyname()

local c = assert( Inet.client.new({
    host = '127.0.0.1',
    port = '8443',
    tlscfg = cfg,
    servername = 'example.com'
}));

c:send('hello from client')
print( 'recv:', c:recv() )

