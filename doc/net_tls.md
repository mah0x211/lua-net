# Constants and helpers of net.tls.context

[net.tls.context](../src/tls_context.c) module exports the following constants
and helper.

## Required file descriptor states

- `WANT_READ`: The underlying read file descriptor needs to be readable in order to continue.
- `WANT_WRITE`: The underlying write file descriptor needs to be writeable in order to continue.

## encrypted_length = context.encrypted_length( protocol )

Returns the maximum on-the-wire TLS record length for the given protocol
policy.

- `protocol`: one of `default`, `tlsv1`, `tlsv1.0`, `tlsv1.1`, `tlsv1.2`,
  `tlsv1.3`.
- The returned value is used as the minimum safe BIO buffer size when the
  memory-BIO transport is enabled.

## Memory BIO buffer size

`context.accept(server, fd, opts)` and `context.connect(client, fd, opts)`
accept an optional options table. Both support `opts.bufcap`; if omitted or
smaller than `context.encrypted_length(protocol)`, the minimum safe size is
used. A `bufcap` that cannot be allocated is reported as an error.

For `connect`, the options table also supports `host`, `port`, `servername`,
`verify_name`, `verify_time`, and `verify_cert`. `host` is a string and `port`
is a string or an integer in the range 0-65535. They identify the destination
for client session caching; omitting either disables session caching for that
connection. The three verification options default to `true`; `servername`,
`host`, and `port` default to `nil`. As with other options tables, keys must be
strings and unknown string keys are ignored.

`verify_name = true` requires certificate verification and a non-empty
`servername`. To disable certificate verification, also set
`verify_name = false`; in that case `servername` may be omitted.

## TLS compatibility notes

- If a server has ALPN configured and the client's ALPN list has no common
  protocol, the handshake fails with a fatal alert instead of continuing
  without ALPN. A client that does not offer ALPN is not rejected for that
  reason alone.
- TLS renegotiation is disabled on both client and server contexts with
  `SSL_OP_NO_RENEGOTIATION`. Peers that require renegotiation are not supported.
- The `secure` cipher policy uses forward-secret ECDHE with AEAD encryption
  for TLS 1.2 and below; it is not an alias for `default`. See the constructor
  options in [net.stream.inet.Client](net_stream_inet_client.md).

## Borrowed file descriptor and memory BIO

`context.connect` and `context.accept` borrow the supplied socket descriptor;
they neither duplicate nor close it, and do not keep the socket userdata alive.
The caller must keep the socket open and reachable until TLS I/O has finished.
Closing it or allowing it to be garbage-collected while the context is still
used can cause the saved descriptor number to refer to an unrelated new file
or socket. Dispose of the TLS context before closing the underlying socket.

### bio, err = ctx:get_bio()

Returns the memory-BIO userdata, including after a completed shutdown so the
last `close_notify` can be drained. Returns `nil, err` with `EINVAL` after
`ctx:close()`. Keeping this userdata alive does not extend the descriptor's
lifetime. On platforms without `MSG_NOSIGNAL`, a supplied socket must already
have `SO_NOSIGPIPE` enabled, or the host must handle `SIGPIPE` itself.

### n, err, again, eof = bio:fill()

Reads ciphertext from the borrowed descriptor into the receive ring.

| Result | Returned values |
| --- | --- |
| Data read; ring full, or EAGAIN after some data | `n` |
| EAGAIN before any data | `nil, nil, true` |
| EOF, with or without data read in this call | `n` or `nil`, followed by `nil, nil, true` |
| Fatal error or receive ring has no space | `nil, err` |

The EOF form has four values. If `n` is present, process those buffered bytes
before treating the connection as closed. EINTR is retried internally.

### n, err, again = bio:drain()

Writes buffered ciphertext to the borrowed socket. A fully drained ring returns
`n` (including `0` if empty). EAGAIN returns `n, nil, true`, preserving the count
already sent; a fatal error returns `nil, err`. EINTR is retried internally.

## Negotiation results

The following methods on a connection context report the negotiated TLS
parameters. They return `(nil, EINVAL error)` once the SSL object has been
released by a completed `shutdown()` or by `close()`.

### protocol = ctx:get_alpn()

Returns the selected ALPN protocol string, or no values if no protocol was
negotiated. Call it after the handshake completes.

### version = ctx:get_version()

Returns the negotiated protocol name (e.g. `TLSv1.3`).  The value is only
meaningful after the handshake completed; before that it depends on the
OpenSSL version.

### cipher = ctx:get_cipher()

Returns the name of the negotiated cipher suite (e.g.
`TLS_AES_256_GCM_SHA384`).  Returns nothing while the handshake has not
completed.

### pem = ctx:get_peer_cert()

Returns the PEM-encoded leaf certificate presented by the peer, or nothing
when the peer presented no certificate.  On the server side this is the
client certificate; on the client side it is the server certificate.

### ok, errstr = ctx:get_verify_result()

Returns `true` when the peer certificate chain verified successfully
(`X509_V_OK`), otherwise `nil` and the verification error message.

## Shutdown and close

The graceful TLS shutdown and the resource disposal are separate operations;
`ctx:shutdown()` performs the former and `ctx:close()` the latter.

### ok, err, want = ctx:shutdown()

Exchanges `close_notify` with the peer. Like the other non-blocking methods,
it returns `(false, nil, want)` while the transport has to become
readable/writable again, and `(false, err)` on a fatal error.

**shutdown completed**

- `true`: the bidirectional shutdown completed. The SSL object is released,
  but the BIO buffers remain available; the final `close_notify` ciphertext
  may still be buffered in the TX BIO, so drain it to the socket before
  `ctx:close()` disposes of the context.

**nothing to shut down**

- `true` is also returned before the handshake has completed, or on an
  already shut down / disposed context. Nothing is released in this case;
  `ctx:close()` disposes of the context.

### ok = ctx:close()

Unconditionally releases the SSL context and the BIO buffers without any
TLS exchange, and always returns `true`.
