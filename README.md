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
    - **Datagram Socket**
        - [net.dgram.Socket](#netdgramsocket)
            - [net.dgram.inet.Socket](#netdgraminetsocket)
            - [net.dgram.unix.Socket](#netdgramunixsocket)
        - [Functions in net.stream module](#functions-in-netdgram-module)
- [Constants in net module](#constants-in-net-module)


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

- **Returns**: same as [getsockname](#ai-err--sockgetsockname).


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

determine whether the SO_REUSEPORT flag enabled, or change the state to an argument value.

- **Parameters**
    - `bool:boolean`: to enable or disable the SO_REUSEPORT flag.
- **Returns**
    - `bool:boolean`: state of the SO_REUSEADDR flag.
    - `err:string`: error string.


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


### sock:initq()

auxiliary method for the non-blocking socket.

initialize a send queue for [sendq](#len-err-again--socksendq-str-) and [fluashq](#len-err-again--sockflushq) uses.


### len, err, again = sock:sendq( str )

auxiliary method for the non-blocking socket.

if `again` is equal to true, you must be calling a [fluashq](#len-err-again--sockflushq) method when socket is writable.


- **Parameters**
    - `str:string`: message string.
- **Returns**
    - `len:number`:  the number of bytes sent.
    - `err:string`: error string.
    - `again:bool`: true if len != #str, or errno is EAGAIN, EWOULDBLOCK or EINTR. also, save a remaining bytes of str into send queue.

**NOTE:** all return values will be nil if closed by peer.


### len, err, again = sock:flushq()

auxiliary method for the non-blocking socket.

send queued messages to socket.

- **Returns**
    - `len:number`: the number of bytes sent.
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


### sec, err = sock:tcpkeepintvl( [sec] )

get the TCP_KEEPINTVL value, or change that value to an argument value.

- **Parameters**
    - `sec:number`: set the TCP_KEEPINTVL value.
- **Returns**
    - `sec:number`:  value of the TCP_KEEPINTVL.
    - `err:string`: error string.


### cnt, err = sock:tcpkeepcnt( [cnt] )

get the TCP_KEEPCNT value, or change that value to an argument value.

- **Parameters**
    - `cnt:number`: set the TCP_KEEPCNT value.
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


### sock, err, again = sock:accept()

accept a connection.

- **Returns**
    - `sock:net.stream.Socket`: instance of [net.stream.Socket](#netstreamsocket).
    - `err:string`: error string.
    - `again:bool`: true if errno is EAGAIN, EWOULDBLOCK, EINTR or ECONNABORTED.


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
    - `sock:net.stream.inet.Server`: instance of net.stream.inet.Server.
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


### sock, err, again = inet.client.new( opts )

create an instance of [net.stream.inet.Client](#netstreaminetclient) and initiate a new connection immediately.

- **Parameters**
    - `opts:table`: following fields are defined;
        - `host:string`: hostname.
        - `port:string`: either a decimal port number or a service name listed in services(5).
        - `nonblock:boolean`: enable the O_NONBLOCK flag.
- **Returns**
    - `sock:net.stream.inet.Client`: instance of net.stream.inet.Client.
    - `err:string`: error string.
    - `again:bool`: true if errno is EINPROGRESS.

**e.g.**

```lua
local inet = require('net.stream.inet')
local sock, err = inet.client.new({
    host = '127.0.0.1',
    port = '8080'
})
```

### err, again = sock:connect()

initiate a new connection, and close an old connection if succeeded.

- **Returns**
    - `err:string`: error string.
    - `again:bool`: true if errno is EINPROGRESS.



## net.stream.unix.Server

defined in `net.stream.unix` module and inherits from the [net.stream.Server](#netstreamserver) class.


### sock, err = unix.server.new( opts )

create an instance of [net.stream.unix.Server](#netstreamunixserver).

- **Parameters**
    - `opts:table`: following fields are defined;
        - `pathname:string`: pathname of unix domain socket.
        - `nonblock:boolean`: enable the O_NONBLOCK flag.
- **Returns**
    - `sock:net.stream.unix.Server`: instance of net.stream.unix.Server.
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


### sock, err, again = unix.client.new( opts )

create an instance of [net.stream.unix.Client](#netstreamunixclient) and initiate a new connection immediately.

- **Parameters**
    - `opts:table`: following fields are defined;
        - `pathname:string`: pathname of unix domain socket.
        - `nonblock:boolean`: enable the O_NONBLOCK flag.
- **Returns**
    - `sock:net.stream.unix.Client`: instance of net.stream.unix.Client.
    - `err:string`: error string.
    - `again:bool`: true if errno is EINPROGRESS.

**e.g.**

```
local unix = require('net.stream.unix')
local sock, err = unix.client.new({
    host = '/tmp/example.sock'
})
```

### err, again = sock:connect()

initiate a new connection, and close an old connection if succeeded.

- **Returns**
    - `err:string`: error string.
    - `again:bool`: true if errno is EINPROGRESS.


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

get an address info of tcp stream socket.

 - **Parameters**
    - `opts:table`: following fields are defined;
        - `host:string`: hostname.
        - `port:string`: either a decimal port number or a service name listed in services(5).
        - `passive:boolean`: enable AI_PASSIVE flag.
        - `canonname:boolean`: enable AI_CANONNAME flag.
        - `numeric:boolean`: enable AI_NUMERICHOST flag.
- **Returns**
    - `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
    - `err:string`: error string.


### ai, err = stream.getaddrinfoun( opts )

get an address info of unix domain stream socket.

 - **Parameters**
    - `opts:table`: following fields are defined;
        - `path:string`: pathname of unix domain socket.
        - `passive:boolean`: enable AI_PASSIVE flag.
- **Returns**
    - `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
    - `err:string`: error string.


***

## net.dgram.Socket

defined in `net.stream` module and inherits from the [net.Socket](#netsocket) class.


### bool, err = sock:mcastloop( [bool] )

determine whether the IP_MULTICAST_LOOP flag enabled, or change the state to an argument value.

- **Parameters**
    - `bool:boolean`: to enable or disable the IP_MULTICAST_LOOP flag.
- **Returns**
    - `bool:boolean`: state of the IP_MULTICAST_LOOP flag.
    - `err:string`: error string.


### ttl, err = sock:mcastttl( [ttl] )

get the IP_MULTICAST_TTL value, or change that value to an argument value.

- **Parameters**
    - `ttl:number`: set the IP_MULTICAST_TTL value.
- **Returns**
    - `sec:number`:  value of the IP_MULTICAST_TTL.
    - `err:string`: error string.


### ifname, err = sock:mcastif( [ifname] )

get the IP_MULTICAST_IF value, or change that value to an argument value.

- **Parameters**
    - `ifname:string`: set the IP_MULTICAST_IF value.
- **Returns**
    - `ifnames:string`:  value of the IP_MULTICAST_IF.
    - `err:string`: error string.


### err = sock:mcastjoin( mcaddr [, ifname] )

set the IP_ADD_MEMBERSHIP or IPV6_JOIN_GROUP (if IPv6) value.

- **Parameters**
    - `mcaddr:string`: multicast group address.
    - `ifname:string`: interface name.
- **Returns**
    - `err:string`: error string.


### err = sock:mcastleave( mcaddr [, ifname] )

set the IP_DROP_MEMBERSHIP or IPV6_LEAVE_GROUP (if IPv6) value.

- **Parameters**
    - `mcaddr:string`: multicast group address.
    - `ifname:string`: interface name.
- **Returns**
    - `err:string`: error string.


### err = sock:mcastjoinsrc( mcaddr, srcaddr [, ifname] )

set the IP_ADD_SOURCE_MEMBERSHIP or MCAST_JOIN_SOURCE_GROUP (if IPv6) value.

- **Parameters**
    - `mcaddr:string`: multicast group address.
    - `srcaddr:string`: multicast source address.
    - `ifname:string`: interface name.
- **Returns**
    - `err:string`: error string.


### err = sock:mcastleavesrc( mcaddr, srcaddr [, ifname] )

set the IP_DROP_SOURCE_MEMBERSHIP or MCAST_LEAVE_SOURCE_GROUP (if IPv6) value.

- **Parameters**
    - `mcaddr:string`: multicast group address.
    - `srcaddr:string`: multicast source address.
    - `ifname:string`: interface name.
- **Returns**
    - `err:string`: error string.


### err = sock:mcastblocksrc( mcaddr, srcaddr [, ifname] )

set the IP_BLOCK_SOURCE or MCAST_BLOCK_SOURCE (if IPv6) value.

- **Parameters**
    - `mcaddr:string`: multicast group address.
    - `srcaddr:string`: multicast source address.
    - `ifname:string`: interface name.
- **Returns**
    - `err:string`: error string.


### err = sock:mcastunblocksrc( mcaddr, srcaddr [, ifname] )

set the IP_UNBLOCK_SOURCE or MCAST_UNBLOCK_SOURCE (if IPv6) value.

- **Parameters**
    - `mcaddr:string`: multicast group address.
    - `srcaddr:string`: multicast source address.
    - `ifname:string`: interface name.
- **Returns**
    - `err:string`: error string.


### bool, err = sock:broadcast( [bool] )

determine whether the SO_BROADCAST flag enabled, or change the state to an argument value.

- **Parameters**
    - `bool:boolean`: to enable or disable the SO_BROADCAST flag.
- **Returns**
    - `bool:boolean`:  state of the SO_BROADCAST flag.
    - `err:string`: error string.


### str, ai, err, again = sock:recvfrom()

receive message and address info from a socket.

- **Returns**
    - `str:string`: received message string.
    - `ai:addrinfo`: instance of instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
    - `err:string`: error string.
    - `again:bool`: true if errno is EAGAIN, EWOULDBLOCK or EINTR.

**NOTE:** all return values will be nil if closed by peer.


### len, err, again = sock:sendto( str, addr )

send a message to specified destination address.

- **Parameters**
    - `str:string`: message string.
    - `addr:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
- **Returns**
    - `len:number`:  the number of bytes sent.
    - `err:string`: error string.
    - `again:bool`: true if len != #str, or errno is EAGAIN, EWOULDBLOCK or EINTR.

**NOTE:** all return values will be nil if closed by peer.


### len, err, again = sock:sendqto( str, addr )

auxiliary method for the non-blocking socket.

send a message to specified destination address.

if again is equal to true, you must be calling a [fluashq](#len-err-again--sockflushq) method when socket is writable.

- **Parameters**
    - `str:string`: message string.
    - `addr:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
- **Returns**
    - `len:number`: the number of bytes sent.
    - `err:string`: error string.
    - `again:bool`: true if len != #str, or errno is EAGAIN, EWOULDBLOCK or EINTR. also, save a remaining bytes of str into send queue.

**NOTE:** all return values will be nil if closed by peer.



## net.dgram.inet.Socket

defined in `net.dgram.inet` module and inherits from the [net.dgram.Socket](#netdgramsocket) class.


### sock, err = inet.new( opts )

create an instance of [net.dgram.inet.Socket](#netdgraminetsocket).

- **Parameters**
    - `opts:table`: following fields are defined;
        - `host:string`: hostname.
        - `port:string`: either a decimal port number or a service name listed in services(5).
        - `passive:boolean`: enable the AI_PASSIVE flag.
        - `nonblock:boolean`: enable  the O_NONBLOCK flag.
        - `reuseaddr:boolean`: enable the SO_REUSEADDR flag.
- **Returns**
    - `sock:net.dgram.inet.Socket`: instance of net.dgram.inet.Socket.
    - `err:string`: error string.

**e.g.**

```lua
local inet = require('net.dgram.inet')
local sock, err = inet.new({
    host = '127.0.0.1',
    port = '8080'
})
```

### err = sock:connect( [opts] )

set a destination address.

- **Parameters**
    - `opts:table`: following fields are defined;
        - `host:string`: hostname.
        - `port:string`: either a decimal port number or a service name listed in services(5).
- **Returns**
    - `err:string`: error string.


### err = sock:bind( [opts] )

bind a name to a socket.

- **Parameters**
    - `opts:table`: following fields are defined;
        - `host:string`: hostname.
        - `port:string`: either a decimal port number or a service name listed in services(5).
        - `passive:boolean`: enable AI_PASSIVE flag.
        - `canonname:boolean`: enable AI_CANONNAME flag.
        - `numeric:boolean`: enable AI_NUMERICHOST flag.
- **Returns**
    - `err:string`: error string.



## net.dgram.unix.Socket

defined in `net.dgram.unix` module and inherits from the [net.dgram.Socket](#netdgramsocket) class.


### sock, err = unix.new( opts )

create an instance of [net.dgram.unix.Socket](#netdgramunixsocket).

- **Parameters**
    - `opts:table`: following fields are defined;
        - `pathname:string`: pathname of unix domain socket.
        - `nonblock:boolean`: enable  the O_NONBLOCK flag.
- **Returns**
    - `sock:net.dgram.unix.Socket`: instance of net.dgram.unix.Socket.
    - `err:string`: error string.

**e.g.**

```lua
local unix = require('net.dgram.unix')
local sock, err = inet.new({
    path = '/tmp/example.sock'
})
```

### err = sock:connect( [opts] )

set a destination address.

- **Parameters**
    - `opts:table`: following fields are defined;
        - `pathname:string`: pathname of unix domain socket.
- **Returns**
    - `err:string`: error string.


### err = sock:bind( [opts] )

bind a name to a socket.

- **Parameters**
    - `opts:table`: following fields are defined;
        - `pathname:string`: pathname of unix domain socket.
- **Returns**
    - `err:string`: error string.


## Functions in net.dgram module

`net.dgram` module has the following functions.

### socks, err = dgram.pair( opts )

create a pair of connected sockets

- **Parameters**
    - `opts:table`: following fields are defined;
        - `nonblock:boolean`: enable the O_NONBLOCK flag.
- **Returns**
    - `socks:table`: pair of connected sockets.
        - `1`: [net.dgram.Socket](#netdgramsocket)
        - `2`: [net.dgram.Socket](#netdgramsocket)
    - `err:string`: error string.

**e.g.**

```lua
local dgram = require('net.dgram')
local socks, err = dgram.pair()
```


### ai, err = dgram.getaddrinfoin( opts )

get an address info of datagram socket.

 - **Parameters**
    - `opts:table`: following fields are defined;
        - `host:string`: hostname.
        - `port:string`: either a decimal port number or a service name listed in services(5).
        - `passive:boolean`: enable AI_PASSIVE flag.
        - `canonname:boolean`: enable AI_CANONNAME flag.
        - `numeric:boolean`: enable AI_NUMERICHOST flag.
- **Returns**
    - `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
    - `err:string`: error string.


### ai, err = dgram.getaddrinfoun( opts )

get an address info of unix domain datagram socket.

 - **Parameters**
    - `opts:table`: following fields are defined;
        - `path:string`: pathname of unix domain socket.
- **Returns**
    - `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket).
    - `err:string`: error string.

***

## Constants in net module

**TODO**

