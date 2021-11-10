# net.stream.Server

defined in [net.stream](../lib/stream.lua) module and inherits from the [net.stream.Socket](net_stream_socket.md) class.


## ok, err = sock:listen( [backlog] )

listen for connections.

**Parameters**

- `backlog:integer`: backlog size. (default `SOMAXCONN`)

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.


## sock, err, ai = sock:accept( with_ai )

accept a connection.

**Parameters**

- `with_ai:boolean`: `true` to receive socket with [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).
- `err:string`: error string.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


## fd, err = sock:acceptfd()

accept a connection.

**Returns**

- `fd:integer`: socket file descriptor.
- `err:string`: error string.


## sock = sock:createConnection( sock )

create a connection socket as a `net.stream.Socket`.

**Parameters**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket#llsocketsocket-instance-methods)

**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).


