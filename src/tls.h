/*
 *  Copyright (C) 2023 Masatoshi Fukunaga
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to
 *  deal in the Software without restriction, including without limitation the
 *  rights to use, copy, modify, merge, publish, distribute, sublicense,
 *  and/or sell copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *  DEALINGS IN THE SOFTWARE.
 *
 */

#ifndef net_tls_h
#define net_tls_h

// depend
#include "lauxhlib.h"
#include "lua_error.h"
// lua
#include <lua.h>
// system
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <stddef.h>

#include "tls_bio.h"

typedef struct {
    lua_State *L;
    SSL_CTX *ctx;
    int sni_callback_ref;
    int ref_alpn;
    unsigned char *alpn;
    size_t alpn_len;
} tls_server_t;

#define NET_TLS_SERVER_MT "net.tls.server"

typedef struct {
    lua_State *L;
    SSL_CTX *ctx;
    int error_cb_ref;
} tls_client_t;

#define NET_TLS_CLIENT_MT "net.tls.client"

// Convert a Lua array of protocol name strings at stack index idx into the
// ALPN wire-format list: [len1][name1][len2][name2]... on the stack.
// The function returns the number of protocols found and replaces the original
// table with the wire-format string on the stack.
// Returns >0 if the table contains valid protocols.
// Returns 0 if the table is nil, empty or contains no valid protocols.
// Returns -1 on error and leaves an error message on the stack. luaL_error on
// invalid input (non-string element, >255 bytes).
static inline int tls_check_alpn_table(lua_State *L, int idx)
{
    int n         = 0;
    int nproto    = 0;
    size_t wtotal = 0;

    // check if the table is nil or empty
    if (lua_isnoneornil(L, idx)) {
        return 0;
    }
    luaL_checktype(L, idx, LUA_TTABLE);
    n = lauxh_rawlen(L, idx);
    if (n <= 0) {
        return 0;
    }

    // confirm stack size can be increased by n elements
    if (!lua_checkstack(L, n)) {
        lua_pushliteral(L, "too many alpn protocols, not enough stack space");
        return -1;
    }

    // first pass: compute total wire length
    for (int i = 1; i <= n; i++) {
        char wire[256]    = {0};
        size_t plen       = 0;
        const char *proto = NULL;

        // get the protocol string at index i
        lua_rawgeti(L, idx, i);
        // ensure it's a string
        if (lua_type(L, -1) != LUA_TSTRING) {
            lua_pop(L, 1);
            lua_pushfstring(L, "alpn protocol #%d must be a string", i);
            return -1;
        }

        // get the length of the protocol string
        proto = lua_tolstring(L, -1, &plen);
        if (plen > 255) {
            lua_pop(L, 1);
            lua_pushfstring(L, "alpn protocol #%d exceeds 255 bytes", i);
            return -1;
        } else if (plen == 0) {
            // ignore empty protocol strings
            lua_pop(L, 1);
            continue;
        }

        // RFC 7301 encodes the ProtocolNameList with a 2-byte length, so
        // the wire format must not exceed 65535 bytes in total.  This also
        // keeps the size_t-to-unsigned int cast at the
        // SSL_CTX_set_alpn_protos() call sites free of truncation.
        wtotal += plen + 1;
        if (wtotal > 0xffff) {
            lua_pop(L, 1);
            lua_pushfstring(
                L, "total length of alpn protocols exceeds 65535 bytes");
            return -1;
        }

        // alpn wire format: [len][name]
        wire[0] = (char)plen;
        memcpy(wire + 1, proto, plen);
        lua_pop(L, 1);
        lua_pushlstring(L, wire, plen + 1);

        nproto++;
        // keep the protocol length and name on the stack for building the wire
        // format later
    }

    // no valid protocols found
    if (nproto == 0) {
        return 0;
    }

    // concat the protocol lengths and names into the wire format, and replace
    // the original table with the wire-format string on the stack
    lua_concat(L, nproto);
    lua_replace(L, idx);
    return nproto;
}

typedef int (*tls_handshake_fn)(SSL *);

typedef struct {
    SSL *ssl;
    tls_bio_t *bio;
    tls_handshake_fn handshake_cb;
    int parent_ref;
} tls_ctx_t;

#define NET_TLS_CONTEXT_MT "net.tls.context"

static inline void tls_init(lua_State *L)
{
#if OPENSSL_VERSION_NUMBER < 0x10100000L
    SSL_library_init();
    SSL_load_error_strings();
    OpenSSL_add_all_algorithms();
#else
    OPENSSL_init_ssl(
        OPENSSL_INIT_LOAD_SSL_STRINGS | OPENSSL_INIT_LOAD_CRYPTO_STRINGS, NULL);
#endif

    // initilize dependent modules
    lua_error_loadlib(L, 1);
}

// NOTE: the cleanup process should not be performed if the OpenSSL library
// has been initialized outside of this module, as it may not work properly.
// static inline void cleanup_openssl(void)
// {
// #if OPENSSL_VERSION_NUMBER < 0x10100000L
//     EVP_cleanup();
// #else
//     OPENSSL_cleanup();
// #endif
// }

typedef enum {
    NET_TLS_CIPHER_SUITE_DEFAULT = 0,
    NET_TLS_CIPHER_SUITE_SECURE,
    NET_TLS_CIPHER_SUITE_LEGACY,
    NET_TLS_CIPHER_SUITE_ALL,
} tls_cipher_suite_t;

static const char *const TLS_CIPHER_SUITES[] = {
    "default", // HIGH:!aNULL
    "secure",  // same as default
    "legacy",  // HIGH:MEDIUM:!aNULL
    "all",     // ALL:!aNULL:!eNULL
    NULL,
};

static inline int tls_set_cipher_suite(SSL_CTX *ctx, tls_cipher_suite_t suite)
{
    const char *ciphers = NULL;

    switch (suite) {
    default:
    case NET_TLS_CIPHER_SUITE_DEFAULT:
    case NET_TLS_CIPHER_SUITE_SECURE:
        ciphers = "HIGH:!aNULL";
        break;

    case NET_TLS_CIPHER_SUITE_LEGACY:
        ciphers = "HIGH:MEDIUM:!aNULL";
        break;

    case NET_TLS_CIPHER_SUITE_ALL:
        ciphers = "ALL:!aNULL:!eNULL";
        break;
    }

    if (SSL_CTX_set_cipher_list(ctx, ciphers) != 1) {
        return 0;
    }

#if OPENSSL_VERSION_NUMBER >= 0x10101000L
    // TLS 1.3 ciphersuites are configured separately from the cipher list
    // for TLS 1.2 and below; set them explicitly so that the cipher policy
    // does not depend on the OpenSSL defaults. All TLS 1.3 ciphersuites are
    // AEAD with equivalent strength, so every policy shares this list.
    return SSL_CTX_set_ciphersuites(
        ctx,
        "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:"
        "TLS_AES_128_GCM_SHA256");
#else
    return 1;
#endif
}

typedef enum {
    NET_TLS_PROTO_DEFAULT = 0,
    NET_TLS_PROTO_TLSv1,
    NET_TLS_PROTO_TLSv1_0,
    NET_TLS_PROTO_TLSv1_1,
    NET_TLS_PROTO_TLSv1_2,
    NET_TLS_PROTO_TLSv1_3,
} tls_protocol_t;

static const char *const TLS_PROTOCOLS[] = {
    "default", // TLSv1.2 and TLSv1.3
    "tlsv1",   // TLSv1.0, TLSv1.1, TLSv1.2 and TLSv1.3
    "tlsv1.0", // TLSv1.0
    "tlsv1.1", // TLSv1.1
    "tlsv1.2", // TLSv1.2
    "tlsv1.3", // TLSv1.3
    NULL,
};

static inline void tls_get_protocol_vers(tls_protocol_t protocol, int *minv,
                                         int *maxv)
{
    int min_version = 0;
    int max_version = 0;

    switch (protocol) {
    default:
    case NET_TLS_PROTO_DEFAULT:
        min_version = TLS1_2_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1:
        min_version = TLS1_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1_0:
        min_version = TLS1_VERSION;
        max_version = TLS1_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1_1:
        min_version = TLS1_1_VERSION;
        max_version = TLS1_1_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1_2:
        min_version = TLS1_2_VERSION;
        max_version = TLS1_2_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1_3:
        min_version = TLS1_3_VERSION;
        max_version = TLS1_3_VERSION;
        break;
    }

    if (minv) {
        *minv = min_version;
    }
    if (maxv) {
        *maxv = max_version;
    }
}

static inline int tls_set_protocol_vers(SSL_CTX *ctx, tls_protocol_t protocol)
{
    int minv = 0;
    int maxv = 0;

    tls_get_protocol_vers(protocol, &minv, &maxv);

    return SSL_CTX_set_min_proto_version(ctx, minv) == 1 &&
           (maxv <= 0 || SSL_CTX_set_max_proto_version(ctx, maxv) == 1);
}

#define TLS_RECORD_HEADER_LENGTH  5
#define TLS_MAX_PLAIN_LENGTH      (16 * 1024)
#define TLS_COMPRESSED_OVERHEAD   1024
#define TLS_MAX_PADDING_LENGTH    256
#define TLS_LEGACY_MAX_MAC_LENGTH 20
#define TLS12_MAX_MAC_LENGTH      64
#define TLS_EXPLICIT_IV_LENGTH    16
#define TLS13_MAX_OVERHEAD        256

static inline size_t tls_get_encrypted_length(int version)
{
    switch (version) {
    case TLS1_VERSION:
        return TLS_RECORD_HEADER_LENGTH + TLS_MAX_PLAIN_LENGTH +
               TLS_COMPRESSED_OVERHEAD + TLS_LEGACY_MAX_MAC_LENGTH +
               TLS_MAX_PADDING_LENGTH;

    case TLS1_1_VERSION:
        return TLS_RECORD_HEADER_LENGTH + TLS_MAX_PLAIN_LENGTH +
               TLS_COMPRESSED_OVERHEAD + TLS_EXPLICIT_IV_LENGTH +
               TLS_LEGACY_MAX_MAC_LENGTH + TLS_MAX_PADDING_LENGTH;

    case TLS1_3_VERSION:
        /* overhead = AEAD tag (16) + inner type (1) + padding (up to 239)
         */
        return TLS_RECORD_HEADER_LENGTH + TLS_MAX_PLAIN_LENGTH +
               TLS13_MAX_OVERHEAD;

    case TLS1_2_VERSION:
    default:
        return TLS_RECORD_HEADER_LENGTH + TLS_MAX_PLAIN_LENGTH +
               TLS_COMPRESSED_OVERHEAD + TLS_EXPLICIT_IV_LENGTH +
               TLS12_MAX_MAC_LENGTH + TLS_MAX_PADDING_LENGTH;
    }
}

static inline void tls_push_error(lua_State *L, const char *default_errop,
                                  const char *default_errmsg)
{
    const int top = lua_gettop(L);
    int msgidx    = top;

#if OPENSSL_VERSION_NUMBER >= 0x30000000L
    const char *errop = NULL;
    unsigned long err = ERR_peek_error_func(&errop);

    // push error messages in reverse order
    while (err) {
        lua_pushstring(L, errop);
        lua_pushstring(L, ERR_error_string(ERR_get_error(), NULL));
        msgidx++;
        lua_insert(L, msgidx);
        lua_error_new_message(L, msgidx);
        lua_insert(L, top + 1);
        err = ERR_peek_error_func(&errop);
    }

#else
    unsigned long err = ERR_get_error();

    // push error messages in reverse order
    while (err) {
        const char *errop  = ERR_func_error_string(err);
        const char *errmsg = ERR_error_string(err, NULL);
        lua_pushstring(L, errmsg);
        lua_pushstring(L, errop);
        lua_error_new_message(L, ++msgidx);
        lua_insert(L, top + 1);
        err = ERR_get_error();
    }

#endif

    if (msgidx == top) {
        // push default error
        lua_pushstring(L, default_errmsg);
        lua_pushstring(L, default_errop);
        lua_error_new_message(L, top + 1);
        lua_error_new(L, top + 1);
        return;
    }

    // create an error that wraps all error messages
    lua_error_new(L, msgidx--);
    while (msgidx > top) {
        lua_error_new(L, msgidx--);
    }
}

#endif
