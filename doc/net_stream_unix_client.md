# net.stream.unix.Client

defined in [net.stream.unix](../lib/stream/unix.lua) module and inherits from the [net.stream.unix.Socket](net_stream_unix_socket.md) class.


## sock, err, timeout, ai = unix.client.new( pathname [, opts] )

initiates a new connection and returns an instance of `net.stream.unix.Client`.  
if the `tlscfg` option is specified, it returns [net.tls.stream.unix.Client](net_tls_stream_unix_client.md) for TLS communication.

**Parameters**

- `pathname:string`: pathname of unix domain socket.
- `opts:table`
    - `deadline:uint`: specify a timeout milliseconds as unsigned integer.
    - `tlscfg:libtls.config`: [libtls.config](https://github.com/mah0x211/lua-libtls/blob/master/doc/config.md) object.

**Returns**

- `sock`: instance of `net.stream.unix.Client` or `net.tls.stream.unix.Client`.
- `err:string`: error string.
- `timeout:boolean`: `true` if operation has timed out.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).

**e.g.**

```lua
local unix = require('net.stream.unix')
local sock, err, timeout, ai = unix.client.new('/tmp/example.sock')
```

```lua
local unix = require('net.stream.unix')
local config = require('net.tls.config')
local cfg = config.new()
cfg:insecure_noverifycert()
cfg:insecure_noverifyname()
local sock, err, timeout, ai = unix.client.new('/tmp/example.sock', {
    tlscfg = cfg,
})
```
