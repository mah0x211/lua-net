# net.dgram.inet.Socket

defined in [net.dgram.inet](../lib/dgram/inet.lua) module and inherits from the [net.dgram.Socket](net_dragm_socket.md) class.


## sock, err = inet.wrap( fd )

create an instance of `net.dgram.inet.Socket` from specified socket file descriptor.

**Parameters**

- `fd:integer`: socket file descriptor.

**Returns**

- `sock:net.dgram.inet.Socket`: instance of `net.dgram.inet.Socket`.
- `err:error`: error object.


## sock, err = inet.new()

create an instance of `net.dgram.inet.Socket`.

**Returns**

- `sock:net.dgram.inet.Socket`: instance of `net.dgram.inet.Socket`.


## ok, err, ai = sock:connect( host, port )

set a destination address.

**Parameters**

- `host:string`: hostname.
- `port:string`: either a decimal port number or a service name listed in services(5).

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


**e.g.**

```lua
local inet = require('net.dgram.inet')
local sock, err = assert(inet.new())
local ok, err, timeout, ai = sock:connect('127.0.0.1','8080')
```


## ok, err, ai = sock:bind( host, port, [, opts] )

bind a name to a socket.

**Parameters**

- `host:string`: hostname.
- `port:string`: either a decimal port number or a service name listed in services(5).
- `opts:table`:
    - `reuseaddr:boolean`: enable the SO_REUSEADDR flag.
    - `reuseport:boolean`: enable the SO_REUSEPORT flag.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

**e.g.**

```lua
local inet = require('net.dgram.inet')
local sock, err = assert(inet.new())
local ok, err, ai = sock:bind('127.0.0.1', '8080', true)
```


