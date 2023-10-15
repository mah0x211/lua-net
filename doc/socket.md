# net.socket

defined in [net.socket](../lib/socket.lua) module.


## sock, err = socket.wrap( fd )

create an instance of `llscoket.socket` from specified socket file descriptor.

**Parameters**

- `fd:integer`: socket file descriptor.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.


## sock, err, timeout, ai = socket.connect_unix_stream( pathname, [, conndeadl] )

create a unix-stream (`family=AF_UNIX`, `socktype=SOCK_STREAM`) socket and connects to specified unix domain socket file.

**Parameters**

- `pathname:string`: pathname of unix domain socket.
- `conndeadl:number`: specify a timeout seconds.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket/blob/master/doc/addrinfo.md).


## sock, err, timeout, ai = socket.connect_inet_stream( host, port, [, conndeadl] )

create a tcp-stream (`family=AF_INET`, `socktype=SOCK_STREAM`) socket and connects to specified address.

**Parameters**

- `host:string`: host string.
- `port:string`: either a decimal port number or a service name listed in `services(5)`.
- `conndeadl:number`: specify a timeout seconds.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket/blob/master/doc/addrinfo.md).


## sock, err, timeout = socket.connect( ai [, conndeadl] )

create a new instance of `llsocket.socket`.

**Parameters**

- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket/blob/master/doc/addrinfo.md).
- `conndeadl:number`: specify a timeout seconds.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.


## sock, err, ai = socket.bind_unix_stream( pathname )

create a unix-stream (`family=AF_UNIX`, `socktype=SOCK_STREAM`) socket and bind an address.

**Parameters**

- `pathname:string`: pathname of unix domain socket.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket/blob/master/doc/addrinfo.md).


## sock, err, ai = socket.bind_inet_stream( host, port [, reuseaddr [, reuseport]] )

create a tcp-stream (`family=AF_INET`, `socktype=SOCK_STREAM`) socket and bind an address.

**Parameters**

- `host:string`: host string.
- `port:string`: either a decimal port number or a service name listed in `services(5)`.
- `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
- `reuseport:boolean`: enable the `SO_REUSEPORT` flag.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket/blob/master/doc/addrinfo.md).


## sock, err = socket.bind( ai [, reuseaddr [, reuseport]] )

create a socket based on the address-info and bind that address-info.

**Parameters**

- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket/blob/master/doc/addrinfo.md).
- `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
- `reuseport:boolean`: enable the `SO_REUSEPORT` flag.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.


## socks, err = socket.pair( socktype )

create a pair of connected sockets.

**Parameters**

- `socktype:integer`: [SOCK_* types](constants.md#sock_-types) constants.

**Returns**

- `socks:table`: pair of connected sockets.
  - `1:socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
  - `2:socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.


## socks, err = socket.pair_stream()

equivalant to `socket.pair( SOCK_STREAM )`.


## socks, err = socket.pair_dgram()

equivalant to `socket.pair( SOCK_DGRAM )`.


## sock, err = socket.new_unix( socktype, protocol [, reuseaddr [, reuseport]] )

create a new instance of `llsocket.socket` for `AF_UNIX`.

**Parameters**

- `socktype:integer`: [SOCK_* types](constants.md#sock_-types).
- `protocol:integer`: [IPPROTO_* types](constants.md#ipproto_-types).
- `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
- `reuseport:boolean`: enable the `SO_REUSEPORT` flag.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.


## sock, err = socket.new_unix_stream( [, reuseaddr [, reuseport]] )

equivalant to `socket.new_unix( SOCK_STREAM, 0 [, reuseaddr [, reuseport]] )`.


## sock, err = socket.new_unix_dgram( [, reuseaddr [, reuseport]] )

equivalant to `socket.new_unix( SOCK_DGRAM, 0 [, reuseaddr [, reuseport]] )`.


## sock, err = socket.new_inet( socktype, protocol [, reuseaddr [, reuseport]] )

create a new instance of `llsocket.socket` for `AF_INET`.

**Parameters**

- `socktype:integer`: [SOCK_* types](constants.md#sock_-types).
- `protocol:integer`: [IPPROTO_* types](constants.md#ipproto_-types).
- `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
- `reuseport:boolean`: enable the `SO_REUSEPORT` flag.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.


## sock, err = socket.new_inet_stream( [, reuseaddr [, reuseport]] )

equivalant to `socket.new_inet( SOCK_STREAM, IPPROTO_TCP [, reuseaddr [, reuseport]] )`.


## sock, err = socket.new_inet_dgram( [, reuseaddr [, reuseport]] )

equivalant to `socket.new_inet( SOCK_DGRAM, IPPROTO_UDP [, reuseaddr [, reuseport]] )`.


## ok, err = socket.shutdown( fd, flag )

shut down part of a full-duplex connection.

**Parameters**

- `fd:integer`: socket file descriptor.
- `flag:number`: [SHUT_* flag](constants.md#shut_-flags) constants.

**Returns**

- `ok:boolean` `true` on success.
- `err:error`: error object.


## ok, err = socket.close( fd [, flag] )

close a socket file descriptor.

**Parameters**

- `fd:number`: socket file descriptor.
- `flag:number`: [SHUT_* flag](constants.md#shut_-flags) constants.

**Returns**

- `ok:boolean` `true` on success.
- `err:error`: error object.


