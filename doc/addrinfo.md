# net.addrinfo

defined in the native [net.addrinfo](../src/addrinfo.c) module.  Each
constructor returns a `net.addrinfo` userdata that wraps `struct
addrinfo` (family + socktype + protocol + sockaddr) and can be passed
to `sock:bind(ai)` / `sock:connect(ai)` or supplied directly to
`net.socket.bind_inet(ai, opts)` / `net.socket.connect_inet(ai, opts)`
in place of `(host, port)`.

Every opts table below is validated by the same `check_options`
helper that `net.socket` uses, so unknown keys are silently ignored
and callers can reuse a single opts table across the addrinfo and
socket layers.

Recognised opts keys:

| key         | value                                                                                                        |
| ----------- | ------------------------------------------------------------------------------------------------------------ |
| `family`    | `inet` / `inet6` / `unix` (only `getaddrinfo` accepts it — the family-specific constructors set it).         |
| `socktype`  | `stream` / `dgram` / `seqpacket`.                                                                            |
| `protocol`  | `auto` (default) / `tcp` / `udp`.                                                                            |
| `passive`   | `true` sets `AI_PASSIVE` (server-side).                                                                      |
| `canonname` | `true` sets `AI_CANONNAME`.                                                                                  |
| `flags`     | array of AI_* flag names (`passive`, `canonname`, `numerichost`, `numericserv`, `addrconfig`, `v4mapped`). |


## ai, err = addrinfo.inet( host, port [, opts] )

build an `AF_INET` addrinfo from a numeric IPv4 address and port.  No
DNS lookup is performed; `host` must be a dotted-quad string.

**Parameters**

- `host:string`: numeric IPv4 address (e.g. `127.0.0.1`).  `nil` /
  omitted binds to the wildcard address.
- `port:string|integer`: numeric port, service name, or `nil`.
- `opts:table`: opts as described above.

**Returns**

- `ai:addrinfo`: `net.addrinfo` userdata.
- `err:error`: error object.


## ai, err = addrinfo.inet6( host, port [, opts] )

`AF_INET6` counterpart of `addrinfo.inet`.  `host` must be a numeric
IPv6 address string (e.g. `::1`).


## ai, err = addrinfo.unix( pathname [, opts] )

build an `AF_UNIX` addrinfo from a filesystem path.  The path must be
shorter than `sizeof(sockaddr_un.sun_path)`; longer paths surface
`ENAMETOOLONG`.

**Parameters**

- `pathname:string`: filesystem path.
- `opts:table`: opts as described above (only `socktype` / `protocol`
  / `passive` are meaningful for unix sockets).


## ais, err = addrinfo.getaddrinfo( host, port [, opts] )

resolve `(host, port)` via `getaddrinfo(3)` and return every result.
Unlike `addrinfo.inet` / `addrinfo.inet6`, `host` may be either a
numeric address or a hostname that DNS resolves.

**Parameters**

- `host:string`: hostname or numeric address (`nil` binds to the
  wildcard when `opts.passive == true`).
- `port:string|integer`: numeric port, service name, or `nil`.
- `opts:table`: opts as described above.  `family` (`inet` / `inet6` /
  `unix`) restricts the returned list to a single family; omit to let
  the resolver pick.

**Returns**

- `ais:addrinfo[]`: array of `net.addrinfo` userdata.
- `err:error`: error object.


## ai userdata instance methods

Each `net.addrinfo` userdata exposes read-only accessors:

- `ai:family()` — `inet` / `inet6` / `unix` / `unspec`.
- `ai:socktype()` — `stream` / `dgram` / `seqpacket` / `unspec`.
- `ai:protocol()` — `tcp` / `udp` / `auto`.
- `ai:addr()` — string form of the sockaddr (dotted-quad address or
  unix pathname).
- `ai:port()` — integer port (inet / inet6 only).
- `ai:canonname()` — canonical hostname when the addrinfo was resolved
  with `canonname = true`; nil otherwise.
- `ai:getnameinfo([flag, ...])` — reverse resolution via
  `getnameinfo(3)`; returns `(host, service, err)`.
- `tostring(ai)` — `"net.addrinfo: 0x...."`.
