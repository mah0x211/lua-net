# net.stream.inet.Server

defined in [net.stream.inet](../lib/stream/inet.lua) module and inherits from the [net.stream.Server](net_stream_server.md) class.


## sock, err, ai = inet.server.new( host, port [, opts] )

create an instance of `net.stream.inet.Server`.

**Parameters**

- `host:string`: hostname.
- `port:string|integer`: either a decimal port number or a service name listed in services(5).
- `opts:table`
    - `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
    - `reuseport:boolean`: enable the `SO_REUSEPORT` flag.

**Returns**

- `sock:net.stream.inet.Server`: instance of `net.stream.inet.Server`.
- `err:string`: error string.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


**e.g.**

```lua
local inet = require('net.stream.inet')
local sock, err = inet.server.new('127.0.0.1',8080)
```


