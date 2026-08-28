# net.unix.Socket

defined in [net.unix](../lib/unix.lua) module and inherits from the [net.Socket](net_socket.md) class.


## len, err, timeout = sock:sendfd( fd [, ai [, flag, ...]] )

send file descriptors along unix domain sockets.

**Parameters**

- `fd:integer`: file descriptor;
- `ai:addrinfo`: instance of [net.addrinfo](addrinfo.md).
- `flag, ...:string`: symbolic `MSG_*` names such as `dontwait` or
  `nosignal`.

**Returns**

- `len:integer`: the number of bytes sent (always zero). Always a number: check `err` for the outcome.
- `err:error`: error object.
- `timeout:boolean`: `true` if errno is `EAGAIN`, `EWOULDBLOCK`, `EINTR`.


## len, err, timeout = sock:sendfdsync( fd [, ai [, flag, ...]] )

synchronous version of sendfd method that uses advisory lock.


## fd, err, timeout = sock:recvfd()

receive file descriptors along unix domain sockets.

**Returns**

- `fd:integer`: file descriptor.
- `err:error`: error object.
- `timeout:boolean`: `true` either if errno is `EAGAIN`, `EWOULDBLOCK` or `EINTR`, or if socket type is `SOCK_DGRAM` or `SOCK_RAW`.

**NOTE:** all return values will be nil if closed by peer.

**NOTE:** `recvfd()` consumes and discards the payload bytes of every
message it processes — a `sendfd()` peer attaches a 1-byte dummy payload to
carry the descriptor. Do not interleave plain `sock:send()` application
data with fd passing on the same socket; such data is silently discarded.


## fd, err, timeout = sock:recvfdsync()

synchronous version of recvfd method that uses advisory lock.


