# net.tls.Socket

defined in [net.tls](../tls.lua) module and inherits from the [net.Socket](net_socket.md) class.


## Methods that cannot be used in net.tls.Socket

the following methods always return an error.

- `sock:closer()`
- `sock:closew()`
- `sock:recvmsg()`
- `sock:recvmsgsync()`
- `sock:readv()`
- `sock:readvsync()`
- `sock:sendmsg()`
- `sock:sendmsgsync()`
- `sock:writev()`
- `sock:writevsync()`


## About internal IO processing

IO operations (`sock:handshake()`, `sock:tls_close()`, `sock:recv` and `sock:send()`) by tls will return a retry error even if the socket is in blocking mode. if this error occurs, the same function call should be repeated immediately.

To prevent the possibility of an infinite loop, it is limited by the clock time (default `10 ms`). Use the `sock:setclocklimit()` method to change the time limit if necessary.


## sock:setclocklimit( [sec] )

sets the clock limit time in seconds. if `sec` is `nil`, it will be set to the default time.

**Parameters**

- `sec:number`: the clock limit time in seconds.


## ok, err, timeout = sock:close()

close the socket after closing the tls context.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.


## ok, err, timeout = sock:poll_wait( want )

wait until the file descriptor is readable or writable.

**Parameters**

- `want:integer`: [Required file descriptor states](constants.md#required-file-descriptor-states).

**Returns**

- `ok:boolean`: `true` on readable.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.


## ok, err, timeout = sock:handshake()

it is only necessary to call this method if you need to guarantee that the handshake has completed, as both `sock:recv()` and `sock:send()` will calls this method if necessary.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.


## ok, err, timeout = sock:tls_close()

closes the tls context associated with the socket.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.


## str, err, timeout = sock:read( [bufsize] )

read a message from a socket.

**Parameters**

- `bufsize:integer`: working buffer size of receive operation. (default: `BUFSIZ` that size of `stdio.h` buffers)

**Returns**

- `str:string`: message string.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## str, err, timeout = sock:recv( [bufsize] )

equivalant to `sock:read( [bufsize] )`.


## len, err, timeout = sock:write( str )

write a message to a socket.

**Parameters**

- `str:string`: message string.

**Returns**

- `len:integer`: the number of bytes written.
- `err:string`: error string.
- `timeout:boolean`: `true` if len is not equal to `#str` or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:send( str )

equivalant to `sock:write( str )`.

