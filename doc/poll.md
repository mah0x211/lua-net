# net.poll

defined in [net.poll](../lib/poll.lua) module.


## ai, err = addrinfo.new_unix( pathname, socktype, protocol [, passive] )

create a new addrinfo instance of `AF_UNIX` socket.

**Parameters**

- `pathname:string`: pathname of unix domain socket.
- `socktype:integer` [SOCK_* types](constants.md#sock_-types) constants.
- `protocol:integer`: [IPROTO_* types](constants.md#ipproto_-types) constants.
- `flags:...`: [AI_* flags](constants.md#ai_-flags) constants.

**Returns**

- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `err:string`: error string.


## err = addrinfo.new_inet( host, port, socktype, protocol [, passive [, canonname]] )

get a list of addrinfo instance of `AF_INET` socket.

**Parameters**

- `host:string`: host string.
- `port:string`: either a decimal port number or a service name listed in `services(5)`.
- `family:integer`: [AF_* types](constants.md#af_-types) constants.
- `socktype:integer` [SOCK_* types](constants.md#sock_-types) constants.
- `protocol:integer`: [IPROTO_* types](constants.md#ipproto_-types) constants.
- `passive:boolean`: `true` to set `AI_PASSIVE` flag.
- `canonname:boolean`: `true` to set `AI_CANONNAME` flag.

**Returns**

- `arr:llsocket.addrinfo[]`: list of [addrinfo](#llsocketaddrinfo-instance-methods).
- `err:string`: error string.

