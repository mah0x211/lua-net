# Constants of net.tls

[net.tls](../lib/tls.lua) module exports the following constants that defined in the [libtls](https://github.com/mah0x211/lua-libtls/blob/master/doc/constants.md) module.

## Required file descriptor states

- `WANT_POLLIN`: The underlying read file descriptor needs to be readable in order to continue.
- `WANT_POLLOUT`: The underlying write file descriptor needs to be writeable in order to continue.


## Protocol Versions

- `TLS_v10`: TLS version 1.0
- `TLS_v11`: TLS version 1.1
- `TLS_v12`: TLS version 1.2
- `TLS_v1x`: TLS version 1.0, 1.1, 1.2 and 1.3
- `TLS_DEFAULT`: TLS version 1.2 and 1.3

## OCSP certificate status code

- `OCSP_CERT_GOOD`
- `OCSP_CERT_REVOKED`
- `OCSP_CERT_UNKNOWN`


## OCSP response status code

- `OCSP_RESPONSE_SUCCESSFUL`
- `OCSP_RESPONSE_MALFORMED`
- `OCSP_RESPONSE_INTERNALERROR`
- `OCSP_RESPONSE_TRYLATER`
- `OCSP_RESPONSE_SIGREQUIRED`
- `OCSP_RESPONSE_UNAUTHORIZED`


## CTL reason status code

- `CRL_REASON_UNSPECIFIED`
- `CRL_REASON_KEY_COMPROMISE`
- `CRL_REASON_CA_COMPROMISE`
- `CRL_REASON_AFFILIATION_CHANGED`
- `CRL_REASON_SUPERSEDED`
- `CRL_REASON_CESSATION_OF_OPERATION`
- `CRL_REASON_CERTIFICATE_HOLD`
- `CRL_REASON_REMOVE_FROM_CRL`
- `CRL_REASON_PRIVILEGE_WITHDRAWN`
- `CRL_REASON_AA_COMPROMISE`

## misc

- `TLS_API`
- `MAX_SESSION_ID_LENGTH`
- `TICKET_KEY_SIZE`
