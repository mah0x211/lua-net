# net.stream.unix.Client

defined in [net.stream.unix](../lib/stream/unix.lua) module and inherits from the [net.stream.unix.Socket](net_stream_unix_socket.md) class.


## sock, err, timeout, ai = unix.client.new( pathname [, opts] )

initiates a new connection and returns an instance of `net.stream.unix.Client`.  
if the `tlscfg` option is specified, it returns [net.tls.stream.unix.Client](net_tls_stream_unix_client.md) for TLS communication.

**Parameters**

- `pathname:string`: pathname of unix domain socket.
- `opts:table`
    - `deadline:number`: specify a timeout seconds.
    - `tlscfg:table?`: table that contains the following fields;
        - `protocol:string?`: protocol version that is one of the following strings (default is `default`);
            - `default`: default protocol version. (`TLSv1.2` and `TLSv1.3`)
            - `tlsv1`: TLS version 1.0, 1.1, 1.2 and 1.3
            - `tlsv1.0`: TLS version 1.0
            - `tlsv1.1`: TLS version 1.1
            - `tlsv1.2`: TLS version 1.2
            - `tlsv1.3`: TLS version 1.3
        - `ciphers:string?`: cipher list that is one of the following strings (default is `default`);
            - `default`: default cipher list. (`HIGH:!aNULL`)
            - `secure`: secure cipher list. (same as default)
            - `legacy`: legacy cipher list. (`HIGH:MEDIUM:!aNULL`)
            - `all`: all cipher list. (`ALL:!aNULL:!eNULL`)
            - TLS 1.3 ciphersuites are also restricted to `TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256` regardless of the above policies. (requires OpenSSL 1.1.1 or later)
        - `alpn:table?`: array of protocol name strings for ALPN (Application-Layer Protocol Negotiation). (default is `nil`)
        - `session_cache_timeout:integer?`: session cache timeout seconds. (default is `0` that cache is disabled)
        - `session_cache_size:integer?`: session cache size. (default is `SSL_SESSION_CACHE_MAX_SIZE_DEFAULT`)
        - `cafile:string?`: path to a PEM file containing trusted CA certificates used to verify the server certificate. loaded in addition to the default system verify paths. either `cafile` or `capath` must be specified. (default is `nil`)
        - `capath:string?`: path to a directory containing CA certificates in the hashed format produced by `openssl rehash`. loaded in addition to the default system verify paths. (default is `nil`)
        - `verify_depth:integer?`: maximum depth of the server certificate chain accepted during verification. (default is the OpenSSL default)
        - `noverify_name:boolean?`: disable verification of the subject name of the server certificate. (default is `false`)
        - `noverify_time:boolean?`: disable verification of the server certificate expiration time. (default is `false`)
        - `noverify_cert:boolean?`: disable verification of the server certificate. (default is `false`)
        - `use_bio:boolean?`: use the memory-BIO transport instead of a direct socket BIO. see [net.tls.context](net_tls.md). (default is `false`)
        - `bufcap:integer?`: capacity in bytes of the memory-BIO ring buffers used with `use_bio = true`. a value of `0` or below `net.tls.context.encrypted_length(protocol)` falls back to that minimum safe size. (default is `0`)

**Returns**

- `sock`: instance of `net.stream.unix.Client` or `net.tls.stream.unix.Client`.
- `err:error`: error object.
- `timeout:boolean`: `true` if operation has timed out.
- `ai:addrinfo`: instance of [net.addrinfo](addrinfo.md).

**e.g.**

```lua
local unix = require('net.stream.unix')
local sock, err, timeout, ai = unix.client.new('/tmp/example.sock')
```

```lua
local unix = require('net.stream.unix')
local sock, err, timeout, ai = unix.client.new('/tmp/example.sock', {
    tlscfg = {
        noverify_cert = true,
        noverify_name = true,
    },
})
```
