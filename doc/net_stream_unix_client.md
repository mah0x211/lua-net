# net.stream.unix.Client

defined in [net.stream.unix](../lib/stream/unix.lua) module and inherits from the [net.stream.unix.Socket](net_stream_unix_socket.md) class.


## sock, err, timeoutm ai = unix.client.new( pathname [, opts] )

initiates a new connection and returns an instance of `net.stream.unix.Client`.

**Parameters**

- `pathname:string`: pathname of unix domain socket.
- `opts:table`
    - `deadline:uint`: specify a timeout milliseconds as unsigned integer.

**Returns**

- `sock:net.stream.unix.Client`: instance of net.stream.unix.Client.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

**e.g.**

```lua
local unix = require('net.stream.unix')
local sock, err, timeout, ai = unix.client.new('/tmp/example.sock', 100)
```
