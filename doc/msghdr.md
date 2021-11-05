
# net.MsgHdr

defined in [net.msghdr](../lib/msghdr.lua) module.


## mh = msghdr.new()

create an instance of `net.MsgHdr`.

**Returns**

- `mh:net.MsgHdr`: instance of net.MsgHdr.

**e.g.**

```lua
local msghdr = require('net.msghdr')
local mh = msghdr.new()
```


## ai = mh:name( [ai] )

get the address-info, or change it to specified address-info. if argument is a nil, the associated address-info will be removed.

**Parameters**

- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

**Returns**

- `ai:llsocket.addrinfo`: previous instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


## cmhs = mh:control()

get the cmsghdrs.

**Returns**

- `cmsgs:llsocket.cmsghdrs`: instance of [llsocket.cmsghdrs](https://github.com/mah0x211/lua-llsocket#llsocketcmsghdrs-instance-methods).


## bytes = mh:bytes()

get a number of bytes used.

**Returns**

- `bytes:integer`: number of bytes used.


## bytes = mh:consume( bytes )

delete the specified number of bytes of data.

**Parameters**

- `bytes:integer`: number of bytes delete.

**Returns**

- `bytes:integer`: number of bytes used.


## str, err = mh:concat()

concatenate all data of elements in use into a string.

**Returns**

- `str:string`: string.
- `err:string`: error string.


## idx, err = mh:add( str )

add an element with specified string.

**Parameters**

- `str:string`: string.

**Returns**

- `idx:integer`: positive index number of added element. or the following negative index number;
  - `-1`: no buffer space available
  - `-2`: stack memory cannot be increased
  - `-3`: empty string cannot be added
- `err:string`: error string.


## idx, err = mh:addn( bytes )

add an element that size of specified number of bytes.

**Parameters**

- `bytes:integer`: number of bytes.

**Returns**

- `idx:integer`: positive index number of added element. or the following negative index number;
  - `-1`: no buffer space available
  - `-2`: stack memory cannot be increased
  - `-3`: empty string cannot be added
- `err:string`: error string.


## str = mh:get( idx )

get a string of element at specified index.

**Parameters**

- `idx:integer`: index of element.

**Returns**

- `str:string`: string of element.


## str = mh:del( idx )

delete an element at specified index.

**Parameters**

- `idx:integer`: index of element.

**Returns**

- `str:string`: string of deleted element.


