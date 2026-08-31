# net.tls.stream.Socket

defined in [net.tls.stream](../lib/tls/stream.lua) module and inherits from the [net.stream.Socket](net_stream_socket.md) and [net.tls.Socket](net_tls_socket.md) classes.


## len, err, timeout = sock:sendfile( f [, bytes [, offset]] )

send a file over the TLS connection.  Unlike the plain
[net.stream.Socket:sendfile](net_stream_socket.md#len-err-timeout--socksendfile-fd-bytes--offset),
which takes a raw file descriptor, the TLS version reads the file with
`pread(2)` and encrypts the bytes through `SSL_write`, so it accepts the
file itself and closes what it opened.

**Parameters**

- `f:file*|integer|string`: the file to send — an open file object, a raw
  file descriptor, or a filesystem path.  A file opened from a path or a
  descriptor is owned by this call and closed before it returns; a `file*`
  argument stays open and remains owned by the caller.
- `bytes:integer`: how many bytes to send from `offset`.  Omit it to send
  the remaining content of the file starting at `offset`; if nothing
  remains, `0` is returned immediately.  Must be a positive number when
  specified; `0` returns `0` and negative values raise `EINVAL`.
- `offset:integer`: where to begin in the file (default `0`).  Must be a
  non-negative integer; other values raise `EINVAL`.

**Returns**

- `len:integer`: number of bytes sent. Always a number: check `err` for the outcome; `len` reports how many bytes were accepted before a failure (`0` when none were).
- `err:error`: error object.
- `timeout:boolean`: `true` if the operation has timed out; `len` still reports the bytes sent so far.

**NOTE:** If the file holds fewer bytes than requested (or is truncated
mid-transfer), the bytes actually sent are returned without a timeout
indication.

**NOTE:** the payload is staged through a buffer capped at the smaller of
`SO_SNDBUF` and 16KB per iteration, so large transfers proceed in chunks
over the TLS record layer.
