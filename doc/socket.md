# net.socket

defined in the native [net.socket](../src/socket.c) module.  Each
constructor returns a `net.socket` userdata. It is the low-level handle
wrapped by [net.Socket](net_socket.md), not an instance of that Lua class.
Its I/O methods return temporary retry indications (`again`) without the
deadline and polling loops provided by the higher-level classes.

Every opts table below is validated by a shared `optspec_check` helper
that silently ignores unknown string keys, so the same opts table can be reused
across layers (for example the addrinfo resolver + the setsockopt pass
that `bind_inet` runs internally).

The `send`-family methods use `MSG_NOSIGNAL` where available so a
peer-closed stream returns an `EPIPE` error object instead of delivering
`SIGPIPE`. Where `SO_NOSIGPIPE` is available (including macOS), that
socket option is applied at construction or adoption time. Linux native
`sendfile` has no flags argument and does not suppress `SIGPIPE`; the
Lua-class `writev` path also lacks per-call suppression. Where neither
mechanism protects a path, the host must handle `SIGPIPE` itself.


## sock, err = socket.wrap( fd )

wrap an existing socket file descriptor into a `net.socket` userdata.
`FD_CLOEXEC`, `O_NONBLOCK` and `SO_NOSIGPIPE` (where available) are set
on the descriptor as a side effect.

**Parameters**

- `fd:integer`: socket file descriptor to adopt.

**Returns**

- `sock:socket`: `net.socket` userdata.
- `err:error`: error object.


## sock, err = socket.new_inet( opts )

create a raw `AF_INET` socket with `socket(AF_INET, opts.socktype,
opts.protocol)`.  The socket is created with `FD_CLOEXEC` and
`O_NONBLOCK`, and any setsockopt keys in `opts` are applied before
`socket.new_inet` returns.  No `getaddrinfo` / `bind` / `connect` is
performed; the caller drives `sock:bind(ai)` / `sock:connect(ai)`
afterwards.

**Parameters**

- `opts:table`: creation options.
  - `socktype:string`: **required** — one of `stream` / `dgram` /
    `seqpacket`.
  - `protocol:string`: `auto` (default), `tcp`, or `udp`.
  - the following setsockopt keys are also applied at creation:
    `broadcast`, `debug`, `dontroute`, `keepalive`, `linger`, `mcastif`,
    `mcastloop`, `mcastttl`, `oobinline`, `rcvbuf`, `rcvlowat`,
    `rcvtimeo`, `reuseaddr`, `reuseport`, `sndbuf`, `sndlowat`,
    `sndtimeo`, `tcpkeepalive`, `tcpkeepcnt`, `tcpkeepintvl`, `tcpcork`,
    `tcpnodelay`, `timestamp`.

**Returns**

- `sock:socket`: `net.socket` userdata.
- `err:error`: error object.


## sock, err = socket.new_inet6( opts )

`AF_INET6` counterpart of `socket.new_inet`.  It accepts the same
setsockopt keys **except `broadcast`**, which is only accepted by
`socket.new_inet`.


## sock, err = socket.new_unix( opts )

create a raw `AF_UNIX` socket.

**Parameters**

- `opts:table`: creation options.
  - `socktype:string`: **required** — one of `stream` / `dgram` /
    `seqpacket`.
  - `protocol:string`: `auto` (default).
  - setsockopt keys accepted by `bind_unix` are also honoured.

**Returns**

- `sock:socket`: `net.socket` userdata.
- `err:error`: error object.


## sock, err = socket.bind_inet( host, port [, opts] )
## sock, err = socket.bind_inet( ai [, opts] )

resolve `(host, port)` via `net.addrinfo.getaddrinfo` (or use the
supplied `ai` userdata directly), iterate the resulting addrinfo list,
create the socket, apply `opts`, and `bind(2)` it.  The first
address that succeeds is returned.

**Parameters**

- `host:string`: numeric address or hostname.
- `port:string|integer`: numeric port, service name, or `nil`.
- `ai:addrinfo`: pre-built [net.addrinfo](addrinfo.md) userdata.
- `opts:table`: options — the following setsockopt keys are applied to
  the bound socket: `broadcast`, `debug`, `dontroute`, `mcastif`,
  `mcastloop`, `mcastttl`, `rcvbuf`, `rcvlowat`, `rcvtimeo`, `reuseaddr`,
  `reuseport`, `sndbuf`, `sndlowat`, `sndtimeo`, `timestamp`.
  addrinfo-side keys (`family`, `socktype`, `protocol`, `passive`, `flags`,
  `canonname`) are forwarded to the resolver.

**Returns**

- `sock:socket`: bound `net.socket` userdata.
- `err:error`: error object.


## sock, err = socket.bind_unix( pathname [, opts] )
## sock, err = socket.bind_unix( ai [, opts] )

`AF_UNIX` counterpart of `bind_inet`.

**Parameters**

- `pathname:string`: filesystem path to bind.
- `ai:addrinfo`: pre-built [net.addrinfo](addrinfo.md) userdata.
- `opts:table`: recognised keys include `debug`, `rcvbuf`, `sndbuf`,
  `rcvtimeo`, `sndtimeo`, ...  addrinfo-side keys (`socktype`,
  `protocol`) are forwarded.

**Returns**

- `sock:socket`: bound `net.socket` userdata.
- `err:error`: error object.


## sock, err, again = socket.connect_inet( host, port [, opts] )
## sock, err, again = socket.connect_inet( ai [, opts] )

resolve `(host, port)` (or use the supplied `ai` userdata), create the
socket, apply `opts`, and `connect(2)` it.  Because the socket is
non-blocking, `connect(2)` typically returns `EINPROGRESS` on inet
sockets; in that case the returned `sock` is not yet connected and
`again` is `true`.  The caller then waits for writability and inspects
`sock:error()` (see [connect_inet_stream in
lib/stream/inet.lua](../lib/stream/inet.lua) for a canonical wait
loop).

**Parameters**

- `host:string`: numeric address or hostname.
- `port:string|integer`: numeric port, service name, or `nil`.
- `ai:addrinfo`: pre-built [net.addrinfo](addrinfo.md) userdata.
- `opts:table`: options — the following setsockopt keys are applied to
  the connected socket: `debug`, `dontroute`, `keepalive`, `linger`,
  `oobinline`, `rcvbuf`, `rcvlowat`, `rcvtimeo`, `sndbuf`, `sndlowat`,
  `sndtimeo`, `tcpkeepalive`, `tcpkeepcnt`, `tcpkeepintvl`, `tcpcork`,
  `tcpnodelay`.  addrinfo-side keys (`family`, `socktype`, `protocol`, `passive`,
  `flags`, `canonname`) are forwarded to the resolver.

**Returns**

- `sock:socket`: `net.socket` userdata (may still be connecting).
- `err:error`: error object.
- `again:boolean`: `true` when the connect is in progress
  (`EINPROGRESS`).


## sock, err, again = socket.connect_unix( pathname [, opts] )
## sock, err, again = socket.connect_unix( ai [, opts] )

`AF_UNIX` counterpart of `connect_inet`.  On a well-formed unix socket
`connect(2)` returns synchronously so `again` is typically nil.


## socks, err = socket.pair( opts )

create a pair of connected `AF_UNIX` sockets via `socketpair(2)`.  Both
descriptors are returned with `FD_CLOEXEC` and `O_NONBLOCK` set.

**Parameters**

- `opts:table`:
  - `socktype:string`: **required** — `stream` / `dgram` / `seqpacket`.
  - `protocol:string`: `auto` (default).

**Returns**

- `socks:table`: two-element array of `net.socket` userdata.
- `err:error`: error object.


## ok, err = socket.close( fd [, how] )

close a raw socket file descriptor, optionally shutting it down first.

**Parameters**

- `fd:integer`: socket file descriptor.
- `how:string`: optional shutdown mode — `rd`, `wr`, or `rdwr`.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## ok, err = socket.shutdown( fd, how )

shut down part of a full-duplex connection.

**Parameters**

- `fd:integer`: socket file descriptor.
- `how:string`: `rd`, `wr`, or `rdwr`.

**Returns**

- `ok:boolean`: `true` on success.
- `err:error`: error object.


## Native-only handle methods

The following methods belong to `net.socket` userdata, not `net.Socket`.
For a Lua-class socket, its native handle is `sock.sock`.

| Method | Contract |
| --- | --- |
| `copy, err = sock:dup()` | Duplicates the descriptor into a new native userdata with `FD_CLOEXEC` set. Closing one handle does not close the other. |
| `fd = sock:unwrap()` | Runs registered cleanup callbacks and removes the userdata's metatable without closing the descriptor. The caller takes ownership of the returned fd; a previously closed socket returns `-1`. |
| `handle, err = sock:addgcfn(errfn, fn, ...)` | Registers `fn(...)` for close/GC and returns an opaque string handle. `errfn` is a Lua error handler or `nil`. Callbacks run in reverse registration order. A closed socket returns `nil, err` with `EBADF`. |
| `removed = sock:delgcfn(handle)` | Removes the registered callback identified by `handle`; returns `false` if it is no longer registered. |
| `ok, err, timeout = sock:recvable([sec [, except]])` | Polls read readiness; `sec` defaults to `0` (immediate check). `except = true` also checks out-of-band readiness. |
| `ok, err, timeout = sock:sendable([sec [, except]])` | Polls write readiness with the same timeout and exception arguments. |

The readiness methods return `true` for readiness (including hangup/error
conditions), `false, nil, true` on timeout, or `false, err` on failure.
The subsequent I/O call reports the actual I/O error or EOF.

GC-callback errors do not escape from close/GC. Diagnostic builds
(`NET_COVERAGE` or builds without `NDEBUG`) report them to stderr via
`NET_GCTHREAD_OUTPUT_STDERR`; release builds discard them silently.
