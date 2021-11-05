# net.stream.Socket

defined in [net.stream](../lib/stream.lua) module and inherits from the [net.Socket](net_socket.md) class.


## enabled, err = sock:acceptconn()

determine whether the `SO_ACCEPTCONN` flag enabled.

**Returns**

- `enabled:boolean`: state of the `SO_ACCEPTCONN` flag.
- `err:string`: error string.


## enabled, err = sock:oobinline( [enable] )

determine whether the `SO_OOBINLINE` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_OOBINLINE` flag.

**Returns**

- `enabled:boolean`: state of the `SO_OOBINLINE` flag.
- `err:string`: error string.


## enabled, err = sock:keepalive( [enable] )

determine whether the `SO_KEEPALIVE` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the SO_KEEPALIVE flag.

**Returns**

- `enabled:boolean`: state of the `SO_KEEPALIVE` flag.
- `err:string`: error string.


## enabled, err = sock:tcpnodelay( [enable] )

determine whether the `TCP_NODELAY` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `TCP_NODELAY` flag.

**Returns**

- `enabled:boolean`: state of the `TCP_NODELAY` flag.
- `err:string`: error string.


## enabled, err = sock:tcpcork( [enable] )

determine whether the `TCP_CORK` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `TCP_CORK` flag.

**Returns**

- `enabled:boolean`: state of the `TCP_CORK` flag.
- `err:string`: error string.


## sec, err = sock:tcpkeepalive( [sec] )

get the `TCP_KEEPALIVE` value, or set that value if argument passed.

**Parameters**

- `sec:integer`: set the `TCP_KEEPALIVE` value.

**Returns**

- `sec:integer`: value of the `TCP_KEEPALIVE`.
- `err:string`: error string.


## sec, err = sock:tcpkeepintvl( [sec] )

get the `TCP_KEEPINTVL` value, or change that value to an argument value.

**Parameters**

- `sec:integer`: set the `TCP_KEEPINTVL` value.

**Returns**

- `sec:integer`: value of the `TCP_KEEPINTVL`.
- `err:string`: error string.


## cnt, err = sock:tcpkeepcnt( [cnt] )

get the `TCP_KEEPCNT` value, or change that value to an argument value.

**Parameters**

- `cnt:integer`: set the `TCP_KEEPCNT` value.

**Returns**

- `cnt:integer`: value of the `TCP_KEEPCNT`.
- `err:string`: error string.


## len, err, timeout = sock:sendfile( fd, bytes [, offset] )

send a file from a socket.

**Parameters**

- `fd:integer`: file descriptor.
- `bytes:integer`: how many bytes of the file should be sent.
- `offset:integer`: specifies where to begin in the file (default 0).

**Returns**

- `len:integer`: number of bytes sent.
- `err:string`: error string.
- `timeout:boolean`: true if len not equal to bytes or operation has timed out.


**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:sendfilesync( fd, bytes [, offset] )

synchronous version of sendfile method that uses advisory lock.


