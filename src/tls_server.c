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

#include "tls.h"

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, NET_TLS_SERVER_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    tls_server_t *s = luaL_checkudata(L, 1, NET_TLS_SERVER_MT);
    SSL_CTX_free(s->ctx);
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
    lua_Integer sess_timout = luaL_optinteger(L, 5, 300);
    lua_Integer sess_cache  = luaL_optinteger(L, 6, 1024 * 20);
    tls_server_t *s         = lua_newuserdata(L, sizeof(tls_server_t));
    const char *errop       = NULL;
    const char *errmsg      = NULL;

    // create context
    s->L   = L;
    s->ctx = SSL_CTX_new(TLS_server_method());
    if (!s->ctx) {
        errop  = "SSL_CTX_new";
        errmsg = "failed to create SSL_CTX";
        goto FAIL;
    }

    // set certificate
    if (SSL_CTX_use_certificate_file(s->ctx, cert, SSL_FILETYPE_PEM) != 1) {
        errop  = "SSL_CTX_use_certificate_file";
        errmsg = "failed to load certificate file";
        goto FAIL;
    }

    // set private key
    if (SSL_CTX_use_PrivateKey_file(s->ctx, key, SSL_FILETYPE_PEM) != 1) {
        errop  = "SSL_CTX_use_PrivateKey_file";
        errmsg = "failed to load private key file";
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
    SSL_CTX_set_options(s->ctx, SSL_OP_CIPHER_SERVER_PREFERENCE);

    lauxh_setmetatable(L, NET_TLS_SERVER_MT);
    return 1;

FAIL:
    if (s->ctx) {
        SSL_CTX_free(s->ctx);
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
        {NULL, NULL}
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
