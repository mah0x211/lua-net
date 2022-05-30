# net.stream.unix.Socket

defined in [net.stream.unix](../lib/stream/unix.lua) module and inherits from the [net.stream.Socket](net_stream_socket.md) and [net.unix.Socket](net_unix_socket.md) classes.


## sock, err = unix.wrap( fd )

create an instance of `net.stream.unix.Socket` from specified socket file descriptor.

**Parameters**

- `fd:integer`: socket file descriptor.

**Returns**

- `sock:net.stream.unix.Socket`: instance of `net.unix.Socket`.
- `err:error`: error object.


## socks, err = unix.pair()

create a pair of connected sockets.

**Returns**

- `socks:table`: pair of connected sockets.
    - `1`: `net.stream.unix.Socket`
    - `2`: `net.stream.unix.Socket`
- `err:error`: error object.

**e.g.**

```lua
local unix = require('net.stream.unix')
local socks, err, timeout = unix.pair()
```
