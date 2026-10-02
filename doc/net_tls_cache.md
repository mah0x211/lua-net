# net.tls.cache

defined in the [net.tls.cache](../src/tls_cache.c) module.

The module returns its constructor function directly. A cache is opaque: its
keys, `SSL_CTX` values, and future `SSL_SESSION` values are not exposed to Lua.

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
  sessions per `SSL_CTX`. The current cache-foundation release does not yet
  attach client sessions, so `nsessions` remains zero. Existing session-cache
  options retain their behavior on clients. Servers use stateless tickets
  and do not cache sessions.
  (default is `0`)

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
