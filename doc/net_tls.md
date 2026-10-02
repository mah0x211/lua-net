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

## Negotiation results

The following methods on a connection context report the negotiated TLS
parameters.  They return `(nil, EINVAL error)` once the context has been
disposed with `close()`.

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
