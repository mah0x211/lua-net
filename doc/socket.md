# net.socket

defined in [net.socket](../lib/socket.lua) module.


## sock, err, nonblock = socket.wrap( fd )

create an instance of `llscoket.socket` from specified socket file descriptor.

**Parameters**

- `fd:integer`: socket file descriptor.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `nonblock:boolean`: `true` if sock has the `O_NONBLOCK` flags


## sock, err, timeout, nonblock = socket.connect( ai [, conndeadl] )

create a new instance of `llsocket.socket`.

**Parameters**

- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket/blob/master/doc/addrinfo.md).
- `conndeadl:integer`: specify a timeout milliseconds as unsigned integer.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `nonblock:boolean`: `true` if sock has the `O_NONBLOCK` flags

## sock, err, nonblock = socket.bind_inet_stream( host, port [, reuseaddr [, reuseport]] )

create a tcp-stream (`socktype=SOCK_STREAM`, `protocol=IPPROTO_TCP`) socket and bind an address.

**Parameters**

- `host:string`: host string.
- `port:string`: either a decimal port number or a service name listed in `services(5)`.
- `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
- `reuseport:boolean`: enable the `SO_REUSEPORT` flag.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `nonblock:boolean`: `true` if sock has the `O_NONBLOCK` flags
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket/blob/master/doc/addrinfo.md).


## sock, err, nonblock = socket.bind( ai [, reuseaddr [, reuseport]] )

create a socket based on the address-info and bind that address-info.

**Parameters**

- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket/blob/master/doc/addrinfo.md).
- `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
- `reuseport:boolean`: enable the `SO_REUSEPORT` flag.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `nonblock:boolean`: `true` if sock has the `O_NONBLOCK` flags


## socks, err, nonblock = socket.pair( socktype [, protocol] )

create a pair of connected sockets.

**Parameters**

- `socktype:integer`: [SOCK_* types](constants.md#sock_-types) constants.
- `protocol:integer`: [IPROTO_* types](constants.md#ipproto_-types) constants.

**Returns**

- `socks:table`: pair of connected sockets.
  - `1:socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
  - `2:socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `nonblock:boolean`: `true` if sock has the `O_NONBLOCK` flags


## socks, err, nonblock = socket.pair_stream()

equivalant to `socket.pair( SOCK_STREAM, IPPROTO_TCP )`.


## socks, err, nonblock = socket.pair_dgram()

equivalant to `socket.pair( SOCK_DGRAM, IPPROTO_UDP )`.


## sock, err, nonblock = socket.new_unix( socktype, protocol [, reuseaddr [, reuseport]] )

create a new instance of `llsocket.socket` for `AF_UNIX`.

**Parameters**

- `socktype:integer`: [SOCK_* types](constants.md#sock_-types).
- `protocol:integer`: [IPPROTO_* types](constants.md#ipproto_-types).
- `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
- `reuseport:boolean`: enable the `SO_REUSEPORT` flag.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `nonblock:boolean`: `true` if sock has the `O_NONBLOCK` flags


## sock, err, nonblock = socket.new_unix_stream( [, reuseaddr [, reuseport]] )

equivalant to `socket.new_unix( SOCK_STREAM, IPPROTO_TCP [, reuseaddr [, reuseport]] )`.


## sock, err, nonblock = socket.new_unix_dgram( [, reuseaddr [, reuseport]] )

equivalant to `socket.new_unix( SOCK_DGRAM, IPPROTO_UDP [, reuseaddr [, reuseport]] )`.


## sock, err, nonblock = socket.new_inet( socktype, protocol [, reuseaddr [, reuseport]] )

create a new instance of `llsocket.socket` for `AF_INET`.

**Parameters**

- `socktype:integer`: [SOCK_* types](constants.md#sock_-types).
- `protocol:integer`: [IPPROTO_* types](constants.md#ipproto_-types).
- `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
- `reuseport:boolean`: enable the `SO_REUSEPORT` flag.

**Returns**

- `sock:llsocket.socket`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket/blob/master/doc/socket.md).
- `err:error`: error object.
- `nonblock:boolean`: `true` if sock has the `O_NONBLOCK` flags


## sock, err, nonblock = socket.new_inet_stream( [, reuseaddr [, reuseport]] )

equivalant to `socket.new_inet( SOCK_STREAM, IPPROTO_TCP [, reuseaddr [, reuseport]] )`.


## sock, err, nonblock = socket.new_inet_dgram( [, reuseaddr [, reuseport]] )

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


