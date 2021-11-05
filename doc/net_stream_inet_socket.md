# net.stream.inet.Socket

defined in [net.stream.inet](../lib/stream/inet.lua) module and inherits from the [net.stream.Socket](net_stream_socket.md) class.


## sock, err = inet.wrap( fd )

create an instance of `net.stream.inet.Socket` from specified socket file descriptor.

**Parameters**

- `fd:integer`: socket file descriptor.

**Returns**

- `sock:net.stream.inet.Socket`: instance of `net.inet.Socket`.
- `err:string`: error string.

