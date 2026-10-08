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
#include "net_pcall.h"
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
#include <openssl/rand.h>
#include <openssl/ssl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, NET_TLS_SERVER_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    tls_server_t *s = luaL_checkudata(L, 1, NET_TLS_SERVER_MT);
    if (lauxh_isref(s->ref_ctx)) {
        s->ref_ctx = lauxh_unref(L, s->ref_ctx);
    }
    if (lauxh_isref(s->sni_callback_ref)) {
        s->sni_callback_ref = lauxh_unref(L, s->sni_callback_ref);
    }
    s->sslctx = NULL;
    s->ctx    = NULL;
    return 0;
}

static int sni_callback(SSL *ssl, int *al, void *arg)
{
    (void)ssl;
    (void)al;
    (void)arg;
    return SSL_TLSEXT_ERR_OK;
}

typedef struct {
    SSL *ssl;
    tls_ctx_t *ctx;
    const char *name;
    int result;
} client_hello_t;

static int select_server_lua(lua_State *L)
{
    client_hello_t *hello = lua_touserdata(L, 1);
    tls_ctx_t *ctx        = hello->ctx;
    tls_server_t *s       = (tls_server_t *)ctx->parent;
    tls_server_t *target  = NULL;
    SSL *ssl              = hello->ssl;
    int ref               = LUA_NOREF;

    // Call the SNI callback to select the appropriate server based on the
    // client hello name.
    lauxh_pushref(L, s->sni_callback_ref);
    lua_pushstring(L, hello->name);
    if (lua_pcall(L, 1, 1, 0) != 0) {
        // Do not stringify numbers: that conversion can itself allocate.
        const char *err = lua_type(L, -1) == LUA_TSTRING ?
                              lua_tostring(L, -1) :
                              "(non-string error value)";
        fprintf(stderr, "call closure failed: %s\n", err);
        return 0;
    }

    // If the callback returned nil, it means no specific server was selected.
    if (lua_isnoneornil(L, -1)) {
        hello->result = SSL_CLIENT_HELLO_SUCCESS;
        return 0;
    }

    // The validating SNI closure already checked this non-nil server userdata.
    target = (tls_server_t *)lua_touserdata(L, -1);
    // Acquire the new reference before releasing the old parent. A failed
    // allocation must leave the connection's current owner intact.
    ref    = lauxh_ref(L);
    lauxh_unref(L, ctx->parent_ref);
    ctx->parent_ref = ref;
    ctx->parent     = target;
    if (!SSL_set_SSL_CTX(ssl, target->ctx)) {
        return 0;
    }

    // SSL_set_SSL_CTX() does not copy the cipher preference option.
    if (SSL_CTX_get_options(target->ctx) & SSL_OP_CIPHER_SERVER_PREFERENCE) {
        SSL_set_options(ssl, SSL_OP_CIPHER_SERVER_PREFERENCE);
    } else {
        SSL_clear_options(ssl, SSL_OP_CIPHER_SERVER_PREFERENCE);
    }

    // Protocol limits are copied by SSL_new(), not SSL_set_SSL_CTX().
    if (SSL_set_min_proto_version(
            ssl, SSL_CTX_get_min_proto_version(target->ctx)) != 1 ||
        SSL_set_max_proto_version(
            ssl, SSL_CTX_get_max_proto_version(target->ctx)) != 1) {
        return 0;
    }

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
        // Abort rather than silently retaining the root verification policy.
        return 0;
    }
    hello->result = SSL_CLIENT_HELLO_SUCCESS;
    return 0;
}

static int client_hello_cb(SSL *ssl, int *al, void *arg)
{
    (void)arg;
    tls_ctx_t *ctx                         = (tls_ctx_t *)SSL_get_app_data(ssl);
    const unsigned char *ext               = NULL;
    size_t extlen                          = 0;
    size_t namelen                         = 0;
    char name[TLSEXT_MAXLEN_host_name + 1] = {0};
    client_hello_t hello                   = {
        .ssl    = ssl,
        .ctx    = ctx,
        .name   = name,
        .result = SSL_CLIENT_HELLO_ERROR,
    };
    union {
        struct in_addr ip4;
        struct in6_addr ip6;
    } addr = {0};

    if (!ctx || !ctx->parent) {
        *al = SSL_AD_INTERNAL_ERROR;
        return SSL_CLIENT_HELLO_ERROR;
    }
    if (((tls_server_t *)ctx->parent)->sni_callback_ref == LUA_NOREF) {
        return SSL_CLIENT_HELLO_SUCCESS;
    }
    // HelloRetryRequest may invoke the selected CTX's callback again.
    // Keep the initial selection, including fallback to the default server.
    if (ctx->sni_done) {
        return SSL_CLIENT_HELLO_SUCCESS;
    }
    ctx->sni_done = 1;

    // The ClientHello callback runs before OpenSSL populates servername.
    // Parse the ServerNameList, containing one host_name, from the raw
    // extension.
    if (!SSL_client_hello_get0_ext(ssl, TLSEXT_TYPE_server_name, &ext,
                                   &extlen)) {
        return SSL_CLIENT_HELLO_SUCCESS;
    } else if (extlen < 5 || ((size_t)ext[0] << 8 | ext[1]) != extlen - 2 ||
               ext[2] != TLSEXT_NAMETYPE_host_name) {
        *al = SSL_AD_DECODE_ERROR;
        return SSL_CLIENT_HELLO_ERROR;
    }

    // Extract the host_name from the ServerNameList extension.
    namelen = (size_t)ext[3] << 8 | ext[4];
    if (namelen != extlen - 5) {
        *al = SSL_AD_DECODE_ERROR;
        return SSL_CLIENT_HELLO_ERROR;
    } else if (!namelen || namelen > TLSEXT_MAXLEN_host_name ||
               memchr(ext + 5, '\0', namelen)) {
        *al = SSL_AD_UNRECOGNIZED_NAME;
        return SSL_CLIENT_HELLO_ERROR;
    }
    memcpy(name, ext + 5, namelen);
    name[namelen] = '\0';

    // Check if the server name is an IP literal.
    if (inet_pton(AF_INET, name, &addr) == 1 ||
        inet_pton(AF_INET6, name, &addr) == 1) {
        // server name is an IP literal
        return SSL_CLIENT_HELLO_SUCCESS;
    }

    // Call the Lua callback to select the appropriate server based on the
    // client hello.
    if (net_pcall(((tls_server_t *)ctx->parent)->sslctx->L, select_server_lua,
                  &hello) != 0 ||
        hello.result != SSL_CLIENT_HELLO_SUCCESS) {
        *al = SSL_AD_INTERNAL_ERROR;
        return SSL_CLIENT_HELLO_ERROR;
    }

    return SSL_CLIENT_HELLO_SUCCESS;
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

static int alpn_select_cb(SSL *ssl, const unsigned char **out,
                          unsigned char *outlen, const unsigned char *client,
                          unsigned int client_len, void *arg)
{
    (void)ssl;
    tls_ssl_ctx_t *s = (tls_ssl_ctx_t *)arg;
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

static inline void key_add_blob(luaL_Buffer *buf, const void *data, size_t len)
{
    uint64_t length = (uint64_t)len;
    luaL_addlstring(buf, (const char *)&length, sizeof(length));
    if (len) {
        luaL_addlstring(buf, data, len);
    }
}

static inline void key_add_optional(luaL_Buffer *buf, const char *value)
{
    unsigned char present = value != NULL;
    luaL_addlstring(buf, (const char *)&present, sizeof(present));
    key_add_blob(buf, value, value ? strlen(value) : 0);
}

// Parsed opts destination for new_lua().
typedef struct {
    // certificate chain and private key paths (required)
    const char *cert;
    const char *key;
    int protocol;
    int cipher;
    int alpn_idx;
    lua_Integer sess_timeout;
    int prefer_client_ciphers;
    // verify options; mode/depth are -1 while the opts keys are absent
    int verify_mode;
    int verify_depth;
    const char *cafile;
    const char *capath;
    tls_cache_t *cache;
} server_opts_t;

static void push_cache_key(lua_State *L, const server_opts_t *opts)
{
    luaL_Buffer buf;
    const char *alpn = NULL;
    size_t alpn_len  = 0;

    if (opts->alpn_idx) {
        alpn = lua_tolstring(L, opts->alpn_idx, &alpn_len);
    }
    luaL_buffinit(L, &buf);
    key_add_blob(&buf, "server", sizeof("server") - 1);
    key_add_blob(&buf, opts->cert, strlen(opts->cert));
    key_add_blob(&buf, opts->key, strlen(opts->key));
    key_add_blob(&buf, &opts->protocol, sizeof(opts->protocol));
    key_add_blob(&buf, &opts->cipher, sizeof(opts->cipher));
    key_add_blob(&buf, alpn, alpn_len);
    key_add_blob(&buf, &opts->sess_timeout, sizeof(opts->sess_timeout));
    key_add_blob(&buf, &opts->prefer_client_ciphers,
                 sizeof(opts->prefer_client_ciphers));
    key_add_blob(&buf, &opts->verify_mode, sizeof(opts->verify_mode));
    key_add_blob(&buf, &opts->verify_depth, sizeof(opts->verify_depth));
    key_add_optional(&buf, opts->cafile);
    key_add_optional(&buf, opts->capath);
    luaL_pushresult(&buf);
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
        opts->alpn_idx = lua_gettop(L);
    }
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

static int check_opt_cache(lua_State *L, const char *name, void *ctx)
{
    server_opts_t *opts = ctx;
    (void)name;
    opts->cache = luaL_checkudata(L, -1, NET_TLS_CACHE_MT);
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

static int new_lua(lua_State *L)
{
    static const optspec_t SPECS[] = {
        {"cert",                  check_opt_cert         },
        {"key",                   check_opt_key          },
        {"protocol",              check_opt_protocol     },
        {"cipher",                check_opt_cipher       },
        {"session_timeout",       check_opt_sess_timeout },
        {"cache",                 check_opt_cache        },
        {"prefer_client_ciphers", check_opt_prefer_client},
        {"verify_mode",           check_opt_verify_mode  },
        {"verify_depth",          check_opt_verify_depth },
        {"cafile",                check_opt_cafile       },
        {"capath",                check_opt_capath       },
    };
    server_opts_t opts = {
        .cert                  = NULL,
        .key                   = NULL,
        .protocol              = 0, // "default"
        .cipher                = 0, // "default"
        .alpn_idx              = 0,
        .sess_timeout          = 300,
        .prefer_client_ciphers = 0,
        .verify_mode           = -1,
        .verify_depth          = -1,
        .cafile                = NULL,
        .capath                = NULL,
    };
    tls_server_t *s       = NULL;
    tls_ssl_ctx_t *sslctx = NULL;
    const char *errop     = NULL;
    const char *errmsg    = NULL;
    int sni_callback_idx  = 0;
    int keyidx            = 0;
    unsigned char sid_ctx[SSL_MAX_SID_CTX_LENGTH];

    luaL_checktype(L, 1, LUA_TTABLE);

    // discard stale errors from the thread-local queue so a failure below
    // reports only its own errors (read/write/handshake/shutdown do the
    // same)
    ERR_clear_error();

    OPTSPEC_CHECK(L, 1, SPECS, &opts);

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
    // Keep the wire-format string on the stack until construction completes.
    if (!opts.alpn_idx) {
        lua_pop(L, 1);
    }

    if (opts.cache) {
        push_cache_key(L, &opts);
        keyidx = lua_gettop(L);
    }

    // create context
    s  = lua_newuserdata(L, sizeof(tls_server_t));
    *s = (tls_server_t){
        .ctx              = NULL,
        .sslctx           = NULL,
        .ref_ctx          = LUA_NOREF,
        .sni_callback_ref = LUA_NOREF,
    };
    // Keep the server finalizer active while constructing the owned context.
    lauxh_setmetatable(L, NET_TLS_SERVER_MT);
    if ((sslctx = tls_cache_ssl_ctx_get(L, opts.cache, keyidx))) {
        goto READY;
    }
    sslctx = tls_ssl_ctx_new(L, TLS_server_method(), NULL);
    s->ctx = sslctx->ctx;
    if (!s->ctx) {
        errop  = "SSL_CTX_new";
        errmsg = "failed to create SSL_CTX";
        goto FAIL;
    }

    // Bind ticket-authenticated client identities to this immutable CTX.
    // OpenSSL requires a nonempty scope when resuming verified sessions;
    // this does not enable the Session ID cache.
    if (RAND_bytes(sid_ctx, sizeof(sid_ctx)) != 1 ||
        SSL_CTX_set_session_id_context(s->ctx, sid_ctx, sizeof(sid_ctx)) != 1) {
        errop  = "SSL_CTX_set_session_id_context";
        errmsg = "failed to initialize session context";
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

    // set session configuration; a non-positive timeout disables
    // tickets in both TLS versions
    if (opts.sess_timeout > 0) {
        // Only stateless tickets are supported; never store Session IDs or
        // TLS 1.3 stateful tickets in the server's internal session cache.
        SSL_CTX_set_timeout(s->ctx, (long)opts.sess_timeout);
        SSL_CTX_set_session_cache_mode(s->ctx, SSL_SESS_CACHE_OFF);
        SSL_CTX_clear_options(s->ctx, SSL_OP_NO_TICKET);
    } else {
        SSL_CTX_set_session_cache_mode(s->ctx, SSL_SESS_CACHE_OFF);
        SSL_CTX_set_options(s->ctx, SSL_OP_NO_TICKET);
        // NO_TICKET alone selects stateful tickets in TLS 1.3.
        SSL_CTX_set_num_tickets(s->ctx, 0);
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
    if (opts.alpn_idx) {
        lua_pushvalue(L, opts.alpn_idx);
        sslctx->alpn = (unsigned char *)lua_tolstring(L, -1, &sslctx->alpn_len);
        sslctx->ref_alpn = lauxh_ref(L);
        SSL_CTX_set_alpn_select_cb(s->ctx, alpn_select_cb, sslctx);
    }

    // The shared CTX only holds the internal SNI callbacks.
    SSL_CTX_set_client_hello_cb(s->ctx, client_hello_cb, sslctx);
    SSL_CTX_set_tlsext_servername_callback(s->ctx, sni_callback);

    tls_cache_ssl_ctx_put(L, opts.cache, keyidx, -1);

READY:
    s->sslctx  = sslctx;
    s->ctx     = sslctx->ctx;
    s->ref_ctx = lauxh_refat(L, -1);
    lua_pop(L, 1);

    // Each server owns its Lua callback, including when the CTX is cached.
    if (sni_callback_idx) {
        lua_pushvalue(L, sni_callback_idx);
        lua_pushcclosure(L, sni_callback_closure, 1);
        s->sni_callback_ref = lauxh_ref(L);
    }

    return 1;

FAIL:
    if (s) {
        s->sslctx = NULL;
        s->ctx    = NULL;
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
    tls_cache_loadlib(L);

    lua_pushcfunction(L, new_lua);
    return 1;
}
