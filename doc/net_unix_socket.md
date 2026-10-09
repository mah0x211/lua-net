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
- `timeout:boolean`: `true` if the send deadline expires. `EAGAIN`,
  `EWOULDBLOCK`, and `EINTR` are retried internally.


## len, err, timeout = sock:sendfdsync( fd [, ai [, flag, ...]] )

synchronous version of sendfd method that uses advisory lock.

If the write lock cannot be acquired, this synchronous form returns
`nil, err, timeout` before attempting to send the descriptor.


## fdq, err, timeout = sock:recvfd( [flag, ...] )

receive file descriptors along unix domain sockets.

**Parameters**

- `flag, ...:string`: symbolic `MSG_*` names such as `dontwait`. `peek` is not supported.

**Returns**

- `fdq:net.scm_rights`: owns the received file descriptors; see [net.scm_rights](net_scm_rights.md).
- `err:error`: error object.
- `timeout:boolean`: `true` if the receive deadline expires. `EAGAIN`,
  `EWOULDBLOCK`, and `EINTR` are retried internally.

**NOTE:** all return values will be nil if closed by peer.

**NOTE:** `recvfd()` consumes and discards the payload bytes of every
message it processes — a `sendfd()` peer attaches a 1-byte dummy payload to
carry the descriptor. Do not interleave plain `sock:send()` application
data with fd passing on the same socket; such data is silently discarded.

The control buffer accommodates up to 253 descriptors on Linux and 254 on
other platforms. Buffer overflow and control-message truncation follow the OS
behavior; reception of every sent descriptor is not guaranteed.

## fdq, err, timeout = sock:recvfdsync( [flag, ...] )

synchronous version of recvfd method that uses advisory lock.

