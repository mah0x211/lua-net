lua-net
=======

this is wrapper module for llsocket module.

**NOTE: this module is under heavy development.**

***

## Dependencies

- halo: https://github.com/mah0x211/lua-halo
- llsocket: https://github.com/mah0x211/lua-llsocket


## Installation

```
$ luarocks install net --from=http://mah0x211.github.io/rocks/
```


## Usage

**TODO**


> please see the [example files](example/).


***


## Classes

- [net.Socket](#netsocket)
	- **Stream Socket**
		- [net.stream.Socket](#netstreamsocket)
			- [net.stream.Server](#netstreamserver)
				- [net.stream.inet.Server](#netstreaminetserver)
				- [net.stream.unix.Server](#netstreamunixserver)
			- [net.stream.inet.Client](#netstreaminetclient)
			- [net.stream.unix.Client](#netstreamunixclient)
		- [Functions in net.stream module](#functions-in-netstream-module)
	- **Datagram Socket (TODO)**


***


## net.Socket

defined in `net` module.
net.Socket is the root class of other class hierarchies.


### fd = sock:fd()

get socket file descriptor.

- **Returns**
	- `fd:number`: socket file descriptor


#### ai, err = sock:getsockname()

get socket name.

- **Returns**
	- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
	- `err:string`: error string.


### ai, err = sock:getpeername()

get address of connected peer.

- **Returns**: same as [getsockname](#ai-err-sockgetsockname).


### err = sock:closer()

disable the input operations.

- **Returns**
	- `err:string`: error string.

### err = sock:closew()

disable the output operations.

- **Returns**
	- `err:string`: error string.


### err = sock:close()

close a socket file descriptor.

- **Returns**
	- `err:string`: error string.


### bool, err = sock:atmark()

determine whether socket is at out-of-band mark.

- **Returns**
	- `bool:boolean`: true if the socket is at the out-of-band mark, or false if it is not.
	- `err:string`: error string.


### bool, err = sock:cloexec( [bool] )

determine whether the FD_CLOEXEC flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the FD_CLOEXEC flag.
- **Returns**
	- `bool:boolean`: state of the FD_CLOEXEC flag.
	- `err:string`: error string.


### bool, err = sock:nonblock( [bool] )

determine whether the O_NONBLOCK flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the O_NONBLOCK flag.
- **Returns**
	- `bool:boolean`: state of the O_NONBLOCK flag.
	- `err:string`: error string.


### typ, err = sock:socktype()

get socket type.

- **Returns**
	- `typ:number`: socket type constants(**TODO**).
	- `err:string`: error string.


### errno, err = sock:error()

get pending socket error status with and clears it.

- **Returns**
	- `errno:number`: number of last error.
	- `err:string`: error string.


### bool, err = sock:reuseport( [bool] )

**TODO**


### bool, err = sock:reuseaddr( [bool] )

determine whether the SO_REUSEADDR flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the SO_REUSEADDR flag.
- **Returns**
	- `bool:boolean`: state of the SO_REUSEADDR flag.
	- `err:string`: error string.


### bool, err = sock:debug( [bool] )

determine whether the SO_DEBUG flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the SO_DEBUG flag.
- **Returns**
	- `bool:boolean`: state of the SO_DEBUG flag.
	- `err:string`: error string.


### bool, err = sock:dontroute( [bool] )

determine whether the SO_DONTROUTE flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the SO_DONTROUTE flag.
- **Returns**
	- `bool:boolean`: state of the SO_DONTROUTE flag.
	- `err:string`: error string.


### bool, err = sock:timestamp( [bool] )

determine whether the SO_TIMESTAMP flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the SO_TIMESTAMP flag.
- **Returns**
	- `bool:boolean`: state of the SO_TIMESTAMP flag.
	- `err:string`: error string.


### bytes, err = sock:rcvbuf( [bytes] )

get the SO_RCVBUF value, or change that value to an argument value.

- **Parameters**
	- `bytes:number`: set the SO_RCVBUF value.
- **Returns**
	- `bytes:number`: value of the SO_RCVBUF.
	- `err:string`: error string.


### bytes, err = sock:rcvlowat( [bytes] )

get the SO_RCVLOWAT value, or change that value to an argument value.

- **Parameters**
	- `bytes:number`: set the SO_RCVLOWAT value.
- **Returns**
	- `bytes:number`: value of the SO_RCVLOWAT.
	- `err:string`: error string.


### bytes, err = sock:sndbuf( [bytes] )

get the SO_SNDBUF value, or change that value to an argument value.

- **Parameters**
	- `bytes:number`: set the SO_SNDBUF value.
- **Returns**
	- `bytes:number`: value of the SO_SNDBUF.
	- `err:string`: error string.


### bytes, err = sock:sndlowat( [bytes] )

get the SO_SNDLOWAT value, or change that value to an argument value.

- **Parameters**
	- `bytes:number`: set the SO_SNDLOWAT value.
- **Returns**
	- `bytes:number`: value of the SO_SNDLOWAT.
	- `err:string`: error string.


### sec, err = sock:rcvtimeo( [sec] )

get the SO_RCVTIMEO value, or change that value to an argument value.

- **Parameters**
	- `sec:number`: set the SO_RCVTIMEO value.
- **Returns**
	- `sec:number`: value of the SO_RCVTIMEO.
	- `err:string`: error string.


### sec, err = sock:sndtimeo( [sec] )

get the SO_SNDTIMEO value, or change that value to an argument value.

- **Parameters**
	- `sec:number`: set the SO_SNDTIMEO value.
- **Returns**
	- `sec:number`: value of the SO_SNDTIMEO.
	- `err:string`: error string.


### str, err, again = sock:recv( [bufsize] )

receive a message from a socket.

- **Parameters**
	- `bufsize:number`: working buffer size of receive operation.
- **Returns**
	- `str:string`: received message string.
	- `err:string`: error string.
	- `again:bool`: true if errno is EAGAIN, EWOULDBLOCK or EINTR.

**NOTE:** all return values will be nil if closed by peer.


### len, err, again = sock:send( str )

send a message from a socket.

- **Parameters**
	- `str:string`: message string.
- **Returns**
	- `len:number`:  the number of bytes sent.
	- `err:string`: error string.
	- `again:bool`: true if len != #str, or errno is EAGAIN, EWOULDBLOCK or EINTR.

**NOTE:** all return values will be nil if closed by peer.


***


## net.stream.Socket

defined in `net.stream` module and inherits from the [net.Socket](#netsocket) class.


### bool, err = sock:acceptconn()

determine whether the SO_ACCEPTCONN flag enabled.

- **Returns**
	- `bool:boolean`:  state of the SO_ACCEPTCONN flag.
	- `err:string`: error string.


### bool, err = sock:oobinline( [bool] )

determine whether the SO_OOBINLINE flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the SO_OOBINLINE flag.
- **Returns**
	- `bool:boolean`:  state of the SO_OOBINLINE flag.
	- `err:string`: error string.


### bool, err = sock:keepalive( [bool] )

determine whether the SO_KEEPALIVE flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the SO_KEEPALIVE flag.
- **Returns**
	- `bool:boolean`:  state of the SO_KEEPALIVE flag.
	- `err:string`: error string.


### bool, err = sock:tcpnodelay( [bool] )

determine whether the TCP_NODELAY flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the TCP_NODELAY flag.
- **Returns**
	- `bool:boolean`:  state of the TCP_NODELAY flag.
	- `err:string`: error string.


### bool, err = sock:tcpcork( [bool] )

determine whether the TCP_CORK flag enabled, or change the state to an argument value.

- **Parameters**
	- `bool:boolean`: to enable or disable the TCP_CORK flag.
- **Returns**
	- `bool:boolean`:  state of the TCP_CORK flag.
	- `err:string`: error string.


### sec, err = sock:tcpkeepalive( [sec] )

get the TCP_KEEPALIVE value, or set that value if argument passed.

- **Parameters**
	- `sec:number`: set the TCP_KEEPALIVE value.
- **Returns**
	- `sec:number`:  value of the TCP_KEEPALIVE.
	- `err:string`: error string.


### sec, err = sock:tcpintvl( [sec] )

get the TCP_KEEPINTVL value, or change that value to an argument value.

- **Parameters**
	- `sec:number`: set the TCP_KEEPINTVL value.
- **Returns**
	- `sec:number`:  value of the TCP_KEEPINTVL.
	- `err:string`: error string.


### cnt, err = sock:tcpkeepcnt( [sec] )

get the TCP_KEEPCNT value, or change that value to an argument value.

- **Parameters**
	- `sec:number`: set the TCP_KEEPCNT value.
- **Returns**
	- `sec:number`:  value of the TCP_KEEPCNT.
	- `err:string`: error string.


## net.stream.Server

defined in `net.stream` module and inherits from the [net.stream.Socket](#netstreamsocket) class.


### err = sock:listen( [backlog] )

listen for connections.

- **Parameters**
	- `backlog:number`: backlog size. (default SOMAXCONN)
- **Returns**
	- `err:string`: error string.


## net.stream.inet.Server

defined in `net.stream.inet` module and inherits from the [net.stream.Server](#netstreamserver) class.


### sock, err = inet.server.new( opts )

create an instance of [net.stream.inet.Server](#netstreaminetserver).

- **Parameters**
	- `opts:table`: following fields are defined;
        - `host:string`: hostname.
        - `port:string`: either a decimal port number or a service name listed in services(5).
        - `nonblock:boolean`: enable  the O_NONBLOCK flag.
        - `reuseaddr:boolean`: enable the SO_REUSEADDR flag.
- **Returns**
	- `sock:net.stream.inet.Server`: instance of net.stream.inet.Server socket.
	- `err:string`: error string.

**e.g.**

```lua
local inet = require('net.stream.inet')
local sock, err = inet.server.new({
	host = '127.0.0.1',
	port = '8080'
})
```

## net.stream.inet.Client

defined in `net.stream.inet` module and inherits from the [net.stream.Socket](#netstreamsocket) class.


### sock, err = inet.client.new( opts )

create an instance of [net.stream.inet.Client](#netstreaminetclient) and initiate a new connection immediately.

- **Parameters**
	- `opts:table`: following fields are defined;
        - `host:string`: hostname.
        - `port:string`: either a decimal port number or a service name listed in services(5).
        - `nonblock:boolean`: enable the O_NONBLOCK flag.
- **Returns**
	- `sock:net.stream.inet.Client`: instance of net.stream.inet.Client socket.
	- `err:string`: error string.

**e.g.**

```lua
local inet = require('net.stream.inet')
local sock, err = inet.client.new({
	host = '127.0.0.1',
	port = '8080'
})
```

### err = sock:connect()

initiate a new connection, and close an old connection if succeeded.

- **Returns**
	- `err:string`: error string.



## net.stream.unix.Server

defined in `net.stream.unix` module and inherits from the [net.stream.Server](#netstreamserver) class.


### sock, err = unix.server.new( opts )

create an instance of [net.stream.unix.Server](#netstreamunixserver).

- **Parameters**
	- `opts:table`: following fields are defined;
        - `path:string`: pathname of unix domain socket.
        - `nonblock:boolean`: enable the O_NONBLOCK flag.
- **Returns**
	- `sock:net.stream.unix.Server`: instance of net.stream.unix.Server socket.
	- `err:string`: error string.

**e.g.**

```lua
local unix = require('net.stream.unix')
local sock, err = unix.server.new({
	path = '/tmp/example.sock'
})
```

## net.stream.unix.Client

defined in `net.stream.unix` module and inherits from the [net.stream.Socket](#netstreamsocket) class.


### sock, err = unix.client.new( opts )

create an instance of [net.stream.unix.Client](#netstreamunixclient) and initiate a new connection immediately.

- **Parameters**
	- `opts:table`: following fields are defined;
        - `path:string`: pathname of unix domain socket.
        - `nonblock:boolean`: enable the O_NONBLOCK flag.
- **Returns**
	- `sock:net.stream.unix.Client`: instance of net.stream.unix.Client socket.
	- `err:string`: error string.

**e.g.**

```
local unix = require('net.stream.unix')
local sock, err = unix.client.new({
    host = '/tmp/example.sock'
})
```

### err = sock:connect()

initiate a new connection, and close an old connection if succeeded.

- **Returns**
	- `err:string`: error string.


## Functions in net.stream module

`net.stream` module has the following functions.

### socks, err = stream.pair( opts )

create a pair of connected sockets

- **Parameters**
	- `opts:table`: following fields are defined;
        - `nonblock:boolean`: enable the O_NONBLOCK flag.
- **Returns**
	- `socks:table`: pair of connected sockets.
		- `1`: [net.stream.Socket](#netstreamsocket)
		- `2`: [net.stream.Socket](#netstreamsocket)
	- `err:string`: error string.

**e.g.**

```lua
local stream = require('net.stream')
local socks, err = stream.pair()
```


### ai, err = stream.getaddrinfoin( opts )

get a address info of tcp stream socket.

 - **Parameters**
	- `opts:table`: following fields are defined;
        - `host:string`: hostname.
        - `port:string`: either a decimal port number or a service name listed in services(5).
        - `passive:boolean`: enable AI_PASSIVE flag.
        - `canonname:boolean`: enable AI_CANONNAME flag.
        - `numeric:boolean`: use AI_NUMERICHOST flag.
- **Returns**
	- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
	- `err:string`: error string.


### ai, err = stream.getaddrinfoun( opts )

get a address info of unix domain stream socket.

 - **Parameters**
	- `opts:table`: following fields are defined;
        - `path:string`: pathname of unix domain socket.
        - `passive:boolean`: enable AI_PASSIVE flag.
- **Returns**
	- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
	- `err:string`: error string.


***

