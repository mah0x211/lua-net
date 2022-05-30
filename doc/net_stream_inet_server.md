# net.stream.inet.Server

defined in [net.stream.inet](../lib/stream/inet.lua) module and inherits from the [net.stream.Server](net_stream_server.md) class.


## sock, err, ai = inet.server.new( host, port [, opts] )

create an instance of `net.stream.inet.Server`.  
if the `tlscfg` option is specified, it returns [net.tls.stream.inet.Server](net_tls_stream_inet_server.md) for TLS communication.


**Parameters**

- `host:string`: hostname.
- `port:string|integer`: either a decimal port number or a service name listed in services(5).
- `opts:table`
    - `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
    - `reuseport:boolean`: enable the `SO_REUSEPORT` flag.
    - `tlscfg:libtls.config`: [libtls.config](https://github.com/mah0x211/lua-libtls/blob/master/doc/config.md) object.

**Returns**

- `sock`: instance of `net.stream.inet.Server` or `net.tls.stream.inet.Server`.
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


**e.g.**

```lua
local inet = require('net.stream.inet')
local sock, err = inet.server.new('127.0.0.1', 8080)
```

```lua
local inet = require('net.stream.inet')
local config = require('net.tls.config')
local cfg = config.new()
cfg:set_keypair_file('./cert.pem', './cert.key')
local sock, err = inet.server.new('127.0.0.1', 8080. {
    tlscfg = cfg,
})
```

