# net.stream.unix.Server

defined in [net.stream.unix](../lib/stream/unix.lua) module and inherits from the [net.stream.Server](net_stream_server.md) class.


## sock, err, ai = unix.server.new( pathname [, tlscfg] )

create an instance of `net.stream.unix.Server`.  
if the `tlscfg` option is specified, it returns [net.tls.stream.unix.Server](net_tls_stream_unix_server.md) for TLS communication.

**Parameters**

- `pathname:string`: pathname of unix domain socket.
- `tlscfg:libtls.config`: [libtls.config](https://github.com/mah0x211/lua-libtls/blob/master/doc/config.md) object.
    
**Returns**

- `sock`: instance of `net.stream.unix.Server` or `net.tls.stream.unix.Server`.
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


**e.g.**

```lua
local unix = require('net.stream.unix')
local sock, err, ai = unix.server.new('/tmp/example.sock')
```

```lua
local unix = require('net.stream.unix')
local config = require('net.tls.config')
local cfg = config.new()
cfg:set_keypair_file('./cert.pem', './cert.key')
local sock, err, ai = unix.server.new('/tmp/example.sock', cfg)
```

