# net.stream.Server

defined in [net.stream](../lib/stream.lua) module and inherits from the [net.stream.Socket](net_stream_socket.md) class.


## ok, err = sock:listen( [backlog] )

listen for connections.

**Parameters**

- `backlog:integer`: backlog size. (default `SOMAXCONN`)

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## sock, err, timeout, ai = sock:accept( [with_ai [, sec]] )

accept a connection.

**Parameters**

- `with_ai:boolean`: `true` to receive socket with [net.addrinfo](addrinfo.md).
- `sec:number`: timeout seconds. if omitted, the call waits indefinitely until a connection arrives.

**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `ai:addrinfo`: instance of [net.addrinfo](addrinfo.md).


## fd, err, timeout, ai = sock:acceptfd( [with_ai [, sec]] )

accept a connection and return the raw socket file descriptor.

**Parameters**

- `with_ai:boolean`: `true` to receive the peer address as [net.addrinfo](addrinfo.md).
- `sec:number`: timeout seconds. if omitted, the call waits indefinitely until a connection arrives.

**Returns**

- `fd:integer`: socket file descriptor.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `ai:addrinfo`: instance of [net.addrinfo](addrinfo.md).


## Implicit method calls

The following methods are implicitly called from the `accept` method.


### sock, err = sock:new_connection( sock )

create a `net.stream.Socket` from the incoming `net.socket`.

**Parameters**

- `sock:net.socket`: instance of [net.socket](socket.md)

**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).
- `err:error`: error object.


### sock, err, timeout, ai = sock:accepted( sock, ai )

calls after the 'new_connection' method succeeds.

**Parameters**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).
- `ai:addrinfo`: instance of [net.addrinfo](addrinfo.md).

**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](net_stream_socket.md).
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `ai:addrinfo`: instance of [net.addrinfo](addrinfo.md).

