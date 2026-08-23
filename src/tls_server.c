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
#include "tls.h"
// depend
#include "lauxhlib.h"
// lua
#include <lauxlib.h>
// system
#include <arpa/inet.h>
#include <netinet/in.h>
#include <openssl/ssl.h>
#include <stdio.h>

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

    return SSL_TLSEXT_ERR_OK;
}

static int sni_callback_closure(lua_State *L)
{
    int narg = lua_tointeger(L, lua_upvalueindex(1));

    lua_settop(L, 1);
    // push callback function and arguments
    for (int i = 0; i <= narg; i++) {
        lua_pushvalue(L, lua_upvalueindex(2 + i));
    }
    // push the server name argument from sni_callback() function
    lua_pushvalue(L, 1);
    lua_call(L, narg + 1, 1);
    // callback function must return tls_server_t* or nil
    if (!lua_isnoneornil(L, 2)) {
        lua_insert(L, 1);
        lua_settop(L, 1);
        luaL_checkudata(L, 1, NET_TLS_SERVER_MT);
    }
    return 1;
}

static int set_sni_callback_lua(lua_State *L)
{
    tls_server_t *s = luaL_checkudata(L, 1, NET_TLS_SERVER_MT);

    if (lua_isfunction(L, 2)) {
        int narg = lua_gettop(L);
        lua_pushinteger(L, narg - 2);
        lua_insert(L, 2);
        lua_pushcclosure(L, sni_callback_closure, narg);

        // remove previous reference
        s->sni_callback_ref = lauxh_unref(L, s->sni_callback_ref);
        s->sni_callback_ref = lauxh_ref(L);

        // set callback for SNI extension (Server Name Indication) support
        SSL_CTX_set_tlsext_servername_callback(s->ctx, sni_callback);
        SSL_CTX_set_tlsext_servername_arg(s->ctx, s);
        return 0;
    } else if (lua_isnil(L, 2)) {
        // remove previous reference
        SSL_CTX_set_tlsext_servername_callback(s->ctx, NULL);
        SSL_CTX_set_tlsext_servername_arg(s->ctx, NULL);
        s->sni_callback_ref = lauxh_unref(L, s->sni_callback_ref);
        return 0;
    }

    return lauxh_argerror(L, 2, "function or nil expected, got %s",
                          luaL_typename(L, 2));
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
    return SSL_TLSEXT_ERR_NOACK;
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
    SSL_CTX_sess_set_cache_size(ctx, cache_size);
    SSL_CTX_set_options(ctx, SSL_OP_NO_TICKET);
}

static int new_lua(lua_State *L)
{
    const char *cert = luaL_checkstring(L, 1);
    const char *key  = luaL_checkstring(L, 2);
    int protocol     = luaL_checkoption(L, 3, "default", TLS_PROTOCOLS);
    int cipher_suite = luaL_checkoption(L, 4, "default", TLS_CIPHER_SUITES);
    int nalpn        = 0;
    lua_Integer sess_timout   = luaL_optinteger(L, 6, 300);
    lua_Integer sess_cache    = luaL_optinteger(L, 7, 1024 * 20);
    int prefer_client_ciphers = lauxh_optboolean(L, 8, 0);
    tls_server_t *s           = NULL;
    const char *errop         = NULL;
    const char *errmsg        = NULL;

    // check ALPN table argument
    nalpn = tls_check_alpn_table(L, 5);
    if (nalpn < 0) {
        errop  = "tls_check_alpn_table";
        errmsg = lua_tostring(L, -1);
        goto FAIL;
    }

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
    if (SSL_CTX_use_certificate_chain_file(s->ctx, cert) != 1) {
        errop  = "SSL_CTX_use_certificate_chain_file";
        errmsg = "failed to load certificate chain file";
        goto FAIL;
    }

    // set private key
    if (SSL_CTX_use_PrivateKey_file(s->ctx, key, SSL_FILETYPE_PEM) != 1) {
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
    if (tls_set_protocol_vers(s->ctx, protocol) != 1) {
        errop  = "tls_set_protocol_vers";
        errmsg = "failed to set protocol version";
        goto FAIL;
    }

    // set cipher suite
    if (tls_set_cipher_suite(s->ctx, cipher_suite) != 1) {
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

    // set session configuration
    set_session_conf(s->ctx, sess_timout, sess_cache);
    // prefer server cipher suites over client cipher suites
    if (!prefer_client_ciphers) {
        SSL_CTX_set_options(s->ctx, SSL_OP_CIPHER_SERVER_PREFERENCE);
    }

    // configure ALPN (Application-Layer Protocol Negotiation)
    if (nalpn > 0) {
        s->alpn     = (unsigned char *)lua_tolstring(L, 5, &s->alpn_len);
        s->alpn_len = (unsigned int)s->alpn_len;
        s->ref_alpn = lauxh_refat(L, 5);
        SSL_CTX_set_alpn_select_cb(s->ctx, alpn_select_cb, s);
    }

    return 1;

FAIL:
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
    struct luaL_Reg method[] = {
        {"set_sni_callback", set_sni_callback_lua},
        {NULL,               NULL                }
    };

    luaL_newmetatable(L, NET_TLS_SERVER_MT);
    for (struct luaL_Reg *ptr = mmethod; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    lua_newtable(L);
    for (struct luaL_Reg *ptr = method; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    // initialize
    tls_init(L);

    lua_pushcfunction(L, new_lua);
    return 1;
}
