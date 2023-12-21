# net.stream.unix.Server

defined in [net.stream.unix](../lib/stream/unix.lua) module and inherits from the [net.stream.Server](net_stream_server.md) class.


## sock, err, ai = unix.server.new( pathname [, tlscfg] )

create an instance of `net.stream.unix.Server`.  
if the `tlscfg` option is specified, it returns [net.tls.stream.unix.Server](net_tls_stream_unix_server.md) for TLS communication.

**Parameters**

- `pathname:string`: pathname of unix domain socket.
- `tlscfg:table?`: table that contains the following fields;
    - `cert:string`: certificate file path.
    - `key:string`: private key file path.
    - `protocol:string?`: protocol version that is one of the following strings (default is `default`);
        - `default`: default protocol version. (`TLSv1.2` and `TLSv1.3`)
        - `tlsv1`: TLS version 1.0, 1.1, 1.2 and 1.3
        - `tlsv1.0`: TLS version 1.0
        - `tlsv1.1`: TLS version 1.1
        - `tlsv1.2`: TLS version 1.2
        - `tlsv1.3`: TLS version 1.3
    - `ciphers:string?`: cipher list that is one of the following strings (default is `default`);
        - `default`: default cipher list. (`HIGH:aNULL`)
        - `secure`: secure cipher list. (same as default)
        - `legacy`: legacy cipher list. (`HIGH:MEDIUM:!aNULL`)
        - `all`: all cipher list. (`ALL:!aNULL:!eNULL`)
    - `session_cache_timeout:integer?`: session cache timeout seconds. (default is `0` that cache is disabled)
    - `session_cache_size:integer?`: session cache size. (default is `SSL_SESSION_CACHE_MAX_SIZE_DEFAULT`)
    
**Returns**

- `sock`: instance of `net.stream.unix.Server` or `net.tls.stream.unix.Server`.
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


**e.g.**

```lua
local unix = require('net.stream.unix')
local sock, err, ai = unix.server.new('/tmp/example.sock')
```

```lua
local unix = require('net.stream.unix')
local sock, err, ai = unix.server.new('/tmp/example.sock', {
    cert = './cert.pem',
    key = './cert.key',
})
```

