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

## Stateless session tickets

Servers support TLS 1.2 RFC5077 tickets and TLS 1.3 PSK tickets using
OpenSSL's stateless implementation. Session ID resumption and server-side
session caches are not used. `session_timeout` defaults to 300 seconds;
zero or negative values disable ticket issuance in both versions.

Ticket keys and lifetime settings belong to the accepting server's `SSL_CTX`.
Reusing that context, including through `net.tls.cache`, preserves its ticket
keys. A new independent context cannot resume its tickets. Servers do not
store sessions in `net.tls.cache`.

The Lua `sni_callback` selects a server before OpenSSL decides whether to
resume a session. Its certificate-verification policy and context-specific
resumption scope apply before that decision, so a ticket from a different
context cannot bypass the selected server's client-certificate requirements.
Returning `nil` keeps the default server; raising an error aborts the handshake.
Selection runs once per connection and is retained across TLS 1.3
HelloRetryRequest; the Lua callback is not invoked again for the retried hello.
SNI acceptance is acknowledged internally, including on default fallback;
users do not need to provide another callback.
