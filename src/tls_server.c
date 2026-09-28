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

// project
#include "optcheck.h"
#include "streq.h"
#include "tls.h"
// depend
#include "lauxhlib.h"
// lua
#include <lauxlib.h>
// system
#include <arpa/inet.h>
#include <limits.h>
#include <netinet/in.h>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <stdio.h>
#include <string.h>

static int sni_callback(SSL *ssl, int *al, void *arg)
{
    tls_server_t *s  = (tls_server_t *)arg;
    const char *name = SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name);
    union {
        struct in_addr ip4;
        struct in6_addr ip6;
    } addr               = {0};
    tls_server_t *target = NULL;
    tls_ctx_t *ctx       = NULL;

    if (!name || inet_pton(AF_INET, name, &addr) == 1 ||
        inet_pton(AF_INET6, name, &addr) == 1) {
        // no server name provided by the client or
        // server name is an IP literal
        return SSL_TLSEXT_ERR_NOACK;
    }

    // call closure
    lauxh_pushref(s->L, s->sni_callback_ref);
    lua_pushstring(s->L, name);
    if (lua_pcall(s->L, 1, 1, 0) != 0) {
        // the error value may be a non-string, in which case
        // lua_tostring() returns NULL and must not reach fprintf("%s").
        const char *err = lua_tostring(s->L, -1);
        fprintf(stderr, "call closure failed: %s\n",
                err ? err : "(non-string error value)");
        lua_pop(s->L, 1);
        // failed to call callback function
        *al = SSL_AD_INTERNAL_ERROR;
        return SSL_TLSEXT_ERR_ALERT_FATAL;
    }
    if (lua_isnoneornil(s->L, -1)) {
        // not found
        lua_pop(s->L, 1);
        return SSL_TLSEXT_ERR_NOACK;
    }
    target = (tls_server_t *)luaL_checkudata(s->L, -1, NET_TLS_SERVER_MT);

    // NOTE: SSL_set_SSL_CTX() will increment the reference count of the passed
    // SSL_CTX. so, tls_server* can be gc'ed anytime after this function.
    // https://github.com/openssl/openssl/blob/b372b1f76450acdfed1e2301a39810146e28b02c/ssl/ssl_lib.c#L4151-L4153
    //
    // ...except that the target's callbacks keep running for the rest of the
    // connection context: the ALPN select callback receives the tls_server_t*
    // as its arg and reads its ALPN wire-format pointer, so the userdata must
    // stay alive.  Switch the connection's parent reference to the target so
    // that tls_ctx_t holds it until the connection closes.  The root server is
    // still owned by the Lua side.
    ctx = (tls_ctx_t *)SSL_get_app_data(ssl);
    if (!ctx) {
        // the connection context is exposed via SSL app_data by every
        // handshake call; a missing one means the library's call structure
        // is broken, not a user error
        lua_pop(s->L, 1);
        fprintf(stderr, "sni_callback: connection context not found\n");
        *al = SSL_AD_INTERNAL_ERROR;
        return SSL_TLSEXT_ERR_ALERT_FATAL;
    }
    ctx->parent = target;
    lauxh_unref(s->L, ctx->parent_ref);
    ctx->parent_ref = lauxh_ref(s->L);
    SSL_set_SSL_CTX(ssl, target->ctx);
    // SSL_set_SSL_CTX() only replaces the certificate chain and the
    // sid_ctx; the verify_mode, the verify depth and the X509_VERIFY_PARAM
    // stay on the connection.  Re-apply them from the target CTX so a
    // vhost that configured verify options at construction actually
    // enforces its policy on the switched connection (nginx-style: the CTX
    // stays the single source of truth).  All accessors exist since
    // OpenSSL 1.0.2.
    SSL_set_verify(ssl, SSL_CTX_get_verify_mode(target->ctx),
                   SSL_CTX_get_verify_callback(target->ctx));
    SSL_set_verify_depth(ssl, SSL_CTX_get_verify_depth(target->ctx));
    if (SSL_set1_param(ssl, SSL_CTX_get0_param(target->ctx)) != 1) {
        // the verify parameters could not be transferred; the connection
        // would keep the root context's parameters and silently enforce
        // the wrong policy, so abort the handshake instead.  reachable
        // only on an allocation failure, hence not covered from Lua
        *al = SSL_AD_INTERNAL_ERROR;
        return SSL_TLSEXT_ERR_ALERT_FATAL;
    }

    return SSL_TLSEXT_ERR_OK;
}

static int sni_callback_closure(lua_State *L)
{
    lua_settop(L, 1);
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_pushvalue(L, 1);
    lua_call(L, 1, 1);
    if (!lua_isnoneornil(L, -1)) {
        luaL_checkudata(L, -1, NET_TLS_SERVER_MT);
    }
    return 1;
}

// Parsed opts destination for new_lua().
typedef struct {
    // certificate chain and private key paths (required)
    const char *cert;
    const char *key;
    int protocol;
    int cipher;
    int alpn_ref;
    lua_Integer sess_timeout;
    lua_Integer sess_cache;
    int prefer_client_ciphers;
    // verify options; mode/depth are -1 while the opts keys are absent
    int verify_mode;
    int verify_depth;
    const char *cafile;
    const char *capath;
} server_opts_t;

/**
 * @brief opts.cert callback.
 */
static int check_opt_cert(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;
    size_t len;
    const char *value;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    value = lua_tolstring(L, -1, &len);
    if (memchr(value, '\0', len)) {
        return luaL_error(L, "opts.%s must not contain NUL", name);
    }
    opts->cert = value;
    return 0;
}

/**
 * @brief opts.key callback.
 */
static int check_opt_key(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;
    size_t len;
    const char *value;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    value = lua_tolstring(L, -1, &len);
    if (memchr(value, '\0', len)) {
        return luaL_error(L, "opts.%s must not contain NUL", name);
    }
    opts->key = value;
    return 0;
}

/**
 * @brief opts.protocol callback.
 */
static int check_opt_protocol(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;
    size_t len          = 0;
    const char *s       = lua_tolstring(L, -1, &len);

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    for (int i = 0; TLS_PROTOCOLS[i]; i++) {
        if (STR_EQ(s, len, TLS_PROTOCOLS[i], strlen(TLS_PROTOCOLS[i]))) {
            opts->protocol = i;
            return 0;
        }
    }
    return luaL_error(L, "opts.%s='%s' is not recognized", name, s);
}

/**
 * @brief opts.cipher callback.
 */
static int check_opt_cipher(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;
    size_t len          = 0;
    const char *s       = lua_tolstring(L, -1, &len);

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    for (int i = 0; TLS_CIPHER_SUITES[i]; i++) {
        if (STR_EQ(s, len, TLS_CIPHER_SUITES[i],
                   strlen(TLS_CIPHER_SUITES[i]))) {
            opts->cipher = i;
            return 0;
        }
    }
    return luaL_error(L, "opts.%s='%s' is not recognized", name, s);
}

/**
 * @brief Convert opts.alpn to wire format and retain it until construction
 * completes.
 */
static int check_opt_alpn(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;

    if (lua_type(L, -1) != LUA_TTABLE) {
        return luaL_error(L, "opts.%s must be table, got %s", name,
                          luaL_typename(L, -1));
    }

    int nalpn = tls_check_alpn_table(L, lua_gettop(L));
    if (nalpn < 0) {
        return luaL_error(L, "%s", lua_tostring(L, -1));
    }
    if (nalpn > 0) {
        opts->alpn_ref = lauxh_refat(L, -1);
    }
    return 0;
}

/**
 * @brief opts.session_timeout callback.
 */
static int check_opt_sess_timeout(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;

    if (lua_type(L, -1) != LUA_TNUMBER) {
        return luaL_error(L, "opts.%s must be integer, got %s", name,
                          luaL_typename(L, -1));
    }
    opts->sess_timeout = lauxh_checkinteger(L, -1);
    return 0;
}

/**
 * @brief opts.session_cache_size callback.
 */
static int check_opt_sess_cache(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;

    if (lua_type(L, -1) != LUA_TNUMBER) {
        return luaL_error(L, "opts.%s must be integer, got %s", name,
                          luaL_typename(L, -1));
    }
    opts->sess_cache = lauxh_checkinteger(L, -1);
    return 0;
}

/**
 * @brief opts.prefer_client_ciphers callback.
 */
static int check_opt_prefer_client(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;

    if (lua_isboolean(L, -1)) {
        opts->prefer_client_ciphers = lua_toboolean(L, -1);
        return 0;
    } else if (lua_isnoneornil(L, -1)) {
        return 0;
    }
    return luaL_error(L, "opts.%s must be boolean, got %s", name,
                      luaL_typename(L, -1));
}

/**
 * @brief opts.verify_mode callback: map string to the verification mode.
 */
static int check_opt_verify_mode(lua_State *L, const char *name, void *ctx)
{
    static const struct {
        const char *name;
        int value;
    } MODES[] = {
        {"none",    SSL_VERIFY_NONE                                  },
        {"request", SSL_VERIFY_PEER                                  },
        {"require", SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT},
        {NULL,      0                                                },
    };
    server_opts_t *opts = ctx;
    size_t len          = 0;
    const char *s       = NULL;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }

    s = lua_tolstring(L, -1, &len);
    for (int i = 0; MODES[i].name; i++) {
        if (STR_EQ(s, len, MODES[i].name, strlen(MODES[i].name))) {
            opts->verify_mode = MODES[i].value;
            return 0;
        }
    }
    return luaL_error(L,
                      "opts.%s='%s' is not a recognized mode (must be "
                      "one of \"none\", \"request\", \"require\")",
                      name, s);
}

/**
 * @brief opts.verify_depth callback.
 */
static int check_opt_verify_depth(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;
    lua_Integer depth   = 0;

    if (lua_type(L, -1) != LUA_TNUMBER) {
        return luaL_error(L, "opts.%s must be integer, got %s", name,
                          luaL_typename(L, -1));
    }
    depth = lauxh_checkinteger(L, -1);
    if (depth < 0 || depth > INT_MAX) {
        return luaL_error(L, "opts.%s must be uint", name);
    }
    opts->verify_depth = (int)depth;
    return 0;
}

/**
 * @brief opts.cafile callback.
 */
static int check_opt_cafile(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;
    size_t len;
    const char *value;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    value = lua_tolstring(L, -1, &len);
    if (memchr(value, '\0', len)) {
        return luaL_error(L, "opts.%s must not contain NUL", name);
    }
    opts->cafile = value;
    return 0;
}

/**
 * @brief opts.capath callback.
 */
static int check_opt_capath(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;
    size_t len;
    const char *value;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    value = lua_tolstring(L, -1, &len);
    if (memchr(value, '\0', len)) {
        return luaL_error(L, "opts.%s must not contain NUL", name);
    }
    opts->capath = value;
    return 0;
}

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, NET_TLS_SERVER_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int alpn_select_cb(SSL *ssl, const unsigned char **out,
                          unsigned char *outlen, const unsigned char *client,
                          unsigned int client_len, void *arg)
{
    (void)ssl;
    tls_server_t *s = (tls_server_t *)arg;
    if (!s->alpn || s->alpn_len == 0) {
        return SSL_TLSEXT_ERR_NOACK;
    }
    if (SSL_select_next_proto((unsigned char **)out, outlen, s->alpn,
                              s->alpn_len, client,
                              client_len) == OPENSSL_NPN_NEGOTIATED) {
        return SSL_TLSEXT_ERR_OK;
    }
    // RFC 7301: abort the handshake with a fatal no_application_protocol
    // alert when the client and server protocol lists share no protocol;
    // OpenSSL maps a fatal return of this callback to that alert
    return SSL_TLSEXT_ERR_ALERT_FATAL;
}

static int gc_lua(lua_State *L)
{
    tls_server_t *s = luaL_checkudata(L, 1, NET_TLS_SERVER_MT);
    // ctx is NULL when the constructor failed after the metatable was set
    if (s->ctx) {
        SSL_CTX_set_tlsext_servername_callback(s->ctx, NULL);
        SSL_CTX_set_tlsext_servername_arg(s->ctx, NULL);
        SSL_CTX_free(s->ctx);
        s->ctx = NULL;
    }
    s->sni_callback_ref = lauxh_unref(L, s->sni_callback_ref);
    s->ref_alpn         = lauxh_unref(L, s->ref_alpn);
    return 0;
}

static void set_session_conf(SSL_CTX *ctx, long timeout, long cache_size)
{
    SSL_CTX_set_timeout(ctx, timeout);
    SSL_CTX_set_session_cache_mode(ctx, SSL_SESS_CACHE_SERVER);
    // cache_size <= 0 must not reach OpenSSL: 0 means "unlimited" there,
    // so keep the context default instead (same rule as the client)
    if (cache_size > 0) {
        SSL_CTX_sess_set_cache_size(ctx, cache_size);
    }
    SSL_CTX_set_options(ctx, SSL_OP_NO_TICKET);
}

static int new_lua(lua_State *L)
{
    static const net_socket_option_spec_t SPECS[] = {
        {"cert",                 check_opt_cert        },
        {"key",                  check_opt_key         },
        {"protocol",             check_opt_protocol    },
        {"cipher",               check_opt_cipher      },
        {"session_timeout",      check_opt_sess_timeout},
        {"session_cache_size",   check_opt_sess_cache  },
        {"prefer_client_ciphers", check_opt_prefer_client},
        {"verify_mode",          check_opt_verify_mode },
        {"verify_depth",         check_opt_verify_depth},
        {"cafile",               check_opt_cafile      },
        {"capath",               check_opt_capath      },
    };
    server_opts_t opts = {
        .cert                = NULL,
        .key                 = NULL,
        .protocol            = 0, // "default"
        .cipher              = 0, // "default"
        .alpn_ref            = LUA_NOREF,
        .sess_timeout        = 300,
        .sess_cache          = 1024 * 20,
        .prefer_client_ciphers = 0,
        .verify_mode         = -1,
        .verify_depth        = -1,
        .cafile              = NULL,
        .capath              = NULL,
    };
    tls_server_t *s    = NULL;
    const char *errop  = NULL;
    const char *errmsg = NULL;
    int sni_callback_idx = 0;

    luaL_checktype(L, 1, LUA_TTABLE);

    // discard stale errors from the thread-local queue so a failure below
    // reports only its own errors (read/write/handshake/shutdown do the
    // same)
    ERR_clear_error();

    NET_SOCKET_CHECK_OPTIONS(L, 1, SPECS, &opts);

    if (!opts.cert) {
        return luaL_error(L, "opts.cert is required");
    } else if (!opts.key) {
        return luaL_error(L, "opts.key is required");
    }
    lua_getfield(L, 1, "sni_callback");
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
    } else if (!lua_isfunction(L, -1)) {
        return luaL_error(L, "opts.sni_callback must be function, got %s",
                          luaL_typename(L, -1));
    } else {
        sni_callback_idx = lua_gettop(L);
    }
    lua_getfield(L, 1, "alpn");
    if (!lua_isnil(L, -1)) {
        check_opt_alpn(L, "alpn", &opts);
    }
    lua_pop(L, 1);

    // create context
    s  = lua_newuserdata(L, sizeof(tls_server_t));
    *s = (tls_server_t){
        .L                = L,
        .sni_callback_ref = LUA_NOREF,
        .alpn             = NULL,
        .alpn_len         = 0,
        .ref_alpn         = LUA_NOREF,
        .ctx              = NULL,
    };
    // set the metatable before creating the SSL_CTX: a later allocation
    // failure raises past this frame, and the __gc must then free the ctx.
    // With ctx NULL the __gc is a no-op.
    lauxh_setmetatable(L, NET_TLS_SERVER_MT);
    s->ctx = SSL_CTX_new(TLS_server_method());
    if (!s->ctx) {
        errop  = "SSL_CTX_new";
        errmsg = "failed to create SSL_CTX";
        goto FAIL;
    }

    // set mode
    SSL_CTX_clear_mode(s->ctx, SSL_MODE_AUTO_RETRY);
    SSL_CTX_set_mode(s->ctx, SSL_MODE_ENABLE_PARTIAL_WRITE);
    SSL_CTX_set_mode(s->ctx, SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);

    // set certificate chain (leaf followed by intermediate CAs in a
    // single PEM file, as recommended by OpenSSL for server certificates)
    if (SSL_CTX_use_certificate_chain_file(s->ctx, opts.cert) != 1) {
        errop  = "SSL_CTX_use_certificate_chain_file";
        errmsg = "failed to load certificate chain file";
        goto FAIL;
    }

    // set private key
    if (SSL_CTX_use_PrivateKey_file(s->ctx, opts.key, SSL_FILETYPE_PEM) != 1) {
        errop  = "SSL_CTX_use_PrivateKey_file";
        errmsg = "failed to load private key file";
        goto FAIL;
    }

    // check that the private key matches the certificate
    if (SSL_CTX_check_private_key(s->ctx) != 1) {
        errop  = "SSL_CTX_check_private_key";
        errmsg = "private key does not match the certificate";
        goto FAIL;
    }

    // set protocol version
    if (tls_set_protocol_vers(s->ctx, opts.protocol) != 1) {
        errop  = "tls_set_protocol_vers";
        errmsg = "failed to set protocol version";
        goto FAIL;
    }

    // set cipher suite
    if (tls_set_cipher_suite(s->ctx, opts.cipher) != 1) {
        errop  = "tls_set_cipher_suite";
        errmsg = "failed to set cipher suite";
        goto FAIL;
    }

    // set DH parameters based on the cipher suites in use
    if (SSL_CTX_set_dh_auto(s->ctx, 1) != 1) {
        errop = "SSL_CTX_set_dh_auto";
        errmsg =
            "failed to set DH parameters based on the cipher suites in use";
        goto FAIL;
    }

    // set session configuration; a non-positive timeout disables the
    // session cache and tickets, mirroring the client-side
    // session_cache_timeout convention
    if (opts.sess_timeout > 0) {
        set_session_conf(s->ctx, (long)opts.sess_timeout,
                         (long)opts.sess_cache);
    } else {
        SSL_CTX_set_session_cache_mode(s->ctx, SSL_SESS_CACHE_OFF);
        SSL_CTX_set_options(s->ctx, SSL_OP_NO_TICKET);
    }
    // reject TLS 1.2 renegotiation: no consumer of this library drives
    // it, and allowing it exposes the server to renegotiation-based DoS
    SSL_CTX_set_options(s->ctx, SSL_OP_NO_RENEGOTIATION);
    // prefer server cipher suites over client cipher suites
    if (!opts.prefer_client_ciphers) {
        SSL_CTX_set_options(s->ctx, SSL_OP_CIPHER_SERVER_PREFERENCE);
    }

    // load the caller-specified trusted CA locations and apply the
    // verification options (all-or-nothing: the SSL_CTX is immutable
    // after construction)
    if (opts.cafile || opts.capath) {
        if (SSL_CTX_load_verify_locations(s->ctx, opts.cafile, opts.capath) !=
            1) {
            errop  = "SSL_CTX_load_verify_locations";
            errmsg = "failed to load verify locations";
            goto FAIL;
        }
    }
    if (opts.verify_depth >= 0) {
        SSL_CTX_set_verify_depth(s->ctx, opts.verify_depth);
    }
    if (opts.verify_mode >= 0) {
        SSL_CTX_set_verify(s->ctx, opts.verify_mode, NULL);
    }

    // configure ALPN (Application-Layer Protocol Negotiation)
    if (lauxh_isref(opts.alpn_ref)) {
        lauxh_pushref(L, opts.alpn_ref);
        s->alpn = (unsigned char *)lua_tolstring(L, -1, &s->alpn_len);
        s->alpn_len = (unsigned int)s->alpn_len;
        s->ref_alpn = lauxh_ref(L);
        SSL_CTX_set_alpn_select_cb(s->ctx, alpn_select_cb, s);
    }

    // configure SNI callback when opts.sni_callback is present; wrap the
    // callback in the validating closure (no extra args through opts —
    // capture them in the user's own closure)
    if (sni_callback_idx) {
        lua_pushvalue(L, sni_callback_idx);
        lua_pushcclosure(L, sni_callback_closure, 1);
        s->sni_callback_ref = lauxh_ref(L);
        SSL_CTX_set_tlsext_servername_callback(s->ctx, sni_callback);
        SSL_CTX_set_tlsext_servername_arg(s->ctx, s);
    }

    if (lauxh_isref(opts.alpn_ref)) {
        opts.alpn_ref = lauxh_unref(L, opts.alpn_ref);
    }
    return 1;

FAIL:
    if (lauxh_isref(opts.alpn_ref)) {
        opts.alpn_ref = lauxh_unref(L, opts.alpn_ref);
    }
    if (s && s->ctx) {
        SSL_CTX_free(s->ctx);
        // prevent the pending __gc (the metatable is already set) from
        // double-freeing the ctx
        s->ctx = NULL;
    }
    lua_pushnil(L);
    tls_push_error(L, errop, errmsg);
    return 2;
}

LUALIB_API int luaopen_net_tls_server(lua_State *L)
{
    struct luaL_Reg mmethod[] = {
        {"__gc",       gc_lua      },
        {"__tostring", tostring_lua},
        {NULL,         NULL        }
    };

    luaL_newmetatable(L, NET_TLS_SERVER_MT);
    for (struct luaL_Reg *ptr = mmethod; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    // no mutation methods: the SSL_CTX is immutable after construction
    lua_newtable(L);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    // initialize
    tls_init(L);

    lua_pushcfunction(L, new_lua);
    return 1;
}
