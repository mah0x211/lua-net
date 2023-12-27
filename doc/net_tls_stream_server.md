# net.tls.stream.Server

defined in [net.tls.stream](../lib/tls/stream.lua) module and inherits from the [net.stream.Server](net_stream_server.md) and [net.tls.stream.Socket](net_tls_stream_socket.md) classes.


## sock:set_sni_callback( callback [, ...] )

set a callback function that is called when the client sends the SNI (Server Name Indication) extension.

if the `callback` is `nil`, the callback function is removed.

**Parameters**

- `callback:function`: callback function as the following signature;  
  ```
  function( ...:any, hostname:string ):net.tls.stream.Server
  Parameters:
    - ...: additional arguments.
    - hostname: hostname that is sent by the client as the SNI extension.
  Returns: 
    - net.tls.stream.Server object.
  ```
- `...:any`: additional arguments.
  

**Example**

```lua
local tls_server = require('net.tls.server')
local inet = require('net.stream.inet')
local s = assert(inet.server.new('127.0.0.1', 8443, {
    reuseaddr = true,
    reuseport = true,
    tlscfg = {
        cert = 'cert.pem',
        key = 'cert.key',
    }
}))

-- create server contexts for each hostname
local SERVER_CTX
    ['example.com'] = tls_server('example.com.crt', 'example.com.key'),
    ['example.net'] = tls_server('example.net.crt', 'example.net.key'),
    ['example.org'] = tls_server('example.org.crt', 'example.org.key'),
}
-- set the SNI callback
s:set_sni_callback(function(_, hostname)
    -- return a server context for the hostname
    return SNI_CTX[hostname]
end)
```
