# net.dgram.unix.Socket

defined in [net.dgram.unix](../lib/dgram/unix.lua) module and inherits from the [net.dgram.Socket](net_dgram_socket.md) class.


## Functions

## sock, err = unix.wrap( fd )

create an instance of `net.dgram.unix.Socket` from specified socket file descriptor.

**Parameters**

- `fd:integer`: socket file descriptor.

**Returns**

- `sock:net.dgram.unix.Socket`: instance of net.dgram.unix.Socket.
- `err:string`: error string.


## socks, err = unix.pair()

create a pair of connected sockets

**Returns**

- `socks:table`: pair of connected sockets.
    - `1`: `net.dgram.unix.Socket`
    - `2`: `net.dgram.unix.Socket`
- `err:string`: error string.

**e.g.**

```lua
local unix = require('net.dgram.unix')
local socks, err = unix.pair()
```


## sock, err = unix.new()

create an instance of `net.dgram.unix.Socket`.

**Returns**

- `sock:net.dgram.unix.Socket`: instance of net.dgram.unix.Socket.
- `err:string`: error string.

**e.g.**

```lua
local unix = require('net.dgram.unix')
local sock, err = unix.new()
```

## Methods

## ok, err, ai = sock:connect( pathname )

set a destination address.

**Parameters**

- `pathname:string`: pathname of unix domain socket.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


## ok, err, ai = sock:bind( pathname )

bind a name to a socket.

**Parameters**

- `pathname:string`: pathname of unix domain socket.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

