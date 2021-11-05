# net.addrinfo

defined in [net.addrinfo](../lib/addrinfo.lua) module.


## ai, err = addrinfo.new_unix( pathname, socktype, protocol [, passive] )

create a new addrinfo instance of `AF_UNIX`.

**Parameters**

- `pathname:string`: pathname of unix domain socket.
- `socktype:integer` [SOCK_* types](constants.md#sock_-types) constants.
- `protocol:integer`: [IPROTO_* types](constants.md#ipproto_-types) constants.
- `flags:...`: [AI_* flags](constants.md#ai_-flags) constants.

**Returns**

- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `err:string`: error string.


## ai, err = addrinfo.new_unix_stream( pathname [, passive] )

equivalant to `addrinfo.new_unix( pathname, SOCK_STREAM, 0 [, passive] )`.

## ai, err = addrinfo.new_unix_dgram( pathname [, passive] )

equivalant to `addrinfo.new_unix( pathname, SOCK_DGRAM, 0 [, passive] )`.


## ai, err = addrinfo.new_inet( host, port, socktype, protocol [, passive] )

get a new addrinfo instance of `AF_INET`.

**Parameters**

- `host:string`: host string.
- `port:string`: either a decimal port number or a service name listed in `services(5)`.
- `family:integer`: [AF_* types](constants.md#af_-types) constants.
- `socktype:integer` [SOCK_* types](constants.md#sock_-types) constants.
- `protocol:integer`: [IPROTO_* types](constants.md#ipproto_-types) constants.
- `passive:boolean`: `true` to set `AI_PASSIVE` flag.

**Returns**

- `ais:llsocket.addrinfo`: instance of [addrinfo](#llsocketaddrinfo-instance-methods).
- `err:string`: error string.


## ai, err = addrinfo.new_inet_stream( host, port [, passive] )

equivalant to `addrinfo.new_inet( host, port, SOCK_STREAM, IPPROTO_TCP [, passive] )`.

## ai, err = addrinfo.new_inet_dgram( host, port [, passive] )

equivalant to `addrinfo.new_inet( host, port, SOCK_DGRAM, IPPROTO_UDP [, passive] )`.



## ais, err = addrinfo.getaddrinfo( host, port, socktype, protocol [, passive [, canonname]] )

get a list of addrinfo instance of `AF_INET`.

**Parameters**

- `host:string`: host string.
- `port:string`: either a decimal port number or a service name listed in `services(5)`.
- `family:integer`: [AF_* types](constants.md#af_-types) constants.
- `socktype:integer` [SOCK_* types](constants.md#sock_-types) constants.
- `protocol:integer`: [IPROTO_* types](constants.md#ipproto_-types) constants.
- `passive:boolean`: `true` to set `AI_PASSIVE` flag.
- `canonname:boolean`: `true` to set `AI_CANONNAME` flag.

**Returns**

- `ais:llsocket.addrinfo[]`: list of [addrinfo](#llsocketaddrinfo-instance-methods).
- `err:string`: error string.



## ais, err = addrinfo.getaddrinfo_stream( host, port [, passive [, canonname]] )

equivalant to `addrinfo.getaddrinfo( host, port, SOCK_STREAM, IPPROTO_TCP [, passive [, canonname]] )`.

## ais, err = addrinfo.getaddrinfo_dgram( host, port [, passive [, canonname]] )

equivalant to `addrinfo.getaddrinfo( host, port, SOCK_DGRAM, IPPROTO_UDP [, passive [, canonname]] )`.



