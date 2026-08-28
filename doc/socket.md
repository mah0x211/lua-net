# net.socket

defined in the native [net.socket](../src/socket.c) module.  Each
constructor returns a `net.socket` userdata that speaks the same method
set as [net.Socket](net_socket.md).

Every opts table below is validated by a shared `check_options` helper
that silently ignores unknown keys, so the same opts table can be reused
across layers (for example the addrinfo resolver + the setsockopt pass
that `bind_inet` runs internally).

Every socket created or adopted by this module suppresses `SIGPIPE` on
its own: writes to a peer-closed stream socket raise the `EPIPE` error
object instead of killing the process, regardless of the host
application's signal disposition.  On Linux this is done with the
per-call `MSG_NOSIGNAL` flag; on macOS/BSD the `SO_NOSIGPIPE` socket
option is applied at construction time.  Platforms providing neither
mechanism (e.g. OpenBSD) cannot suppress the signal in-process; hosts
there must ignore `SIGPIPE` themselves.


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
  addrinfo-side keys (`socktype`, `protocol`, `passive`, `flags`,
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
  `tcpnodelay`.  addrinfo-side keys (`socktype`, `protocol`, `passive`,
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
