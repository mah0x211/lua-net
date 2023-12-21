# net.stream.inet.Server

defined in [net.stream.inet](../lib/stream/inet.lua) module and inherits from the [net.stream.Server](net_stream_server.md) class.


## sock, err, ai = inet.server.new( host, port [, opts] )

create an instance of `net.stream.inet.Server`.  
if the `tlscfg` option is specified, it returns [net.tls.stream.inet.Server](net_tls_stream_inet_server.md) for TLS communication.


**Parameters**

- `host:string`: hostname.
- `port:string|integer`: either a decimal port number or a service name listed in services(5).
- `opts:table`
    - `reuseaddr:boolean`: enable the `SO_REUSEADDR` flag.
    - `reuseport:boolean`: enable the `SO_REUSEPORT` flag.
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

- `sock`: instance of `net.stream.inet.Server` or `net.tls.stream.inet.Server`.
- `err:error`: error object.
- `ai:llsocket.addrinfo`: instance of [llsocket.addrinfo](https://github.com/mah0x211/lua-llsocket#llsocketaddrinfo-instance-methods).


**e.g.**

```lua
local inet = require('net.stream.inet')
local sock, err = inet.server.new('127.0.0.1', 8080)
```

```lua
local inet = require('net.stream.inet')
local sock, err = inet.server.new('127.0.0.1', 8080, {
    tlscfg = {
        cert = './cert.pem',
        key = './cert.key',
    },
})
```

