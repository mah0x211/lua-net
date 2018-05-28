lua-net
=======

this is wrapper module for llsocket module.

**NOTE: this module is under heavy development.**

***

## Dependencies

- halo: https://github.com/mah0x211/lua-halo
- libtls: https://github.com/mah0x211/lua-libtls
- llsocket: https://github.com/mah0x211/lua-llsocket


## Optional Dependencies

- act: https://github.com/mah0x211/lua-act


## Installation

```
$ luarocks install net --from=http://mah0x211.github.io/rocks/
```

## Usage

**TODO**

> please see the [example files](example/).


***


## Classes

- [net.CmsgHdr](#netcmsghdr)
- [net.MsgHdr](#netmsghdr)
- [net.Socket](#netsocket)
    - **Stream Socket**
        - [net.stream.Socket](#netstreamsocket)
            - [net.stream.Server](#netstreamserver)
                - [net.stream.inet.Server](#netstreaminetserver)
                - [net.stream.unix.Server](#netstreamunixserver)
            - [net.stream.inet.Client](#netstreaminetclient)
            - [net.stream.unix.Socket](#netstreamunixsocket)
                - [net.stream.unix.Client](#netstreamunixclient)
        - [Functions in net.stream module](#functions-in-netstream-module)
        - [Functions in net.stream.unix module](#functions-in-netstreamunix-module)
    - **Datagram Socket**
        - [net.dgram.Socket](#netdgramsocket)
            - [net.dgram.inet.Socket](#netdgraminetsocket)
            - [net.dgram.unix.Socket](#netdgramunixsocket)
        - [Functions in net.dgram module](#functions-in-netdgram-module)
    - **Unix Socket**
        - [net.unix.Socket](#netunixsocket)
- [Functions in net module](#functions-in-net-module)
- [Constants in net module](#constants-in-net-module)


***


## net.CmsgHdr

defined in `net` module.

**NOTE:** this is same as [llsocket.cmsghdr](https://github.com/mah0x211/lua-llsocket#llsocketcmsghdr-module)


***


## net.MsgHdr

defined in `net` module.


### msg, err = msghdr.new()

create an instance of [net.MsgHdr](#netmsghdr).

**Returns**

- `msg:net.MsgHdr`: instance of net.MsgHdr.
- `err:string`: error string.

**e.g.**

```lua
local net = require('net')
local msg, err = net.msghdr.new()
```

### ai = msg:name( [ai] )

get the address-info, or change it to specified address-info. if argument is a nil, associated address-info will be removed.

**Parameters**

- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

**Returns**

- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


### cmsgs = msg:control()

get cmsgs.

**Returns**

- `cmsgs:llsocket.cmsghdrs`: instance of [llsocket.cmsghdrs](https://github.com/mah0x211/lua-llsocket#llsocketcmsghdrs-instance-methods).


### bytes = msg:bytes()

get a number of bytes used.

**Returns**

- `bytes:number`: number of bytes used.


### bytes = msg:consume( bytes )

delete the specified number of bytes of data.

**Parameters**

- `bytes:number`: number of bytes delete.

**Returns**

- `bytes:number`: number of bytes used.


### str = msg:concat()

concatenate all data of elements in use into a string.

**Returns**

- `str:string`: string.


### idx, err = msg:add( str )

add an element with specified string.

**Parameters**

- `str:string`: string.

**Returns**

- `idx:number`: index number of added element.
- `err:string`: error string.


### idx, err = msg:addn( bytes )

add an element that size of specified number of bytes.

**Parameters**

- `bytes:number`: number of bytes.

**Returns**

- `idx:number`: index number of added element.
- `err:string`: error string.


### str = msg:get( idx )

get a string of element at specified index.

**Parameters**

- `idx:number`: index of element.

**Returns**

- `str:string`: string of element.


### str, midx = msg:del( idx )

delete an element at specified index.

**Parameters**

- `idx:number`: index of element.

**Returns**

- `str:string`: string of deleted element.
- `midx:number`: index number of moved element.


***


## net.Socket

defined in `net` module.
net.Socket is the root class of other class hierarchies.


### fd = sock:fd()

get socket file descriptor.

**Returns**

- `fd:number`: socket file descriptor


### fn, err = sock:onwaitrecv( fn, ctx )

set a hook function that invokes before waiting for receivable data arrivals.

**Parameters**

- `fn:function`: a hook function.
- `ctx:any`: context object.

**Returns**

- `fn:function`: old hook function.
- `err:string`: error string.


### fn, err = sock:onwaitsend( fn, ctx )

set a hook function that invokes before waiting for send buffer has decreased.

**Parameters**

- `fn:function`: a hook function.
- `ctx:any`: context object.

**Returns**

- `fn:function`: old hook function.
- `err:string`: error string.


### af = sock:family()

get a address family type.

**Returns**

- `af:number`: family type constants ([AF_* Types](https://github.com/mah0x211/lua-llsocket#af_-types)).


#### ai, err = sock:getsockname()

get socket name.

**Returns**

- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `err:string`: error string.


### ai, err = sock:getpeername()

get address of connected peer.

**Returns**: same as [getsockname](#ai-err--sockgetsockname).


### err = sock:closer()

disable the input operations.

**Returns**

- `err:string`: error string.

### err = sock:closew()

disable the output operations.

**Returns**

- `err:string`: error string.


### err = sock:close( [shutrd [, shutwr]] )

close a socket file descriptor.

**Parameters**

- `shutrd:boolean`: disabling the input operations before close a descriptor. (default `false`)
- `shutwr:boolean`: disabling the output operations before close a descriptor. (default `false`)

**Returns**

- `err:string`: error string.


### bool, err = sock:atmark()

determine whether socket is at out-of-band mark.

**Returns**

- `bool:boolean`: true if the socket is at the out-of-band mark, or false if it is not.
- `err:string`: error string.


### bool, err = sock:cloexec( [bool] )

determine whether the FD_CLOEXEC flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the FD_CLOEXEC flag.

**Returns**

- `bool:boolean`: state of the FD_CLOEXEC flag.
- `err:string`: error string.


### bool = sock:isnonblock()

determine whether the O_NONBLOCK flag enabled.

**Returns**

- `bool:boolean`: state of the O_NONBLOCK flag.


### typ, err = sock:socktype()

get socket type.

**Returns**

- `typ:number`: socket type constants ([SOCK_* Types](https://github.com/mah0x211/lua-llsocket#sock_-types)).
- `err:string`: error string.


### proto = sock:protocol()

get a protocol type.

**Returns**

- `proto:number`: protocol type constants ([IPPROTO_* Types](https://github.com/mah0x211/lua-llsocket#ipproto_-types)).


### soerr, err = sock:error()

get pending socket error status with and clears it.

**Returns**

- `soerr:string`: socket error string.
- `err:string`: error string.


### bool, err = sock:reuseport( [bool] )

determine whether the SO_REUSEPORT flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the SO_REUSEPORT flag.

**Returns**

- `bool:boolean`: state of the SO_REUSEADDR flag.
- `err:string`: error string.


### bool, err = sock:reuseaddr( [bool] )

determine whether the SO_REUSEADDR flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the SO_REUSEADDR flag.

**Returns**

- `bool:boolean`: state of the SO_REUSEADDR flag.
- `err:string`: error string.


### bool, err = sock:debug( [bool] )

determine whether the SO_DEBUG flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the SO_DEBUG flag.

**Returns**

- `bool:boolean`: state of the SO_DEBUG flag.
- `err:string`: error string.


### bool, err = sock:dontroute( [bool] )

determine whether the SO_DONTROUTE flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the SO_DONTROUTE flag.

**Returns**

- `bool:boolean`: state of the SO_DONTROUTE flag.
- `err:string`: error string.


### bool, err = sock:timestamp( [bool] )

determine whether the SO_TIMESTAMP flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the SO_TIMESTAMP flag.

**Returns**

- `bool:boolean`: state of the SO_TIMESTAMP flag.
- `err:string`: error string.


### bytes, err = sock:rcvbuf( [bytes] )

get the SO_RCVBUF value, or change that value to an argument value.

**Parameters**

- `bytes:number`: set the SO_RCVBUF value.

**Returns**

- `bytes:number`: value of the SO_RCVBUF.
- `err:string`: error string.


### bytes, err = sock:rcvlowat( [bytes] )

get the SO_RCVLOWAT value, or change that value to an argument value.

**Parameters**

- `bytes:number`: set the SO_RCVLOWAT value.

**Returns**

- `bytes:number`: value of the SO_RCVLOWAT.
- `err:string`: error string.


### bytes, err = sock:sndbuf( [bytes] )

get the SO_SNDBUF value, or change that value to an argument value.

**Parameters**

- `bytes:number`: set the SO_SNDBUF value.

**Returns**

- `bytes:number`: value of the SO_SNDBUF.
- `err:string`: error string.


### bytes, err = sock:sndlowat( [bytes] )

get the SO_SNDLOWAT value, or change that value to an argument value.

**Parameters**

- `bytes:number`: set the SO_SNDLOWAT value.

**Returns**

- `bytes:number`: value of the SO_SNDLOWAT.
- `err:string`: error string.


### sec, err = sock:rcvtimeo( [sec] )

get the SO_RCVTIMEO value, or change that value to an argument value.

**Parameters**

- `sec:number`: set the SO_RCVTIMEO value.

**Returns**

- `sec:number`: value of the SO_RCVTIMEO.
- `err:string`: error string.


### sec, err = sock:sndtimeo( [sec] )

get the SO_SNDTIMEO value, or change that value to an argument value.

**Parameters**

- `sec:number`: set the SO_SNDTIMEO value.

**Returns**

- `sec:number`: value of the SO_SNDTIMEO.
- `err:string`: error string.


### rcvmsec, sndmsec = sock:deadlines( [rcvmsec [, sndmsec] )

get the receive timeout and the send timeout values.

if you specify arguments, these values are changed to argument values.

**NOTE**

if socket is in the **blocking mode**, this method calls the [rcvtimeo](#sec-err--sockrcvtimeo-sec-) and [sndtime](#sec-err--socksndtimeo-sec-) methods internally.


**Parameters**

- `rcvmsec:number`: set the receive timeout in milliseconds.
- `sndmsec:number`: set the send timeout in milliseconds.

**Returns**

- `rcvmsec:number`: the receive timeout.
- `sndmsec:number`: the send timeout.


### sec, err = sock:linger( [sec] )

get the SO_LINGER value, or change that value to an argument value.

**Parameters**

- `sec:number`: if sec >= 0 then enable SO_LINGER option, or else disabled this option.

**Returns**

- `sec:number`: nil or a value of the SO_LINGER.
- `err:string`: error string.


### str, err, timeout = sock:recv( [bufsize] )

receive a message from a socket.

**Parameters**

- `bufsize:number`: working buffer size of receive operation.

**Returns**

- `str:string`: received message string.
- `err:string`: error string.
- `timeout:boolean`: true if operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


### str, err, timeout = sock:recvsync( [bufsize] )

synchronous version of recv method that uses advisory lock.


### len, err, timeout = sock:recvmsg( msg )

receive multiple messages and ancillary data from a socket.


**Parameters**

- `msg:net.MsgHdr`: [net.MsgHdr](#netmsghdr).

**Returns**

- `len:number`: the number of bytes received.
- `err:string`: error string.
- `timeout:boolean`: true if len is not equal to msg:bytes() or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


### len, err, timeout = sock:recvmsgsync( msg )

synchronous version of recvmsg method that uses advisory lock.


### len, err, timeout = sock:send( str )

send a message from a socket.

**Parameters**

- `str:string`: message string.

**Returns**

- `len:number`: the number of bytes sent.
- `err:string`: error string.
- `timeout:boolean`: true if len is not equal to #str or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


### len, err, timeout = sock:sendsync( str )

synchronous version of send method that uses advisory lock.


### len, err, timeout = sock:sendmsg( msg )

send multiple messages and ancillary data from a socket.


**Parameters**

- `msg:net.MsgHdr`: [net.MsgHdr](#netmsghdr).

**Returns**

- `len:number`: the number of bytes sent.
- `err:string`: error string.
- `timeout:boolean`: true if len is not equal to msg:bytes() or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


### len, err, timeout = sock:sendmsgsync( msg )

synchronous version of sendmsg method that uses advisory lock.


***


## net.stream.Socket

defined in `net.stream` module and inherits from the [net.Socket](#netsocket) class.


### bool, err = sock:acceptconn()

determine whether the SO_ACCEPTCONN flag enabled.

**Returns**

- `bool:boolean`: state of the SO_ACCEPTCONN flag.
- `err:string`: error string.


### bool, err = sock:oobinline( [bool] )

determine whether the SO_OOBINLINE flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the SO_OOBINLINE flag.

**Returns**

- `bool:boolean`: state of the SO_OOBINLINE flag.
- `err:string`: error string.


### bool, err = sock:keepalive( [bool] )

determine whether the SO_KEEPALIVE flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the SO_KEEPALIVE flag.

**Returns**

- `bool:boolean`: state of the SO_KEEPALIVE flag.
- `err:string`: error string.


### bool, err = sock:tcpnodelay( [bool] )

determine whether the TCP_NODELAY flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the TCP_NODELAY flag.

**Returns**

- `bool:boolean`: state of the TCP_NODELAY flag.
- `err:string`: error string.


### bool, err = sock:tcpcork( [bool] )

determine whether the TCP_CORK flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the TCP_CORK flag.

**Returns**

- `bool:boolean`: state of the TCP_CORK flag.
- `err:string`: error string.


### sec, err = sock:tcpkeepalive( [sec] )

get the TCP_KEEPALIVE value, or set that value if argument passed.

**Parameters**

- `sec:number`: set the TCP_KEEPALIVE value.

**Returns**

- `sec:number`: value of the TCP_KEEPALIVE.
- `err:string`: error string.


### sec, err = sock:tcpkeepintvl( [sec] )

get the TCP_KEEPINTVL value, or change that value to an argument value.

**Parameters**

- `sec:number`: set the TCP_KEEPINTVL value.

**Returns**

- `sec:number`: value of the TCP_KEEPINTVL.
- `err:string`: error string.


### cnt, err = sock:tcpkeepcnt( [cnt] )

get the TCP_KEEPCNT value, or change that value to an argument value.

**Parameters**

- `cnt:number`: set the TCP_KEEPCNT value.

**Returns**

- `sec:number`: value of the TCP_KEEPCNT.
- `err:string`: error string.


### len, err, timeout = sock:sendfile( fd, bytes [, offset] )

send a file from a socket.

**Parameters**

- `fd:number`: file descriptor.
- `bytes:number`: how many bytes of the file should be sent.
- `offset:number`: specifies where to begin in the file (default 0).

**Returns**

- `len:number`: number of bytes sent.
- `err:string`: error string.
- `timeout:boolean`: true if len not equal to bytes or operation has timed out.


**NOTE:** all return values will be nil if closed by peer.


### len, err, timeout = sock:sendfilesync( fd, bytes [, offset] )

synchronous version of sendfile method that uses advisory lock.


***


## net.stream.Server

defined in `net.stream` module and inherits from the [net.stream.Socket](#netstreamsocket) class.


### err = sock:listen( [backlog] )

listen for connections.

**Parameters**

- `backlog:number`: backlog size. (default SOMAXCONN)

**Returns**

- `err:string`: error string.


### sock, err = sock:accept()

accept a connection.

**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](#netstreamsocket).
- `err:string`: error string.


### fd, err = sock:acceptfd()

accept a connection.

**Returns**

- `fd:number`: socket file descriptor.
- `err:string`: error string.


### sock = sock:createConnection( sock, tls )

create a connection socket as a [net.stream.Socket](#netstreamsocket).

**Parameters**

- `sock:`: instance of [llsocket.socket](https://github.com/mah0x211/lua-llsocket#llsocketsocket-instance-methods)
- `tls:libtls.config`: instance of [libtls](https://github.com/mah0x211/lua-libtls#client-err--ctxaccept_socket-fd-)

**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](#netstreamsocket).


***


## net.stream.inet.Server

defined in `net.stream.inet` module and inherits from the [net.stream.Server](#netstreamserver) class.


### sock, err = inet.server.new( opts )

create an instance of [net.stream.inet.Server](#netstreaminetserver).

**Parameters**

- `opts:table`: following fields are defined;
    - `host:string`: hostname.
    - `port:string`: either a decimal port number or a service name listed in services(5).
    - `reuseaddr:boolean`: enable the SO_REUSEADDR flag. (default `true`)
    - `reuseport:boolean`: enable the SO_REUSEPORT flag.
    - `tcpnodelay:boolean`: enable the TCP_NODELAY flag. (default `false` in blocking mode)
    - `tlscfg:libtls.config`: instance of [libtls.config](https://github.com/mah0x211/lua-libtls#libtlsconfig-module)

**Returns**

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


***


## net.stream.inet.Client

defined in `net.stream.inet` module and inherits from the [net.stream.Socket](#netstreamsocket) class.


### sock, err, timeout = inet.client.new( opts [, connect [, conndeadl]] )

create an instance of [net.stream.inet.Client](#netstreaminetclient) and initiate a new connection immediately.

**Parameters**

- `opts:table`: following fields are defined;
    - `host:string`: hostname.
    - `port:string`: either a decimal port number or a service name listed in services(5).
    - `tcpnodelay:boolean`: enable the TCP_NODELAY flag. (default `false` in blocking mode)
    - `tlscfg:libtls.config`: instance of [libtls.config](https://github.com/mah0x211/lua-libtls#libtlsconfig-module)
    - `servername:string`: servername.
- `connect:boolean`: to connect immediately. (default `true`)
- `conndeadl:number`: specify a timeout milliseconds as unsigned integer.

**Returns**

- `sock:net.stream.inet.Client`: instance of net.stream.inet.Client.
- `err:string`: error string.
- `timeout:boolean`: true if operation has timed out.

**e.g.**

```lua
local inet = require('net.stream.inet')
local sock, err = inet.client.new({
    host = '127.0.0.1',
    port = '8080'
})
```

### err, timeout = sock:connect( [conndeadl] )

initiate a new connection, and close an old connection if succeeded.

**Parameters**

- `conndeadl:number`: specify a timeout milliseconds as unsigned integer.

**Returns**

- `err:string`: error string.
- `timeout:boolean`: true if operation has timed out.


***


## net.stream.unix.Server

defined in `net.stream.unix` module and inherits from the [net.stream.Server](#netstreamserver) class.


### sock, err = unix.server.new( opts )

create an instance of [net.stream.unix.Server](#netstreamunixserver).

**Parameters**

- `opts:table`: following fields are defined;
    - `pathname:string`: pathname of unix domain socket.
    - `tlscfg:libtls.config`: instance of [libtls.config](https://github.com/mah0x211/lua-libtls#libtlsconfig-module)

**Returns**

- `sock:net.stream.unix.Server`: instance of net.stream.unix.Server.
- `err:string`: error string.

**e.g.**

```lua
local unix = require('net.stream.unix')
local sock, err = unix.server.new({
    path = '/tmp/example.sock'
})
```


***


## net.stream.unix.Socket

defined in `net.stream.unix` module and inherits from the [net.unix.Socket](#netunixsocket) class.


***


## net.stream.unix.Client

defined in `net.stream.unix` module and inherits from the [net.stream.Socket](#netstreamsocket) and [net.unix.Socket](#netunixsocket) classes.


### sock, err, timeout = unix.client.new( opts [, connect [, conndeadl]] )

create an instance of [net.stream.unix.Client](#netstreamunixclient) and initiate a new connection immediately.

**Parameters**

- `opts:table`: following fields are defined;
    - `pathname:string`: pathname of unix domain socket.
    - `tlscfg:libtls.config`: instance of [libtls.config](https://github.com/mah0x211/lua-libtls#libtlsconfig-module)
    - `servername:string`: servername.
- `connect:boolean`: to connect immediately. (default `true`)
- `conndeadl:number`: specify a timeout milliseconds as unsigned integer.

**Returns**

- `sock:net.stream.unix.Client`: instance of net.stream.unix.Client.
- `err:string`: error string.
- `timeout:boolean`: true if operation has timed out.

**e.g.**

```
local unix = require('net.stream.unix')
local sock, err = unix.client.new({
    path = '/tmp/example.sock'
})
```

### err, timeout = sock:connect( [conndeadl] )

initiate a new connection, and close an old connection if succeeded.

**Parameters**

- `conndeadl:number`: specify a timeout milliseconds as unsigned integer.

**Returns**

- `err:string`: error string.
- `timeout:boolean`: true if operation has timed out.


***


## Functions in net.stream module

`net.stream` module has the following functions.

### socks, err = stream.wrap( fd )

create an instance of socket from specified socket file descriptor.

**Parameters**

- `fd:number`: socket file descriptor.

**Returns**

- `sock:net.stream.Socket`: instance of [net.stream.Socket](#netstreamsocket).
- `err:string`: error string.


### ai, err = stream.getaddrinfoin( opts )

get an address info of tcp stream socket.

**Parameters**

- `opts:table`: following fields are defined;
    - `host:string`: hostname.
    - `port:string`: either a decimal port number or a service name listed in services(5).
    - `passive:boolean`: enable AI_PASSIVE flag.
    - `canonname:boolean`: enable AI_CANONNAME flag.
    - `numeric:boolean`: enable AI_NUMERICHOST flag.

**Returns**

- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `err:string`: error string.


### ai, err = stream.getaddrinfoun( opts )

get an address info of unix domain stream socket.

**Parameters**

- `opts:table`: following fields are defined;
    - `path:string`: pathname of unix domain socket.
    - `passive:boolean`: enable AI_PASSIVE flag.

**Returns**

- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `err:string`: error string.


***


## Functions in net.stream.unix module

`net.stream.unix` module has the following functions.

### socks, err = unix.pair()

create a pair of connected sockets

**Returns**

- `socks:table`: pair of connected sockets.
    - `1`: [net.stream.unix.Socket](#netstreamunixsocket)
    - `2`: [net.stream.unix.Socket](#netstreamunixsocket)
- `err:string`: error string.

**e.g.**

```lua
local unix = require('net.stream.unix')
local socks, err = unix.pair()
```


***


## net.dgram.Socket

defined in `net.dgram` module and inherits from the [net.Socket](#netsocket) class.


### bool, err = sock:mcastloop( [bool] )

determine whether the IP_MULTICAST_LOOP flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the IP_MULTICAST_LOOP flag.

**Returns**

- `bool:boolean`: state of the IP_MULTICAST_LOOP flag.
- `err:string`: error string.


### ttl, err = sock:mcastttl( [ttl] )

get the IP_MULTICAST_TTL value, or change that value to an argument value.

**Parameters**

- `ttl:number`: set the IP_MULTICAST_TTL value.

**Returns**

- `sec:number`: value of the IP_MULTICAST_TTL.
- `err:string`: error string.


### ifname, err = sock:mcastif( [ifname] )

get the IP_MULTICAST_IF value, or change that value to an argument value.

**Parameters**

- `ifname:string`: set the IP_MULTICAST_IF value.

**Returns**

- `ifnames:string`: value of the IP_MULTICAST_IF.
- `err:string`: error string.


### err = sock:mcastjoin( mcaddr [, ifname] )

set the IP_ADD_MEMBERSHIP or IPV6_JOIN_GROUP (if IPv6) value.

**Parameters**

- `mcaddr:string`: multicast group address.
- `ifname:string`: interface name.

**Returns**

- `err:string`: error string.


### err = sock:mcastleave( mcaddr [, ifname] )

set the IP_DROP_MEMBERSHIP or IPV6_LEAVE_GROUP (if IPv6) value.

**Parameters**

- `mcaddr:string`: multicast group address.
- `ifname:string`: interface name.

**Returns**

- `err:string`: error string.


### err = sock:mcastjoinsrc( mcaddr, srcaddr [, ifname] )

set the IP_ADD_SOURCE_MEMBERSHIP or MCAST_JOIN_SOURCE_GROUP (if IPv6) value.

**Parameters**

- `mcaddr:string`: multicast group address.
- `srcaddr:string`: multicast source address.
- `ifname:string`: interface name.

**Returns**

- `err:string`: error string.


### err = sock:mcastleavesrc( mcaddr, srcaddr [, ifname] )

set the IP_DROP_SOURCE_MEMBERSHIP or MCAST_LEAVE_SOURCE_GROUP (if IPv6) value.

**Parameters**

- `mcaddr:string`: multicast group address.
- `srcaddr:string`: multicast source address.
- `ifname:string`: interface name.

**Returns**

- `err:string`: error string.


### err = sock:mcastblocksrc( mcaddr, srcaddr [, ifname] )

set the IP_BLOCK_SOURCE or MCAST_BLOCK_SOURCE (if IPv6) value.

**Parameters**

- `mcaddr:string`: multicast group address.
- `srcaddr:string`: multicast source address.
- `ifname:string`: interface name.

**Returns**

- `err:string`: error string.


### err = sock:mcastunblocksrc( mcaddr, srcaddr [, ifname] )

set the IP_UNBLOCK_SOURCE or MCAST_UNBLOCK_SOURCE (if IPv6) value.

**Parameters**

- `mcaddr:string`: multicast group address.
- `srcaddr:string`: multicast source address.
- `ifname:string`: interface name.

**Returns**

- `err:string`: error string.


### bool, err = sock:broadcast( [bool] )

determine whether the SO_BROADCAST flag enabled, or change the state to an argument value.

**Parameters**

- `bool:boolean`: to enable or disable the SO_BROADCAST flag.

**Returns**

- `bool:boolean`: state of the SO_BROADCAST flag.
- `err:string`: error string.


### str, ai, err, timeout = sock:recvfrom()

receive message and address info from a socket.

**Returns**

- `str:string`: received message string.
- `ai:addrinfo`: instance of instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `err:string`: error string.
- `timeout:boolean`: true if operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


### str, ai, err, timeout = sock:recvfromsync()

synchronous version of recvfrom method that uses advisory lock.


### len, err, timeout = sock:sendto( str, ai )

send a message to specified destination address.

**Parameters**

- `str:string`: message string.
- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

**Returns**

- `len:number`: the number of bytes sent.
- `err:string`: error string.
- `timeout:boolean`: true if len not equal to #str or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


### len, err, timeout = sock:sendtosync( str, ai )

synchronous version of sendto method that uses advisory lock.


***


## net.dgram.inet.Socket

defined in `net.dgram.inet` module and inherits from the [net.dgram.Socket](#netdgramsocket) class.

### sock, err = inet.wrap( fd )

create an instance of [net.dgram.inet.Socket](#netdgraminetsocket) from specified socket file descriptor.

**Parameters**

- `fd:number`: socket file descriptor.

**Returns**

- `sock:net.dgram.inet.Socket`: instance of net.dgram.inet.Socket.
- `err:string`: error string.


### sock, err = inet.new( opts )

create an instance of [net.dgram.inet.Socket](#netdgraminetsocket).

**Parameters**

- `opts:table`: following fields are defined;
    - `host:string`: hostname.
    - `port:string`: either a decimal port number or a service name listed in services(5).
    - `passive:boolean`: enable the AI_PASSIVE flag.
    - `reuseaddr:boolean`: enable the SO_REUSEADDR flag.
    - `reuseport:boolean`: enable the SO_REUSEPORT flag.

**Returns**

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

**Parameters**

- `opts:table`: following fields are defined;
    - `host:string`: hostname.
    - `port:string`: either a decimal port number or a service name listed in services(5).

**Returns**

- `err:string`: error string.


### err = sock:bind( [opts] )

bind a name to a socket.

**Parameters**

- `opts:table`: following fields are defined;
    - `host:string`: hostname.
    - `port:string`: either a decimal port number or a service name listed in services(5).
    - `passive:boolean`: enable AI_PASSIVE flag.
    - `canonname:boolean`: enable AI_CANONNAME flag.
    - `numeric:boolean`: enable AI_NUMERICHOST flag.

**Returns**

- `err:string`: error string.


***


## net.dgram.unix.Socket

defined in `net.dgram.unix` module and inherits from the [net.dgram.Socket](#netdgramsocket) class.


### sock, err = unix.wrap( fd )

create an instance of [net.dgram.unix.Socket](#netdgramunixsocket) from specified socket file descriptor.

**Parameters**

- `fd:number`: socket file descriptor.

**Returns**

- `sock:net.dgram.unix.Socket`: instance of net.dgram.unix.Socket.
- `err:string`: error string.


### socks, err = unix.pair()

create a pair of connected sockets

**Returns**

- `socks:table`: pair of connected sockets.
    - `1`: [net.dgram.unix.Socket](#netdgramunixsocket)
    - `2`: [net.dgram.unix.Socket](#netdgramunixsocket)
- `err:string`: error string.

**e.g.**

```lua
local unix = require('net.dgram.unix')
local socks, err = unix.pair()
```


### sock, err = unix.new( opts )

create an instance of [net.dgram.unix.Socket](#netdgramunixsocket).

**Parameters**

- `opts:table`: following fields are defined;
    - `pathname:string`: pathname of unix domain socket.

**Returns**

- `sock:net.dgram.unix.Socket`: instance of net.dgram.unix.Socket.
- `err:string`: error string.

**e.g.**

```lua
local unix = require('net.dgram.unix')
local sock, err = unix.new({
    path = '/tmp/example.sock'
})
```

### err = sock:connect( [opts] )

set a destination address.

**Parameters**

- `opts:table`: following fields are defined;
    - `pathname:string`: pathname of unix domain socket.

**Returns**

- `err:string`: error string.


### err = sock:bind( [opts] )

bind a name to a socket.

**Parameters**

- `opts:table`: following fields are defined;
    - `pathname:string`: pathname of unix domain socket.

**Returns**

- `err:string`: error string.


***


## Functions in net.dgram module

`net.dgram` module has the following functions.


### ai, err = dgram.getaddrinfoin( opts )

get an address info of datagram socket.

**Parameters**

- `opts:table`: following fields are defined;
    - `host:string`: hostname.
    - `port:string`: either a decimal port number or a service name listed in services(5).
    - `passive:boolean`: enable AI_PASSIVE flag.
    - `canonname:boolean`: enable AI_CANONNAME flag.
    - `numeric:boolean`: enable AI_NUMERICHOST flag.

**Returns**

- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `err:string`: error string.


### ai, err = dgram.getaddrinfoun( opts )

get an address info of unix domain datagram socket.

**Parameters**

- `opts:table`: following fields are defined;
    - `path:string`: pathname of unix domain socket.

**Returns**

- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).
- `err:string`: error string.


***

## net.unix.Socket

defined in `net.unix` module and inherits from the [net.Socket](#netsocket) class.


### len, err = sock:sendfd( fd [, ai] )

send file descriptors along unix domain sockets.

**Parameters**

- `fd:number`: file descriptor;
- `ai:addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

**Returns**

- `len:number`: the number of bytes sent (always zero).
- `err:string`: error string.
- `again:bool`: true if errno is EAGAIN, EWOULDBLOCK, EINTR or EMSGSIZE.

**NOTE:** all return values will be nil if closed by peer.


### len, err = sock:sendfdsync( fd [, ai] )

synchronous version of sendfd method that uses advisory lock.


### fd, err, again = sock:recvfd()

receive file descriptors along unix domain sockets.

**Returns**

- `fd:number`: file descriptor.
- `err:string`: error string.
- `again:bool`: true either if errno is EAGAIN, EWOULDBLOCK or EINTR, or if socket type is SOCK_DGRAM or SOCK_RAW.

**NOTE:** all return values will be nil if closed by peer.


### fd, err, again = sock:recvfd()

synchronous version of recvfd method that uses advisory lock.


***

## Functions in net module

`net` module has the following functions.

### err = shutdown( fd, flag )

shut down part of a full-duplex connection.

**Parameters**

- `fd:number`: socket file descriptor.
- `flag:number`: [SHUT_* flag](#shut_-flags) constants.

**Returns**

- `err:string`: error string.


### err = close( fd [, flag] )

close a socket file descriptor.

**Parameters**

- `fd:number`: socket file descriptor.
- `flag:number`: [SHUT_* flag](#shut_-flags) constants.

**Returns**

- `err:string`: error string.


***

## Constants in net module


### SHUT_* Flags

- `SHUT_RD`: shut down the reading side
- `SHUT_WR`: shut down the writing side
- `SHUT_RDWR`: shut down both sides


**TODO**

