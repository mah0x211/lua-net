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
#include <limits.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509_vfy.h>

// set callback for ALPN (Application-Layer Protocol Negotiation) support
// SSL_CTX_set_alpn_select_cb(ctx->sslctx, alpn_select_cb, ctx);
// set callback for NPN (Next Protocol Negotiation) support
// SSL_CTX_set_next_protos_advertised_cb(ctx->sslctx, npn_advertise_cb, ctx);

static int set_crls(lua_State *L)
{
    tls_client_t *c          = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    size_t len               = 0;
    const char *crls         = luaL_checklstring(L, 2, &len);
    X509_STORE *store        = SSL_CTX_get_cert_store(c->ctx);
    BIO *bio                 = NULL;
    STACK_OF(X509_INFO) *inf = NULL;
    const char *errop        = NULL;
    const char *errmsg       = NULL;

    // BIO_new_mem_buf takes int; refuse >INT_MAX to prevent truncation.
    // Not exercised by tests: allocating a 2GB PEM in CI is impractical.
    if (len > INT_MAX) {
        errop  = "BIO_new_mem_buf";
        errmsg = "CRL PEM buffer exceeds INT_MAX";
        goto FAIL;
    }
    bio = BIO_new_mem_buf((void *)crls, (int)len);
    if (!bio) {
        errop  = "BIO_new_mem_buf";
        errmsg = "failed to create BIO";
        goto FAIL;
    }

    // read CRLs from PEM format
    inf = PEM_X509_INFO_read_bio(bio, NULL, NULL, NULL);
    if (!inf) {
        errop  = "PEM_X509_INFO_read_bio";
        errmsg = "failed to read CRLs";
        goto FAIL;
    }

    // Add CRLs to the store.  X509_STORE_add_crl's failure branch is not
    // covered from Lua: OpenSSL 3.x accepts duplicates, and other triggers
    // (internal malloc failure, specially crafted CRLs) are not reachable
    // from userspace.
    for (int i = 0; i < sk_X509_INFO_num(inf); i++) {
        X509_INFO *it = sk_X509_INFO_value(inf, i);
        if (!it->crl) {
            continue;
        } else if (X509_STORE_add_crl(store, it->crl) != 1) {
            errop  = "X509_STORE_add_crl";
            errmsg = "failed to add CRL";
            goto FAIL;
        }
    }

    // enable CRL checking for the entire certificate chain and also enable CRL
    // checking for leaf certificate
    if (X509_STORE_set_flags(store, X509_V_FLAG_CRL_CHECK |
                                        X509_V_FLAG_CRL_CHECK_ALL) != 1) {
        errop  = "X509_STORE_set_flags";
        errmsg = "failed to set CRL flags";
        goto FAIL;
    }

    sk_X509_INFO_pop_free(inf, X509_INFO_free);
    BIO_free(bio);
    lua_pushboolean(L, 1);
    return 1;

FAIL:
    if (inf) {
        sk_X509_INFO_pop_free(inf, X509_INFO_free);
    }
    if (bio) {
        BIO_free(bio);
    }
    lua_pushboolean(L, 0);
    tls_push_error(L, errop, errmsg);
    return 2;
}

static int load_verify_locations(lua_State *L)
{
    tls_client_t *c    = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    const char *cafile = lauxh_optstring(L, 2, NULL);
    const char *capath = lauxh_optstring(L, 3, NULL);

    if (!cafile && !capath) {
        return luaL_error(L, "either cafile or capath must be specified");
    }

    if (SSL_CTX_load_verify_locations(c->ctx, cafile, capath) != 1) {
        lua_pushboolean(L, 0);
        tls_push_error(L, "SSL_CTX_load_verify_locations",
                       "failed to load verify locations");
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int set_verify_depth_lua(lua_State *L)
{
    tls_client_t *c = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    int depth       = lauxh_checkuinteger(L, 2);
    SSL_CTX_set_verify_depth(c->ctx, depth);
    return 0;
}

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, NET_TLS_CLIENT_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    tls_client_t *c = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    SSL_CTX_free(c->ctx);
    return 0;
}

static int new_lua(lua_State *L)
{
    int protocol      = luaL_checkoption(L, 1, "default", TLS_PROTOCOLS);
    int cipher        = luaL_checkoption(L, 2, "default", TLS_CIPHER_SUITES);
    int cache_timeout = lauxh_optinteger(L, 4, 0);
    int cache_size = lauxh_optinteger(L, 5, SSL_SESSION_CACHE_MAX_SIZE_DEFAULT);
    int nalpn      = 0;
    tls_client_t *c    = NULL;
    const char *errop  = NULL;
    const char *errmsg = NULL;

    // check ALPN table parsing error
    nalpn = tls_check_alpn_table(L, 3);
    if (nalpn < 0) {
        errop  = "tls_check_alpn_table";
        errmsg = lua_tostring(L, -1);
        goto FAIL;
    }

    // create context
    c  = lua_newuserdata(L, sizeof(tls_client_t));
    *c = (tls_client_t){
        .ctx = NULL,
    };
    // set the metatable before creating the SSL_CTX: a later allocation
    // failure raises past this frame, and the __gc must then free the ctx.
    // With ctx NULL the __gc is a no-op.
    lauxh_setmetatable(L, NET_TLS_CLIENT_MT);
    c->ctx = SSL_CTX_new(TLS_client_method());
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
    if (tls_set_protocol_vers(c->ctx, protocol) != 1) {
        errop  = "tls_set_protocol_vers";
        errmsg = "failed to set protocol version";
        goto FAIL;
    }

    // set cipher suite
    if (tls_set_cipher_suite(c->ctx, cipher) != 1) {
        errop  = "tls_set_cipher_suite";
        errmsg = "failed to set cipher suite";
        goto FAIL;
    }

    // session settings
    if (cache_timeout <= 0) {
        // disable session cache and session tickets
        SSL_CTX_set_session_cache_mode(c->ctx, SSL_SESS_CACHE_OFF);
        SSL_CTX_set_options(c->ctx, SSL_OP_NO_TICKET);
        SSL_CTX_set_num_tickets(c->ctx, 0);
    } else {
        // enable session cache
        SSL_CTX_set_session_cache_mode(c->ctx, SSL_SESS_CACHE_CLIENT);
        SSL_CTX_set_timeout(c->ctx, cache_timeout);
        if (cache_size > 0) {
            SSL_CTX_sess_set_cache_size(c->ctx, cache_size);
        }
        SSL_CTX_set_num_tickets(c->ctx, 2);
    }

    // set default verify certificate locations
    if (SSL_CTX_set_default_verify_paths(c->ctx) != 1) {
        errop  = "SSL_CTX_set_default_verify_paths";
        errmsg = "failed to set default verify paths";
        goto FAIL;
    }

    // configure ALPN (OpenSSL copies the list internally)
    if (nalpn > 0) {
        size_t len          = 0;
        unsigned char *alpn = (unsigned char *)lua_tolstring(L, 3, &len);
        if (SSL_CTX_set_alpn_protos(c->ctx, alpn, (unsigned int)len) != 0) {
            errop  = "SSL_CTX_set_alpn_protos";
            errmsg = "failed to set ALPN protocols";
            goto FAIL;
        }
    }

    // return net.tls.client userdata
    return 1;

FAIL:
    if (c && c->ctx) {
        SSL_CTX_free(c->ctx);
        // prevent the pending __gc (the metatable is already set) from
        // double-freeing the ctx
        c->ctx = NULL;
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
    struct luaL_Reg method[] = {
        {"set_verify_depth",      set_verify_depth_lua },
        {"load_verify_locations", load_verify_locations},
        {"set_crls",              set_crls             },
        {NULL,                    NULL                 }
    };

    luaL_newmetatable(L, NET_TLS_CLIENT_MT);
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
