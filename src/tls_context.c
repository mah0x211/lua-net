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

static int handshake_lua(lua_State *L)
{
    tls_ctx_t *ctx = luaL_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    int rv         = 0;

    if (!ctx->handshake_cb) {
        lua_pushboolean(L, 1);
        return 1;
    }

    ERR_clear_error();
    rv = ctx->handshake_cb(ctx->ssl);
    if (rv != 1) {
        int err = SSL_get_error(ctx->ssl, rv);
        switch (err) {
        case SSL_ERROR_WANT_READ:
        case SSL_ERROR_WANT_WRITE:
            lua_pushboolean(L, 0);
            lua_pushnil(L);
            lua_pushinteger(L, err);
            return 3;

        case SSL_ERROR_ZERO_RETURN:
            // connection closed
            return 0;
        }

        // error occurred
        lua_pushboolean(L, 0);
        if (ctx->handshake_cb == SSL_connect) {
            tls_push_error(L, "SSL_connect",
                           "failed to initiate SSL/TLS handshake with server");
        } else {
            tls_push_error(L, "SSL_accept",
                           "failed to initiate SSL/TLS handshake with client");
        }
        return 2;
    }

    // handshake success
    ctx->handshake_cb = NULL;
    lua_pushboolean(L, 1);
    return 1;
}

static int write_lua(lua_State *L)
{
    tls_ctx_t *ctx  = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    size_t len      = 0;
    const char *buf = lauxh_checklstring(L, 2, &len);
    ssize_t rv      = SSL_write(ctx->ssl, buf, len);

    if (rv <= 0) {
        int err = SSL_get_error(ctx->ssl, rv);
        switch (err) {
        case SSL_ERROR_WANT_READ:
        case SSL_ERROR_WANT_WRITE:
            lua_pushinteger(L, 0);
            lua_pushnil(L);
            lua_pushinteger(L, err);
            return 3;

        case SSL_ERROR_ZERO_RETURN:
            // connection closed
            return 0;
        }

        // error occurred
        lua_pushnil(L);
        tls_push_error(L, "SSL_write", "failed to write data");
        return 2;
    }

    lua_pushinteger(L, rv);
    if ((size_t)rv == len) {
        return 1;
    }
    // not all data was written
    lua_pushnil(L);
    lua_pushinteger(L, SSL_ERROR_WANT_WRITE);
    return 3;
}

static int read_lua(lua_State *L)
{
    tls_ctx_t *ctx     = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    lua_Integer bufsiz = lauxh_optinteger(L, 2, BUFSIZ);
    void *buf          = lua_newuserdata(L, (bufsiz < 0) ? BUFSIZ : bufsiz);
    ssize_t rv         = SSL_read(ctx->ssl, buf, bufsiz);

    if (rv <= 0) {
        int err = SSL_get_error(ctx->ssl, rv);
        switch (err) {
        case SSL_ERROR_WANT_READ:
        case SSL_ERROR_WANT_WRITE:
            lua_pushnil(L);
            lua_pushnil(L);
            lua_pushinteger(L, err);
            return 3;

        case SSL_ERROR_ZERO_RETURN:
            // connection closed
            return 0;
        }

        // error occurred
        lua_pushnil(L);
        tls_push_error(L, "SSL_read", "failed to read data");
        return 2;
    }

    lua_pushlstring(L, buf, rv);
    return 1;
}

static int close_lua(lua_State *L)
{
    tls_ctx_t *ctx     = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    SSL *ssl           = ctx->ssl;
    const char *errop  = NULL;
    const char *errmsg = NULL;

    if (!ssl) {
        lua_pushboolean(L, 1);
        return 1;
    }

    if (!ctx->handshake_cb) {
        // SSL context should be gracefully shutdown
        int rv = SSL_shutdown(ssl);
        if (rv < 0) {
            rv = SSL_get_error(ctx->ssl, rv);
            switch (rv) {
            case SSL_ERROR_WANT_READ:
            case SSL_ERROR_WANT_WRITE:
                lua_pushboolean(L, 0);
                lua_pushnil(L);
                lua_pushinteger(L, rv);
                return 3;

            default:
                errop  = "SSL_shutdown";
                errmsg = "failed to shutdown SSL context";
            }
        }
    }
    // free ssl context and server reference
    ctx->ssl          = NULL;
    ctx->handshake_cb = NULL;
    SSL_free(ssl);
    ctx->parent_ref = lauxh_unref(L, ctx->parent_ref);

    lua_pushboolean(L, 1);
    if (!errop) {
        return 1;
    }
    // error occurred during SSL_shutdown
    tls_push_error(L, errop, errmsg);
    return 2;
}

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, NET_TLS_CONTEXT_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    tls_ctx_t *ctx = luaL_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    if (ctx->ssl) {
        SSL_free(ctx->ssl);
        lauxh_unref(L, ctx->parent_ref);
    }
    return 0;
}

static int accept_lua(lua_State *L)
{
    tls_server_t *s    = luaL_checkudata(L, 1, NET_TLS_SERVER_MT);
    int fd             = lauxh_checkinteger(L, 2);
    tls_ctx_t *ctx     = lua_newuserdata(L, sizeof(tls_ctx_t));
    const char *errop  = NULL;
    const char *errmsg = NULL;
    unsigned long err  = 0;

    ctx->handshake_cb = SSL_accept;
    ctx->ssl          = SSL_new(s->ctx);
    if (!ctx->ssl) {
        errop  = "SSL_new";
        errmsg = "failed to create SSL context";
    } else if (SSL_set_fd(ctx->ssl, fd) != 1) {
        errop  = "SSL_set_fd";
        errmsg = "failed to set file descriptor";
    } else {
        lauxh_setmetatable(L, NET_TLS_CONTEXT_MT);
        ctx->parent_ref = lauxh_refat(L, 1);
        return 1;
    }

    if (ctx->ssl) {
        SSL_free(ctx->ssl);
    }
    // error occurred
    lua_pushnil(L);
    tls_push_error(L, errop, errmsg);
    return 2;
}

static int noverify_time_cb(int preverify_ok, X509_STORE_CTX *x509_ctx)
{
    if (preverify_ok == 0) {
        switch (X509_STORE_CTX_get_error(x509_ctx)) {
        case X509_V_ERR_CERT_HAS_EXPIRED:
        case X509_V_ERR_CERT_NOT_YET_VALID:
            // ignore expired certificate error
            return 1;
        }
    }
    return preverify_ok;
}

static int connect_lua(lua_State *L)
{
    tls_client_t *c        = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    int fd                 = lauxh_checkinteger(L, 2);
    size_t len             = 0;
    const char *servername = luaL_optlstring(L, 3, NULL, &len);
    int noverify_name      = lauxh_optboolean(L, 4, 0);
    int noverify_time      = lauxh_optboolean(L, 5, 0);
    int noverify_cert      = lauxh_optboolean(L, 6, 0);
    tls_ctx_t *ctx         = lua_newuserdata(L, sizeof(tls_ctx_t));
    union {
        struct in_addr ip4;
        struct in6_addr ip6;
    } addr             = {0};
    const char *errop  = NULL;
    const char *errmsg = NULL;

    ctx->handshake_cb = SSL_connect;
    ctx->ssl          = SSL_new(c->ctx);
    if (!ctx->ssl) {
        errop  = "SSL_new";
        errmsg = "failed to create SSL context";
        goto FAIL;
    } else if (SSL_set_fd(ctx->ssl, fd) != 1) {
        errop  = "SSL_set_fd";
        errmsg = "failed to set file descriptor";
        goto FAIL;
    } else if (SSL_set_app_data(ctx->ssl, c) != 1) {
        errop  = "SSL_set_app_data";
        errmsg = "failed to set app data";
        goto FAIL;
    }

    if (len && inet_pton(AF_INET, servername, &addr) != 1 &&
        inet_pton(AF_INET6, servername, &addr) != 1) {
        // Server Name Indication (SNI) support
        if (SSL_set_tlsext_host_name(ctx->ssl, servername) != 1) {
            errop  = "SSL_set_tlsext_host_name";
            errmsg = "failed to set server name indication (SNI)";
            goto FAIL;
        }
        // hostname verification
        if (!noverify_name && SSL_set1_host(ctx->ssl, servername) != 1) {
            errop  = "SSL_set1_host";
            errmsg = "failed to set hostname for verification";
            goto FAIL;
        }
    }

    if (noverify_cert) {
        // ignore server certificate error
        SSL_set_verify(ctx->ssl, SSL_VERIFY_NONE, NULL);
    } else if (noverify_time) {
        // ignore server certificate expired error by callback
        SSL_set_verify(ctx->ssl, SSL_VERIFY_PEER, noverify_time_cb);
    } else {
        // verify server certificate
        SSL_set_verify(ctx->ssl, SSL_VERIFY_PEER, NULL);
    }

    lauxh_setmetatable(L, NET_TLS_CONTEXT_MT);
    ctx->parent_ref = lauxh_refat(L, 1);
    return 1;

FAIL:
    // error occurred
    if (ctx->ssl) {
        SSL_free(ctx->ssl);
    }
    lua_pushnil(L);
    tls_push_error(L, errop, errmsg);
    return 2;
}

LUALIB_API int luaopen_net_tls_context(lua_State *L)
{
    struct luaL_Reg mmethod[] = {
        {"__gc",       gc_lua      },
        {"__tostring", tostring_lua},
        {NULL,         NULL        }
    };
    struct luaL_Reg method[] = {
        {"read",      read_lua     },
        {"write",     write_lua    },
        {"close",     close_lua    },
        {"handshake", handshake_lua},
        {NULL,        NULL         }
    };

    luaL_newmetatable(L, NET_TLS_CONTEXT_MT);
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

    lua_createtable(L, 0, 4);
    lauxh_pushfn2tbl(L, "accept", accept_lua);
    lauxh_pushfn2tbl(L, "connect", connect_lua);
    // add constants
    lauxh_pushint2tbl(L, "WANT_READ", SSL_ERROR_WANT_READ);
    lauxh_pushint2tbl(L, "WANT_WRITE", SSL_ERROR_WANT_WRITE);
    return 1;
}
