# net.unix.Socket

defined in [net.unix](../lib/unix.lua) module and inherits from the [net.Socket](net_socket.md) class.


## len, err, timeout = sock:sendfd( fd [, ai [, flag, ...]] )

send file descriptors along unix domain sockets.

**Parameters**

- `fd:integer`: file descriptor;
- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `flag, ...:integer`: [MSG_* Flags](constants.md#msg_-flags).

**Returns**

- `len:integer`: the number of bytes sent (always zero).
- `err:error`: error object.
- `timeout:boolean`: `true` if errno is `EAGAIN`, `EWOULDBLOCK`, `EINTR`.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:sendfdsync( fd [, ai [, flag, ...]] )

synchronous version of sendfd method that uses advisory lock.


## fd, err, timeout = sock:recvfd()

receive file descriptors along unix domain sockets.

**Returns**

- `fd:integer`: file descriptor.
- `err:error`: error object.
- `timeout:boolean`: `true` either if errno is `EAGAIN`, `EWOULDBLOCK` or `EINTR`, or if socket type is `SOCK_DGRAM` or `SOCK_RAW`.

**NOTE:** all return values will be nil if closed by peer.


## fd, err, timeout = sock:recvfdsync()

synchronous version of recvfd method that uses advisory lock.



