# net.tls.stream.Server

defined in [net.tls.stream](../lib/tls/stream.lua) module and inherits from the
[net.stream.Server](net_stream_server.md) and
[net.tls.stream.Socket](net_tls_stream_socket.md) classes.

## Immutable TLS configuration

The server's `SSL_CTX` is fully configured when the stream server is created.
It cannot be changed through `set_verify` or `set_sni_callback` methods.

Configure client-certificate verification and SNI in the constructor's
`tlscfg` table instead:

```lua
local new_tls_server = require('net.tls.server')
local inet = require('net.stream.inet')

local vhosts = {
    ['example.com'] = assert(new_tls_server({
        cert = 'example.com.crt',
        key = 'example.com.key',
    })),
}

local server = assert(inet.server.new('127.0.0.1', 8443, {
    tlscfg = {
        cert = 'default.crt',
        key = 'default.key',
        verify_mode = 'require',
        verify_depth = 3,
        cafile = 'mycompany-ca.pem',
        capath = '.',
        sni_callback = function(hostname)
            return vhosts[hostname]
        end,
    },
}))
```

See the `tlscfg` options documented by
[net.stream.inet.Server](net_stream_inet_server.md) and
[net.stream.unix.Server](net_stream_unix_server.md).
