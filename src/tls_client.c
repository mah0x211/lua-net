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
#include <limits.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509_vfy.h>
#include <stdint.h>
#include <string.h>

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, NET_TLS_CLIENT_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    tls_client_t *c = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    if (lauxh_isref(c->ref_ctx)) {
        c->ref_ctx = lauxh_unref(L, c->ref_ctx);
    }
    c->sslctx = NULL;
    c->ctx    = NULL;
    return 0;
}

// Parsed opts destination for new_lua().
typedef struct {
    int protocol;
    int cipher;
    int alpn_ref;
    lua_Integer cache_timeout;
    lua_Integer cache_size;
    lua_Integer verify_depth; // -1 while the opts key is absent
    const char *cafile;
    const char *capath;
    size_t crls_len;
    const char *crls;
    tls_cache_t *cache;
} client_opts_t;

/**
 * @brief opts.protocol callback: map string to the TLS_PROTOCOLS index.
 */
static int check_opt_protocol(lua_State *L, const char *name, void *ctx)
{
    client_opts_t *opts = ctx;
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
 * @brief opts.cipher callback: map string to the TLS_CIPHER_SUITES index.
 */
static int check_opt_cipher(lua_State *L, const char *name, void *ctx)
{
    client_opts_t *opts = ctx;
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
    client_opts_t *opts = ctx;

    if (lua_type(L, -1) != LUA_TTABLE) {
        return luaL_error(L, "opts.%s must be table, got %s", name,
                          luaL_typename(L, -1));
    }

    // tls_check_alpn_table replaces the table at -1 with the wire-format
    // string (or raises / leaves an error message)
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
 * @brief opts.session_cache_timeout callback.
 */
static int check_opt_cache_timeout(lua_State *L, const char *name, void *ctx)
{
    client_opts_t *opts = ctx;

    if (lua_type(L, -1) != LUA_TNUMBER) {
        return luaL_error(L, "opts.%s must be integer, got %s", name,
                          luaL_typename(L, -1));
    }
    opts->cache_timeout = lauxh_checkinteger(L, -1);
    return 0;
}

/**
 * @brief opts.session_cache_size callback.
 */
static int check_opt_cache_size(lua_State *L, const char *name, void *ctx)
{
    client_opts_t *opts = ctx;

    if (lua_type(L, -1) != LUA_TNUMBER) {
        return luaL_error(L, "opts.%s must be integer, got %s", name,
                          luaL_typename(L, -1));
    }
    opts->cache_size = lauxh_checkinteger(L, -1);
    return 0;
}

/**
 * @brief opts.verify_depth callback.
 */
static int check_opt_verify_depth(lua_State *L, const char *name, void *ctx)
{
    client_opts_t *opts = ctx;
    lua_Integer depth   = 0;

    if (lua_type(L, -1) != LUA_TNUMBER) {
        return luaL_error(L, "opts.%s must be integer, got %s", name,
                          luaL_typename(L, -1));
    }
    depth = lauxh_checkinteger(L, -1);
    // SSL_CTX_set_verify_depth() takes int; a depth above INT_MAX would
    // narrow to a negative limit after the cast
    if (depth < 0 || depth > INT_MAX) {
        return luaL_error(L, "opts.%s must be uint", name);
    }
    opts->verify_depth = depth;
    return 0;
}

/**
 * @brief opts.cafile callback.
 */
static int check_opt_cafile(lua_State *L, const char *name, void *ctx)
{
    client_opts_t *opts = ctx;
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
    client_opts_t *opts = ctx;
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
 * @brief opts.crls callback.
 */
static int check_opt_crls(lua_State *L, const char *name, void *ctx)
{
    client_opts_t *opts = ctx;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    opts->crls = lua_tolstring(L, -1, &opts->crls_len);
    return 0;
}

static int check_opt_cache(lua_State *L, const char *name, void *ctx)
{
    client_opts_t *opts = ctx;
    (void)name;
    opts->cache = luaL_checkudata(L, -1, NET_TLS_CACHE_MT);
    return 0;
}

// Load the CRLs PEM into the SSL_CTX's certificate store.
// Returns 0 on success; on failure fills errop/errmsg.
static int load_crls(SSL_CTX *ctx, const char *crls, size_t len,
                     const char **errop, const char **errmsg)
{
    X509_STORE *store        = SSL_CTX_get_cert_store(ctx);
    BIO *bio                 = NULL;
    STACK_OF(X509_INFO) *inf = NULL;
    int rc                   = -1;

    // BIO_new_mem_buf takes int; refuse >INT_MAX to prevent truncation
    if (len > (size_t)INT_MAX) {
        *errop  = "BIO_new_mem_buf";
        *errmsg = "CRL PEM buffer exceeds INT_MAX";
        goto DONE;
    }
    bio = BIO_new_mem_buf((void *)crls, (int)len);
    if (!bio) {
        *errop  = "BIO_new_mem_buf";
        *errmsg = "failed to create BIO";
        goto DONE;
    }

    inf = PEM_X509_INFO_read_bio(bio, NULL, NULL, NULL);
    if (!inf) {
        *errop  = "PEM_X509_INFO_read_bio";
        *errmsg = "failed to read CRLs";
        goto DONE;
    }

    for (int i = 0; i < sk_X509_INFO_num(inf); i++) {
        X509_INFO *it = sk_X509_INFO_value(inf, i);
        if (!it->crl) {
            continue;
        } else if (X509_STORE_add_crl(store, it->crl) != 1) {
            *errop  = "X509_STORE_add_crl";
            *errmsg = "failed to add CRL";
            goto DONE;
        }
    }

    if (X509_STORE_set_flags(store, X509_V_FLAG_CRL_CHECK |
                                        X509_V_FLAG_CRL_CHECK_ALL) != 1) {
        *errop  = "X509_STORE_set_flags";
        *errmsg = "failed to set CRL flags";
        goto DONE;
    }
    rc = 0;

DONE:
    if (inf) {
        sk_X509_INFO_pop_free(inf, X509_INFO_free);
    }
    if (bio) {
        BIO_free(bio);
    }
    return rc;
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

static void push_cache_key(lua_State *L, const client_opts_t *opts)
{
    luaL_Buffer buf;
    const char *alpn       = NULL;
    size_t alpn_len        = 0;
    unsigned char has_crls = opts->crls != NULL;

    if (lauxh_isref(opts->alpn_ref)) {
        lauxh_pushref(L, opts->alpn_ref);
        alpn = lua_tolstring(L, -1, &alpn_len);
    }
    luaL_buffinit(L, &buf);
    key_add_blob(&buf, "client", sizeof("client") - 1);
    key_add_blob(&buf, &opts->protocol, sizeof(opts->protocol));
    key_add_blob(&buf, &opts->cipher, sizeof(opts->cipher));
    key_add_blob(&buf, alpn, alpn_len);
    key_add_blob(&buf, &opts->cache_timeout, sizeof(opts->cache_timeout));
    key_add_blob(&buf, &opts->cache_size, sizeof(opts->cache_size));
    key_add_blob(&buf, &opts->verify_depth, sizeof(opts->verify_depth));
    key_add_optional(&buf, opts->cafile);
    key_add_optional(&buf, opts->capath);
    key_add_blob(&buf, &has_crls, sizeof(has_crls));
    key_add_blob(&buf, opts->crls, opts->crls_len);
    luaL_pushresult(&buf);
    if (alpn) {
        lua_remove(L, -2);
    }
}

static int new_lua(lua_State *L)
{
    static const optspec_t SPECS[] = {
        {"protocol",              check_opt_protocol     },
        {"cipher",                check_opt_cipher       },
        {"session_cache_timeout", check_opt_cache_timeout},
        {"session_cache_size",    check_opt_cache_size   },
        {"cache",                 check_opt_cache        },
        {"verify_depth",          check_opt_verify_depth },
        {"cafile",                check_opt_cafile       },
        {"capath",                check_opt_capath       },
        {"crls",                  check_opt_crls         },
    };
    client_opts_t opts = {
        .protocol      = 0, // "default"
        .cipher        = 0, // "default"
        .alpn_ref      = LUA_NOREF,
        .cache_timeout = 0,
        .cache_size    = SSL_SESSION_CACHE_MAX_SIZE_DEFAULT,
        .verify_depth  = -1,
        .cafile        = NULL,
        .capath        = NULL,
        .crls          = NULL,
        .crls_len      = 0,
    };
    tls_client_t *c       = NULL;
    tls_ssl_ctx_t *sslctx = NULL;
    const char *errop     = NULL;
    const char *errmsg    = NULL;
    int keyidx            = 0;

    luaL_checktype(L, 1, LUA_TTABLE);

    // discard stale errors from the thread-local queue so a failure below
    // reports only its own errors (read/write/handshake/shutdown do the
    // same)
    ERR_clear_error();

    // Parse scalar options first so a later validation error cannot leak the
    // temporary registry reference used for ALPN wire format.
    OPTSPEC_CHECK(L, 1, SPECS, &opts);
    lua_getfield(L, 1, "alpn");
    if (!lua_isnil(L, -1)) {
        check_opt_alpn(L, "alpn", &opts);
    }
    lua_pop(L, 1);

    if (opts.cache) {
        push_cache_key(L, &opts);
        keyidx = lua_gettop(L);
    }

    // create context
    c  = lua_newuserdata(L, sizeof(tls_client_t));
    *c = (tls_client_t){
        .ctx     = NULL,
        .sslctx  = NULL,
        .ref_ctx = LUA_NOREF,
    };
    // Keep the client finalizer active while constructing the owned context.
    lauxh_setmetatable(L, NET_TLS_CLIENT_MT);
    if ((sslctx = tls_cache_ctx_get(L, opts.cache, keyidx))) {
        goto READY;
    }
    sslctx = tls_ssl_ctx_new(L, TLS_client_method(),
                             opts.cache ? opts.cache->session_capacity : 0);
    c->ctx = sslctx->ctx;
    if (!c->ctx) {
        errop  = "SSL_CTX_new";
        errmsg = "failed to create SSL_CTX";
        goto FAIL;
    }

    // set mode
    SSL_CTX_clear_mode(c->ctx, SSL_MODE_AUTO_RETRY);
    SSL_CTX_set_mode(c->ctx, SSL_MODE_ENABLE_PARTIAL_WRITE);
    SSL_CTX_set_mode(c->ctx, SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);

    // set protocols
    if (tls_set_protocol_vers(c->ctx, opts.protocol) != 1) {
        errop  = "tls_set_protocol_vers";
        errmsg = "failed to set protocol version";
        goto FAIL;
    }

    // set cipher suite
    if (tls_set_cipher_suite(c->ctx, opts.cipher) != 1) {
        errop  = "tls_set_cipher_suite";
        errmsg = "failed to set cipher suite";
        goto FAIL;
    }

    // session settings
    // reject TLS 1.2 renegotiation: no consumer of this library drives
    // it, and the server-side stance of this library refuses it too
    SSL_CTX_set_options(c->ctx, SSL_OP_NO_RENEGOTIATION);
    if (opts.cache_timeout <= 0) {
        // disable session cache and session tickets
        SSL_CTX_set_session_cache_mode(c->ctx, SSL_SESS_CACHE_OFF);
        SSL_CTX_set_options(c->ctx, SSL_OP_NO_TICKET);
    } else {
        // enable session cache
        SSL_CTX_set_session_cache_mode(c->ctx, SSL_SESS_CACHE_CLIENT);
        SSL_CTX_set_timeout(c->ctx, (long)opts.cache_timeout);
        if (opts.cache_size > 0) {
            SSL_CTX_sess_set_cache_size(c->ctx, (long)opts.cache_size);
        }
        // note: SSL_CTX_set_num_tickets() is a server-side setting only;
        // it has no effect on a client context
    }

    // set default verify certificate locations
    if (SSL_CTX_set_default_verify_paths(c->ctx) != 1) {
        errop  = "SSL_CTX_set_default_verify_paths";
        errmsg = "failed to set default verify paths";
        goto FAIL;
    }

    // load the caller-specified trusted CA locations (all-or-nothing:
    // the SSL_CTX is immutable after construction)
    if (opts.cafile || opts.capath) {
        if (SSL_CTX_load_verify_locations(c->ctx, opts.cafile, opts.capath) !=
            1) {
            errop  = "SSL_CTX_load_verify_locations";
            errmsg = "failed to load verify locations";
            goto FAIL;
        }
    }

    if (opts.verify_depth >= 0) {
        SSL_CTX_set_verify_depth(c->ctx, (int)opts.verify_depth);
    }

    if (opts.crls &&
        load_crls(c->ctx, opts.crls, opts.crls_len, &errop, &errmsg) != 0) {
        goto FAIL;
    }

    // configure ALPN (OpenSSL copies the list internally)
    if (lauxh_isref(opts.alpn_ref)) {
        size_t len = 0;
        unsigned char *alpn;

        lauxh_pushref(L, opts.alpn_ref);
        alpn = (unsigned char *)lua_tolstring(L, -1, &len);
        if (SSL_CTX_set_alpn_protos(c->ctx, alpn, (unsigned int)len) != 0) {
            lua_pop(L, 1);
            errop  = "SSL_CTX_set_alpn_protos";
            errmsg = "failed to set ALPN protocols";
            goto FAIL;
        }
        lua_pop(L, 1);
    }

    tls_cache_ctx_put(L, opts.cache, keyidx, -1);

READY:
    c->sslctx  = sslctx;
    c->ctx     = sslctx->ctx;
    c->ref_ctx = lauxh_refat(L, -1);
    lua_pop(L, 1);

    // return net.tls.client userdata
    if (lauxh_isref(opts.alpn_ref)) {
        opts.alpn_ref = lauxh_unref(L, opts.alpn_ref);
    }
    return 1;

FAIL:
    if (lauxh_isref(opts.alpn_ref)) {
        opts.alpn_ref = lauxh_unref(L, opts.alpn_ref);
    }
    if (c) {
        c->sslctx = NULL;
        c->ctx    = NULL;
    }
    lua_pushnil(L);
    tls_push_error(L, errop, errmsg);
    return 2;
}

LUALIB_API int luaopen_net_tls_client(lua_State *L)
{
    struct luaL_Reg mmethod[] = {
        {"__gc",       gc_lua      },
        {"__tostring", tostring_lua},
        {NULL,         NULL        }
    };

    luaL_newmetatable(L, NET_TLS_CLIENT_MT);
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
