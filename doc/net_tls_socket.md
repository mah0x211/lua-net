# net.tls.Socket

defined in [net.tls](../lib/tls.lua) module and inherits from the [net.Socket](net_socket.md) class.


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

The IO operations (`sock:handshake()`, `sock:read()` / `sock:recv()`,
`sock:write()` / `sock:send()`, `sock:tls_shutdown()` and `sock:tls_close()`)
drive the non-blocking transport by themselves: while the underlying socket
reports `WANT_READ` / `WANT_WRITE`, they wait for the file descriptor to
become readable / writable and retry internally, so the caller does not
need to repeat the call on those indications.

Every such operation is bounded by a deadline derived from
`sock:rcvtimeo()` / `sock:sndtimeo()` (see [net.Socket](net_socket.md)).
When the corresponding timeout is unset or zero, the library defaults apply
(currently `330` seconds for receive-side operations and `960` seconds for
send-side operations); once the deadline elapses, the operation returns
with the `timeout` indication instead of looping forever.


## ok, err, timeout = sock:close()

close the socket after closing the tls context.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.


## ok, err, timeout, eof = sock:poll_wait( want [, sec] )

wait until the file descriptor is readable or writable.

**Parameters**

- `want:integer`: [required file descriptor state](net_tls.md#required-file-descriptor-states).
- `sec:number?`: timeout seconds; defaults to the deadline derived from `sock:rcvtimeo()` / `sock:sndtimeo()`.

**Returns**

- `ok:boolean`: `true` when the wanted state became ready.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `eof:boolean`: `true` if the memory-BIO transport observed end-of-file.


## ok, err, timeout = sock:handshake()

it is only necessary to call this method if you need to guarantee that the handshake has completed, as both `sock:recv()` and `sock:send()` will calls this method if necessary.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.


## ok, err, timeout = sock:tls_shutdown()

performs the graceful tls shutdown (`close_notify` exchange; with memory
BIOs the final `close_notify` ciphertext is drained to the socket). the tls
context is kept alive; follow up with `sock:tls_close()` to dispose of it.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.


## ok, err, timeout = sock:tls_close()

performs `sock:tls_shutdown()` and then disposes of the tls context
associated with the socket. the context is disposed even if the graceful
shutdown fails or times out; the failure is reported through the return
values.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.


## str, err, timeout = sock:read( [bufsize] )

read a message from a socket.

**Parameters**

- `bufsize:integer`: working buffer size of receive operation. (default: `BUFSIZ` that size of `stdio.h` buffers)

**Returns**

- `str:string`: message string.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## str, err, timeout = sock:recv( [bufsize] )

equivalant to `sock:read( [bufsize] )`.


## len, err, timeout = sock:write( str )

write a message to a socket.

**Parameters**

- `str:string`: message string.

**Returns**

- `len:integer`: the number of bytes written. Always a number: check `err` for the outcome; `len` reports how many bytes were accepted before a failure (`0` when none were).
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out; `len` still reports the bytes accepted so far.


## len, err, timeout = sock:send( str )

equivalant to `sock:write( str )`.
