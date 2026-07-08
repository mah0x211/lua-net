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

When `context.accept()` / `context.connect()` are called with `use_bio=true`,
an optional trailing `bufcap` can be supplied. If omitted, or smaller than
`context.encrypted_length(protocol)`, the minimum safe size is used.
