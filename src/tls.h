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

#include <arpa/inet.h>
#include <openssl/err.h>
#include <openssl/ocsp.h>
#include <openssl/ssl.h>
#include <openssl/x509_vfy.h>
#include <openssl/x509v3.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
// lua
#include <lauxhlib.h>
#include <lua_error.h>

typedef struct {
    lua_State *L;
    SSL_CTX *ctx;
    int error_cb_ref;
} tls_client_t;

#define NET_TLS_CLIENT_MT "net.tls.client"

typedef int (*tls_handshake_fn)(SSL *);

typedef struct {
    SSL *ssl;
    tls_handshake_fn handshake_cb;
    // parent context reference (tls_server_t or tls_client_t)
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

// NOTE: the cleanup process should not be performed if the OpenSSL library has
// been initialized outside of this module, as it may not work properly.
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

    return SSL_CTX_set_cipher_list(ctx, ciphers);
}

typedef enum {
    NET_TLS_PROTO_DEFAULT = 0,
    NET_TLS_PROTO_TLSv1,
    NET_TLS_PROTO_TLSv1_0,
    NET_TLS_PROTO_TLSv1_1,
    NET_TLS_PROTO_TLSv1_2,
    NET_TLS_PROTO_TLSv1_3,
} tls_protocol_t;

const char *const TLS_PROTOCOLS[] = {
    "default", // TLSv1.2 and TLSv1.3
    "tlsv1",   // TLSv1.0, TLSv1.1, TLSv1.2 and TLSv1.3
    "tlsv1.0", // TLSv1.0
    "tlsv1.1", // TLSv1.1
    "tlsv1.2", // TLSv1.2
    "tlsv1.3", // TLSv1.3
    NULL,
};

static int tls_set_protocol_vers(SSL_CTX *ctx, tls_protocol_t protocol)
{
    int minv = 0;
    int maxv = 0;

    switch (protocol) {
    default:
    case NET_TLS_PROTO_DEFAULT:
        minv = TLS1_2_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1:
        minv = TLS1_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1_0:
        minv = TLS1_VERSION;
        maxv = TLS1_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1_1:
        minv = TLS1_1_VERSION;
        maxv = TLS1_1_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1_2:
        minv = TLS1_2_VERSION;
        maxv = TLS1_2_VERSION;
        break;

    case NET_TLS_PROTO_TLSv1_3:
        minv = TLS1_3_VERSION;
        maxv = TLS1_3_VERSION;
        break;
    }

    return SSL_CTX_set_min_proto_version(ctx, minv) == 1 &&
           (maxv <= 0 || SSL_CTX_set_max_proto_version(ctx, maxv) == 1);
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
