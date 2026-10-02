# net.tls.cache

defined in the [net.tls.cache](../src/tls_cache.c) module.

The module returns its constructor function directly. A cache is opaque: its
keys, `SSL_CTX` values, and `SSL_SESSION` values are not exposed to Lua.

## cache = new_cache( [opts] )

```lua
local new_cache = require('net.tls.cache')

local cache = new_cache({
    ctx_capacity = 64,
    session_capacity = 64,
})
```

**Options**

- `ctx_capacity:integer?`: maximum number of strongly cached `SSL_CTX`
  userdata across clients and servers. (default is `0`)
- `session_capacity:integer?`: maximum number of strongly cached client
  sessions per `SSL_CTX`. A positive value enables client session caching;
  each entry expires according to the lifetime in its `SSL_SESSION`.
  (default is `0`)

Client sessions are scoped to their cached `SSL_CTX` and destination. TLS 1.2
RFC 5077 tickets and TLS 1.3 PSK tickets are supported. A session is removed
from the cache when selected for a connection and replaced by the ticket from
the resulting handshake; session-ID resumption and 0-RTT are not supported.

Servers use stateless tickets and do not cache sessions.

When a strong store reaches its capacity, an arbitrary entry is moved to a
weak-value store. It can be promoted again while another object still owns it;
otherwise Lua garbage collection releases it. The policy is bounded but is not
LRU.

## nctx, nsessions = cache:size()

Returns the number of strong context entries and the total number of strong
session entries. Weak entries are not included.

## ok = cache:clear()

Invalidates all context mappings and session mappings currently reachable from
the cache. Existing clients, servers, and connections continue owning their
resources until they are released.

Certificate, key, CA-directory, or CA-file contents are not monitored. Call
`cache:clear()` after changing a file referenced by cached TLS options.
