# net.stream.Server

defined in [net.stream](../lib/stream.lua) module and inherits from the [net.stream.Socket](net_stream_socket.md) class.


## ok, err = sock:listen( [backlog] )

listen for connections.

**Parameters**

- `backlog:integer`: backlog size. (default `SOMAXCONN`)

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## sock, err, ai = sock:accept( with_ai )

accept a connection.

**Parameters**

- `with_ai:boolean`: `true` to receive socket with [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


## fd, err = sock:acceptfd()

accept a connection.

**Returns**

- `fd:integer`: socket file descriptor.
- `err:error`: error object.


## Implicit method calls

The following methods are implicitly called from the `accept` method.


### sock, err = sock:new_connection( sock )

create a `net.stream.Socket` from the incoming `llsocket.socket`.

**Parameters**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket#llsocketsocket-instance-methods)

**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).
- `err:error`: error object.


### sock, err, ai = sock:accepted( sock, ai )

calls after the 'new_connection' method succeeds.

**Parameters**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


