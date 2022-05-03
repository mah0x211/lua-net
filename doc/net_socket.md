# net.Socket

defined in [net](../net.lua) module. `net.Socket` is the root class of other class hierarchies.


## fd = sock:fd()

get socket file descriptor.

**Returns**

- `fd:integer`: socket file descriptor


## fn = sock:onwaitrecv( [fn [, ctx]] )

set a hook function that invokes before waiting for receivable data arrivals.

**Parameters**

- `fn:function`: a hook function.
- `ctx:any`: context object.

**Returns**

- `fn:function`: old hook function.


## fn = sock:onwaitsend( [fn [, ctx]] )

set a hook function that invokes before waiting for send buffer has decreased.

**Parameters**

- `fn:function`: a hook function.
- `ctx:any`: context object.

**Returns**

- `fn:function`: old hook function.


## af = sock:family()

get a address family type.

**Returns**

- `af:integer`: family type constants ([AF_* Types](constants.md#af_-types)).


### ai, err = sock:getsockname()

get socket name.

**Returns**

- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `err:string`: error string.


## ai, err = sock:getpeername()

get address of connected peer.

**Returns**: same as [getsockname](#ai-err--sockgetsockname).


## ok, err = sock:closer()

disable the input operations.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.


## ok, err = sock:closew()

disable the output operations.

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.


## ok, err = sock:close( [shutrd [, shutwr]] )

close a socket file descriptor.

**Parameters**

- `shutrd:boolean`: disabling the input operations before close a descriptor. (default `false`)
- `shutwr:boolean`: disabling the output operations before close a descriptor. (default `false`)

**Returns**

- `ok:boolean`: `true` on success.
- `err:string`: error string.


## enabled, err = sock:atmark()

determine whether socket is at out-of-band mark.

**Returns**

- `enabled:boolean`: `true` if the socket is at the out-of-band mark, or false if it is not.
- `err:string`: error string.


## enabled, err = sock:cloexec( [enable] )

determine whether the `FD_CLOEXEC` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `FD_CLOEXEC` flag.

**Returns**

- `enabled:boolean`: state of the `FD_CLOEXEC` flag.
- `err:string`: error string.


## enabled = sock:isnonblock()

determine whether the `O_NONBLOCK` flag enabled.

**Returns**

- `enabled:boolean`: state of the `O_NONBLOCK` flag.


## typ, err = sock:socktype()

get socket type.

**Returns**

- `typ:integer`: socket type constants ([SOCK_* Types](constants.md#sock_-types)).
- `err:string`: error string.


## proto = sock:protocol()

get a protocol type.

**Returns**

- `proto:integer`: protocol type constants ([IPPROTO_* Types](constants.md#ipproto_-types)).


## soerr, err = sock:error()

get pending socket error status with and clears it.

**Returns**

- `soerr:string`: socket error string.
- `err:string`: error string.


## enabled, err = sock:reuseport( [enable] )

determine whether the `SO_REUSEPORT` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_REUSEPORT` flag.

**Returns**

- `enabled:boolean`: state of the `SO_REUSEPORT` flag.
- `err:string`: error string.


## enabled, err = sock:reuseaddr( [enable] )

determine whether the `SO_REUSEADDR` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_REUSEADDR` flag.

**Returns**

- `enabled:boolean`: state of the `SO_REUSEADDR` flag.
- `err:string`: error string.


## enabled, err = sock:debug( [enable] )

determine whether the `SO_DEBUG` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_DEBUG` flag.

**Returns**

- `enabled:boolean`: state of the `SO_DEBUG` flag.
- `err:string`: error string.


## enabled, err = sock:dontroute( [enable] )

determine whether the `SO_DONTROUTE` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_DONTROUTE` flag.

**Returns**

- `enabled:boolean`: state of the `SO_DONTROUTE` flag.
- `err:string`: error string.


## enabled, err = sock:timestamp( [enable] )

determine whether the `SO_TIMESTAMP` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_TIMESTAMP` flag.

**Returns**

- `enabled:boolean`: state of the `SO_TIMESTAMP` flag.
- `err:string`: error string.


## bytes, err = sock:rcvbuf( [bytes] )

get the `SO_RCVBUF` value, or change that value to an argument value.

**Parameters**

- `bytes:integer`: set the `SO_RCVBUF` value.

**Returns**

- `bytes:integer`: value of the `SO_RCVBUF`.
- `err:string`: error string.


## bytes, err = sock:rcvlowat( [bytes] )

get the `SO_RCVLOWAT` value, or change that value to an argument value.

**Parameters**

- `bytes:integer`: set the `SO_RCVLOWAT` value.

**Returns**

- `bytes:integer`: value of the `SO_RCVLOWAT`.
- `err:string`: error string.


## bytes, err = sock:sndbuf( [bytes] )

get the `SO_SNDBUF` value, or change that value to an argument value.

**Parameters**

- `bytes:integer`: set the `SO_SNDBUF` value.

**Returns**

- `bytes:integer`: value of the `SO_SNDBUF`.
- `err:string`: error string.


## bytes, err = sock:sndlowat( [bytes] )

get the `SO_SNDLOWAT` value, or change that value to an argument value.

**Parameters**

- `bytes:integer`: set the `SO_SNDLOWAT` value.

**Returns**

- `bytes:integer`: value of the `SO_SNDLOWAT`.
- `err:string`: error string.


## sec, err = sock:rcvtimeo( [sec] )

get the `SO_RCVTIMEO` value, or change that value to an argument value.

**Parameters**

- `sec:number`: set the `SO_RCVTIMEO` value.

**Returns**

- `sec:number`: value of the `SO_RCVTIMEO`.
- `err:string`: error string.


## sec, err = sock:sndtimeo( [sec] )

get the `SO_SNDTIMEO` value, or change that value to an argument value.

**Parameters**

- `sec:number`: set the `SO_SNDTIMEO` value.

**Returns**

- `sec:number`: value of the `SO_SNDTIMEO`.
- `err:string`: error string.


## rcvmsec, sndmsec = sock:deadlines( [rcvmsec [, sndmsec]] )

get the receive timeout and the send timeout values.

if you specify arguments, these values are changed to argument values.

**NOTE**

if socket is in the **blocking mode**, this method calls the [rcvtimeo](#sec-err--sockrcvtimeo-sec-) and [sndtime](#sec-err--socksndtimeo-sec-) methods internally.


**Parameters**

- `rcvmsec:integer`: set the receive timeout in milliseconds.
- `sndmsec:integer`: set the send timeout in milliseconds.

**Returns**

- `rcvmsec:integer`: the receive timeout.
- `sndmsec:integer`: the send timeout.


## sec, err = sock:linger( [sec] )

get the `SO_LINGER` value, or change that value to an argument value.

**Parameters**

- `sec:integer`: if sec >= 0 then enable `SO_LINGER` option, or else disabled this option.

**Returns**

- `sec:integer`: `nil` or a value of the `SO_LINGER`.
- `err:string`: error string.


## v, err, timeout, extra = sock:syncread(fn, ... )

call the function with `self` and passed arguments after acquiring the read lock.

**Parameters**

- `fn:function`: a function in the following declaration;
  - `v, err, timeout, extra? = fn(...)`
- `...:any`: any arguments for a function.

**Returns**

- `v:any`: the first return value of function.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.
- `extra:any`: the forth return value of function.


## str, err, timeout = sock:read( [bufsize] )

read a message from a socket.

**Parameters**

- `bufsize:integer`: working buffer size of read operation.

**Returns**

- `str:string`: received message string.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## str, err, timeout = sock:readsync( [bufsize] )

synchronous version of read method that uses advisory lock.


## str, err, timeout = sock:recv( [bufsize [, flag, ...]] )

receive a message from a socket.

**Parameters**

- `bufsize:integer`: working buffer size of receive operation.
- `flag, ...:integer`: [MSG_* Flags](constants.md#msg_-flags).

**Returns**

- `str:string`: received message string.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## str, err, timeout = sock:recvsync( [bufsize [, flag, ...]] )

synchronous version of recv method that uses advisory lock.


## len, err, timeout = sock:recvmsg( mh [, flag, ...] )

receive multiple messages and ancillary data from a socket.

**Parameters**

- `mh:net.MsgHdr`: [net.MsgHdr](#netmsghdr).
- `flag, ...:integer`: [MSG_* Flags](constants.md#msg_-flags).

**Returns**

- `len:integer`: the number of bytes received.
- `err:string`: error string.
- `timeout:boolean`: `true` if len is not equal to `mh:bytes()` or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:recvmsgsync( mh [, flag, ...] )

synchronous version of recvmsg method that uses advisory lock.


## len, err, timeout = sock:readv( iov [, offset [, nbyte]] )

read the messages from socket into iovec.

**Parameters**

- `iov:iovec`: instance of [iovec](https://github.com/mah0x211/lua-iovec).
- `offset:integer`: insertion position of received data.
- `nbyte:integer`: maximum number of bytes to be received.

**Returns**

- `len:integer`: the number of bytes received.
- `err:string`: error string.
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
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.


## len, err, timeout = sock:send( str [, flag, ...] )

send a message from a socket.

**Parameters**

- `str:string`: message string.
- `flag, ...:integer`: [MSG_* Flags](constants.md#msg_-flags).

**Returns**

- `len:integer`: the number of bytes sent.
- `err:string`: error string.
- `timeout:boolean`: `true` if len is not equal to `#str` or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:sendsync( str [, flag, ...] )

synchronous version of send method that uses advisory lock.


## len, err, timeout = sock:sendmsg( mh [, flag, ...] )

send multiple messages and ancillary data from a socket.

**Parameters**

- `mh:net.MsgHdr`: [net.MsgHdr](msghdr.md).
- `flag, ...:integer`: [MSG_* Flags](constants.md#msg_-flags).

**Returns**

- `len:integer`: the number of bytes sent.
- `err:string`: error string.
- `timeout:boolean`: `true` if len is not equal to `mh:bytes()` or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:sendmsgsync( mh [, flag, ...] )

synchronous version of sendmsg method that uses advisory lock.


## len, err, timeout = sock:writev( iov [, offset [, nbyte]] )

send iovec messages at once.

**Parameters**

- `iov:iovec`: instance of [iovec](https://github.com/mah0x211/lua-iovec).
- `offset:integer`: offset at which the output operation is to be performed.
- `nbyte:integer`: number of bytes to send.

**Returns**

- `len:integer`: the number of bytes sent.
- `err:string`: error string.
- `timeout:boolean`: `true` if len is not equal to `iov:bytes()` or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:writevsync( iov [, offset [, nbyte]] )

synchronous version of writev method that uses advisory lock.
