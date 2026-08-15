# net.Socket

defined in [net](../net.lua) module. `net.Socket` is the root class of other class hierarchies.


## fd = sock:fd()

get socket file descriptor.

**Returns**

- `fd:integer`: socket file descriptor


## af = sock:family()

get a address family type.

**Returns**

- `af:string`: symbolic address family name such as `inet`, `inet6`, or
  `unix`.


### ai, err = sock:getsockname()

get socket name.

**Returns**

- `ai:addrinfo`: [net.addrinfo](addrinfo.md) userdata.
- `err:error`: error object.


## ai, err = sock:getpeername()

get address of connected peer.

**Returns**: same as [getsockname](#ai-err--sockgetsockname).


## ok, err = sock:closer()

disable the input operations.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## ok, err = sock:closew()

disable the output operations.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## ok, err = sock:close( [shutrd [, shutwr]] )

close a socket file descriptor.

**Parameters**

- `shutrd:boolean`: disabling the input operations before close a descriptor. (default `false`)
- `shutwr:boolean`: disabling the output operations before close a descriptor. (default `false`)

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## enabled, err = sock:atmark()

determine whether socket is at out-of-band mark.

**Returns**

- `enabled:boolean`: `true` if the socket is at the out-of-band mark, or false if it is not.
- `err:error`: error object.


## enabled, err = sock:cloexec( [enable] )

determine whether the `FD_CLOEXEC` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `FD_CLOEXEC` flag.

**Returns**

- `enabled:boolean`: state of the `FD_CLOEXEC` flag.
- `err:error`: error object.


## enabled, err = sock:isnonblock()

determine whether the `O_NONBLOCK` flag enabled.

**Returns**

- `enabled:boolean`: state of the `O_NONBLOCK` flag.
- `err:error`: error object.


## typ, err = sock:socktype()

get socket type.

**Returns**

- `typ:string`: symbolic socket type such as `stream`, `dgram`, or
  `seqpacket`.
- `err:error`: error object.


## proto = sock:protocol()

get a protocol type.

**Returns**

- `proto:string`: symbolic protocol name such as `auto`, `tcp`, or `udp`.


## soerr, err = sock:error()

get pending socket error status with and clears it.

**Returns**

- `soerr:error`: socket error object.
- `err:error`: error object.


## enabled, err = sock:reuseport( [enable] )

determine whether the `SO_REUSEPORT` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_REUSEPORT` flag.

**Returns**

- `enabled:boolean`: state of the `SO_REUSEPORT` flag.
- `err:error`: error object.


## enabled, err = sock:reuseaddr( [enable] )

determine whether the `SO_REUSEADDR` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_REUSEADDR` flag.

**Returns**

- `enabled:boolean`: state of the `SO_REUSEADDR` flag.
- `err:error`: error object.


## enabled, err = sock:debug( [enable] )

determine whether the `SO_DEBUG` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_DEBUG` flag.

**Returns**

- `enabled:boolean`: state of the `SO_DEBUG` flag.
- `err:error`: error object.


## enabled, err = sock:dontroute( [enable] )

determine whether the `SO_DONTROUTE` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_DONTROUTE` flag.

**Returns**

- `enabled:boolean`: state of the `SO_DONTROUTE` flag.
- `err:error`: error object.


## enabled, err = sock:timestamp( [enable] )

determine whether the `SO_TIMESTAMP` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_TIMESTAMP` flag.

**Returns**

- `enabled:boolean`: state of the `SO_TIMESTAMP` flag.
- `err:error`: error object.


## bytes, err = sock:rcvbuf( [bytes] )

get the `SO_RCVBUF` value, or change that value to an argument value.

**Parameters**

- `bytes:integer`: set the `SO_RCVBUF` value.

**Returns**

- `bytes:integer`: value of the `SO_RCVBUF`.
- `err:error`: error object.


## bytes, err = sock:rcvlowat( [bytes] )

get the `SO_RCVLOWAT` value, or change that value to an argument value.

**Parameters**

- `bytes:integer`: set the `SO_RCVLOWAT` value.

**Returns**

- `bytes:integer`: value of the `SO_RCVLOWAT`.
- `err:error`: error object.


## bytes, err = sock:sndbuf( [bytes] )

get the `SO_SNDBUF` value, or change that value to an argument value.

**Parameters**

- `bytes:integer`: set the `SO_SNDBUF` value.

**Returns**

- `bytes:integer`: value of the `SO_SNDBUF`.
- `err:error`: error object.


## bytes, err = sock:sndlowat( [bytes] )

get the `SO_SNDLOWAT` value, or change that value to an argument value.

**Parameters**

- `bytes:integer`: set the `SO_SNDLOWAT` value.

**Returns**

- `bytes:integer`: value of the `SO_SNDLOWAT`.
- `err:error`: error object.


## sec, err = sock:rcvtimeo( [sec] )

get the `SO_RCVTIMEO` value, or change that value to an argument value.

**Parameters**

- `sec:number`: set the `SO_RCVTIMEO` value.

**Returns**

- `sec:number`: value of the `SO_RCVTIMEO`.
- `err:error`: error object.


## sec, err = sock:sndtimeo( [sec] )

get the `SO_SNDTIMEO` value, or change that value to an argument value.

**Parameters**

- `sec:number`: set the `SO_SNDTIMEO` value.

**Returns**

- `sec:number`: value of the `SO_SNDTIMEO`.
- `err:error`: error object.


## sec, err = sock:linger( [sec] )

get the `SO_LINGER` value, or change that value to an argument value.

**Parameters**

- `sec:integer`: if sec >= 0 then enable `SO_LINGER` option, or else disabled this option.

**Returns**

- `sec:integer`: `nil` or a value of the `SO_LINGER`.
- `err:error`: error object.


## v, err, timeout, extra = sock:syncread(fn, ... )

call the function with `self` and passed arguments after acquiring the read lock.

**Parameters**

- `fn:function`: a function in the following declaration;
  - `v, err, timeout, extra? = fn(...)`
- `...:any`: any arguments for a function.

**Returns**

- `v:any`: the first return value of function.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `extra:any`: the forth return value of function.

**NOTE:** the read lock is released even if `fn` raises an error; the error
message with stack traceback is returned as `err` instead of being thrown.


## str, err, timeout = sock:read( [bufsize] )

read a message from a socket.

**Parameters**

- `bufsize:integer`: working buffer size of read operation.

**Returns**

- `str:string`: received message string.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## str, err, timeout = sock:readsync( [bufsize] )

synchronous version of read method that uses advisory lock.


## str, err, timeout = sock:recv( [bufsize [, flag, ...]] )

receive a message from a socket.

**Parameters**

- `bufsize:integer`: working buffer size of receive operation.
- `flag, ...:string`: symbolic `MSG_*` names such as `peek`, `dontwait`,
  or `waitall`.

**Returns**

- `str:string`: received message string.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## str, err, timeout = sock:recvsync( [bufsize [, flag, ...]] )

synchronous version of recv method that uses advisory lock.


## msg, err, timeout = sock:recvmsg( [bufsize [, cmsgbuf [, flag, ...]]] )

receive a message along with optional ancillary data (cmsgs) from a socket.

**Parameters**

- `bufsize:integer`: size of the buffer allocated for the payload data.  If
  omitted or `0`, no payload is received (cmsg-only mode).
- `cmsgbuf:integer`: size of the buffer allocated for control (ancillary)
  messages.  If omitted or `0`, cmsgs are not received.
- `flag, ...:string`: symbolic `MSG_*` names such as `peek`, `dontwait`,
  or `waitall`.

**Returns**

- `msg:table`: a table with the received data:
  - `data:string?`: payload bytes (present only when `bufsize > 0`).
  - `cmsgs:table[]?`: array of cmsg descriptors, each `{ level = string,
    type = string, data = integer|string|integer[] }`.
  - `flags:table`: `msg_flags` returned by `recvmsg(2)` as a set of
    lowercase names.  A flag that is set on the returned `msghdr` appears
    as `true` under its name (for example `trunc`, `ctrunc`, `eor`, `oob`,
    `errqueue`, `cmsg_cloexec`); flags that are not set are omitted.
    `ctrunc` in particular indicates that the kernel had to clip the
    ancillary data because `cmsgbuf` was too small, so `cmsgs` may be
    incomplete.
  - `addr:addrinfo?`: source [net.addrinfo](addrinfo.md) for datagram
    sockets (nil on connected sockets).
- `err:error`: error object.
- `timeout:boolean`: `true` when the deadline elapsed before data arrived.

**NOTE:** all return values will be nil if closed by peer.


## msg, err, timeout = sock:recvmsgsync( [bufsize [, cmsgbuf [, flag, ...]]] )

synchronous version of recvmsg method that uses advisory lock.


## len, err, timeout = sock:readv( iov [, offset [, nbyte]] )

read the messages from socket into iovec.

**Parameters**

- `iov:iovec`: instance of [iovec](https://github.com/mah0x211/lua-iovec).
- `offset:integer`: insertion position of received data.
- `nbyte:integer`: maximum number of bytes to be received.

**Returns**

- `len:integer`: the number of bytes received.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:readvsync( iov [, offset [, nbyte]] )

synchronous version of readv method that uses advisory lock.


## len, err, timeout = sock:syncwrite( fn, ... )

call the function with `self` and passed arguments after acquiring the write lock.

**Parameters**

- `fn:function`: a function in the following declaration;
  - `len, err, timeout = fn(...)`
- `...:any`: any arguments for a function.

**Returns**

- `len:integer`: the first return value of function.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.

**NOTE:** the write lock is released even if `fn` raises an error; the error
message with stack traceback is returned as `err` instead of being thrown.


## len, err, timeout = sock:write( str )

write a message to a socket.

**Parameters**

- `str:string`: message string.

**Returns**

- `len:integer`: the number of bytes written.
- `err:error`: error object.
- `timeout:boolean`: `true` if len is not equal to `#str` or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:writesync( str )

synchronous version of write method that uses advisory lock.


## len, err, timeout = sock:send( str [, flag, ...] )

send a message to a socket.

**Parameters**

- `str:string`: message string.
- `flag, ...:string`: symbolic `MSG_*` names such as `oob`, `dontwait`,
  or `nosignal`.

**Returns**

- `len:integer`: the number of bytes sent.
- `err:error`: error object.
- `timeout:boolean`: `true` if len is not equal to `#str` or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:sendsync( str [, flag, ...] )

synchronous version of send method that uses advisory lock.


## len, err, timeout = sock:sendmsg( [msg [, addr [, cmsg [, flag, ...]]]] )

send a message and optional ancillary data (cmsgs) via a socket.

**Parameters**

- `msg:string`: payload bytes to send.  May be omitted / nil when only
  cmsgs are being transmitted.
- `addr:addrinfo`: destination [net.addrinfo](addrinfo.md).  Only used
  by unconnected datagram sockets; nil on connected sockets.
- `cmsg:table[]`: array of cmsg descriptors, each `{ level = string,
  type = string, data = integer|string|integer[] }`.
- `flag, ...:string`: symbolic `MSG_*` names such as `oob`, `dontwait`,
  or `nosignal`.

**Returns**

- `len:integer`: the number of payload bytes sent.
- `err:error`: error object.
- `timeout:boolean`: `true` when the deadline elapsed with bytes still
  to send.

**NOTE:** at least one of `msg` and `cmsg` must be provided.


## len, err, timeout = sock:sendmsgsync( [msg [, addr [, cmsg [, flag, ...]]]] )

synchronous version of sendmsg method that uses advisory lock.


## len, err, timeout = sock:writev( iov [, offset [, nbyte]] )

send iovec messages at once.

**Parameters**

- `iov:iovec`: instance of [iovec](https://github.com/mah0x211/lua-iovec).
- `offset:integer`: offset at which the output operation is to be performed.
- `nbyte:integer`: number of bytes to send.

**Returns**

- `len:integer`: the number of bytes sent.
- `err:error`: error object.
- `timeout:boolean`: `true` if len is not equal to `iov:bytes()` or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:writevsync( iov [, offset [, nbyte]] )

synchronous version of writev method that uses advisory lock.
