# net.dgram.Socket

defined in [net.dgram](../lib/dgram.lua) module and inherits from the [net.Socket](net_socket.md) class.


## enabled, err = sock:mcastloop( [enable] )

determine whether the `IP_MULTICAST_LOOP` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `IP_MULTICAST_LOOP` flag.

**Returns**

- `enabled:boolean`: state of the `IP_MULTICAST_LOOP` flag.
- `err:error`: error object.


## ttl, err = sock:mcastttl( [ttl] )

get the `IP_MULTICAST_TTL` value, or change that value to an argument value.

**Parameters**

- `ttl:integer`: set the `IP_MULTICAST_TTL` value.

**Returns**

- `ttl:integer`: value of the `IP_MULTICAST_TTL`.
- `err:error`: error object.


## ifname, err = sock:mcastif( [ifname] )

get the `IP_MULTICAST_IF` value, or change that value to an argument value.

**Parameters**

- `ifname:string`: set the `IP_MULTICAST_IF` value.

**Returns**

- `ifnames:string`: value of the `IP_MULTICAST_IF`.
- `err:error`: error object.


## ok, err = sock:mcastjoin( grp [, ifname] )

set the `IP_ADD_MEMBERSHIP` or `IPV6_JOIN_GROUP` (if IPv6) value.

**Parameters**

- `grp:net.addrinfo`: multicast group address.
- `ifname:string`: interface name.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## ok, err = sock:mcastleave( grp [, ifname] )

set the `IP_DROP_MEMBERSHIP` or `IPV6_LEAVE_GROUP` (if IPv6) value.

**Parameters**

- `grp:net.addrinfo`: multicast group address.
- `ifname:string`: interface name.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## ok, err = sock:mcastjoinsrc( grp, src [, ifname] )

set the `IP_ADD_SOURCE_MEMBERSHIP` or `MCAST_JOIN_SOURCE_GROUP` (if IPv6) value.

**Parameters**

- `grp:net.addrinfo`: multicast group address.
- `src:net.addrinfo`: multicast source address.
- `ifname:string`: interface name.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## ok, err = sock:mcastleavesrc( grp, src [, ifname] )

set the `IP_DROP_SOURCE_MEMBERSHIP` or `MCAST_LEAVE_SOURCE_GROUP` (if IPv6) value.

**Parameters**

- `grp:net.addrinfo`: multicast group address.
- `src:net.addrinfo`: multicast source address.
- `ifname:string`: interface name.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## ok, err = sock:mcastblocksrc( grp, src [, ifname] )

set the `IP_BLOCK_SOURCE` or `MCAST_BLOCK_SOURCE` (if IPv6) value.

**Parameters**

- `grp:net.addrinfo`: multicast group address.
- `src:net.addrinfo`: multicast source address.
- `ifname:string`: interface name.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## ok, err = sock:mcastunblocksrc( grp, src [, ifname] )

set the `IP_UNBLOCK_SOURCE` or `MCAST_UNBLOCK_SOURCE` (if IPv6) value.

**Parameters**

- `grp:net.addrinfo`: multicast group address.
- `src:net.addrinfo`: multicast source address.
- `ifname:string`: interface name.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## enabled, err = sock:broadcast( [enable] )

determine whether the `SO_BROADCAST` flag enabled, or change the state to an argument value.

**Parameters**

- `enable:boolean`: to enable or disable the `SO_BROADCAST` flag.

**Returns**

- `enabled:boolean`: state of the `SO_BROADCAST` flag.
- `err:error`: error object.


## str, err, timeout, ai = sock:recvfrom( [flag, ...] )

receive message and address info from a socket.

**Parameters**

- `flag, ...:string`: symbolic `MSG_*` names such as `peek` or `dontwait`.

**Returns**

- `str:string`: received message string.
- `err:error`: error object.
- `timeout:boolean`: true if operation has timed out.
- `ai:addrinfo`: instance of [net.addrinfo](addrinfo.md).

**NOTE:** all return values will be nil if closed by peer.


## str, err, timeout, ai = sock:recvfromsync( [flag, ...] )

synchronous version of recvfrom method that uses advisory lock.


## len, err, timeout = sock:sendto( str, ai [, flag, ...] )

send a message to specified destination address.

**Parameters**

- `str:string`: message string.
- `ai:addrinfo`: instance of [net.addrinfo](addrinfo.md).
- `flag, ...:string`: symbolic `MSG_*` names such as `dontwait` or
  `nosignal`.

**Returns**

- `len:integer`: the number of bytes sent.
- `err:error`: error object.
- `timeout:boolean`: true if len not equal to #str or operation has timed out.

**NOTE:** all return values will be nil if closed by peer.


## len, err, timeout = sock:sendtosync( str, ai )

synchronous version of sendto method that uses advisory lock.

