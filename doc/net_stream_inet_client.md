# net.stream.inet.Client

defined in [net.stream.inet](../lib/stream/inet.lua) module and inherits from the [net.stream.inet.Socket](net_stream_inet_socket.md) class.


## sock, err, timeout, ai = inet.client.new( host, port [, opts] )

initiates a new connection and returns an instance of `net.stream.inet.Client`.  
if the `tlscfg` option is specified, it returns [net.tls.stream.inet.Client](net_tls_stream_inet_client.md) for TLS communication.

**Parameters**

- `host:string`: hostname.
- `port:string|integer`: either a decimal port number or a service name listed in services(5).
- `opts:table`
    - `deadline:number`: specify a timeout seconds.
    - `tlscfg:libtls.config`: [libtls.config](https://github.com/mah0x211/lua-libtls/blob/master/doc/config.md) object.

**Returns**

- `sock`: instance of `net.stream.inet.Client` or `net.tls.stream.inet.Client`.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

**e.g.**

```lua
local inet = require('net.stream.inet')
local sock, err, timeout, ai = inet.client.new('127.0.0.1','8080')
```

```lua
local inet = require('net.stream.inet')
local config = require('net.tls.config')
local cfg = config.new()
cfg:insecure_noverifycert()
cfg:insecure_noverifyname()
local sock, err, timeout, ai = inet.client.new('127.0.0.1','8080', {
    tlscfg = cfg,
})
```
