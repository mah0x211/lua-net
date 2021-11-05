# net.stream.unix.Server

defined in [net.stream.unix](../lib/stream/unix.lua) module and inherits from the [net.stream.Server](net_stream_server.md) class.


## sock, err, ai = unix.server.new( pathname )

create an instance of `net.stream.unix.Server`.

**Parameters**

- `pathname:string`: pathname of unix domain socket.
    
**Returns**

- `sock:net.stream.unix.Server`: instance of net.stream.unix.Server.
- `err:string`: error string.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


**e.g.**

```lua
local unix = require('net.stream.unix')
local sock, err, ai = unix.server.new('/tmp/example.sock')
```

