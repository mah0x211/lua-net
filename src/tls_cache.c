/*
 * Copyright (C) 2026 Masatoshi Fukunaga
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */

#include "tls_cache.h"
#include "optcheck.h"
#include <limits.h>
#include <stdint.h>

typedef struct {
    size_t ctx_capacity;
    size_t session_capacity;
} cache_opts_t;

static int check_capacity(lua_State *L, const char *name, size_t *capacity)
{
    lua_Integer value = 0;

    if (lua_type(L, -1) != LUA_TNUMBER) {
        return luaL_error(L, "opts.%s must be integer, got %s", name,
                          luaL_typename(L, -1));
    }
    value = lauxh_checkuinteger(L, -1);
    if ((uintmax_t)value > (uintmax_t)SIZE_MAX) {
        return luaL_error(L, "opts.%s is too large", name);
    }
    *capacity = (size_t)value;
    return 0;
}

static int check_ctx_capacity(lua_State *L, const char *name, void *data)
{
    cache_opts_t *opts = data;
    return check_capacity(L, name, &opts->ctx_capacity);
}

static int check_session_capacity(lua_State *L, const char *name, void *data)
{
    cache_opts_t *opts = data;
    return check_capacity(L, name, &opts->session_capacity);
}

static size_t count_sessions(lua_State *L, int ref)
{
    size_t count = 0;

    if (!lauxh_isref(ref)) {
        return 0;
    }
    lauxh_pushref(L, ref);
    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
        tls_ssl_ctx_t *ctx = lua_touserdata(L, -1);
        if (ctx) {
            count += ctx->ssl_sess_cache.ncached;
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
    return count;
}

static void clear_sessions(lua_State *L, int ref)
{
    if (!lauxh_isref(ref)) {
        return;
    }
    lauxh_pushref(L, ref);
    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
        tls_ssl_ctx_t *ctx = lua_touserdata(L, -1);
        if (ctx) {
            tls_cache_store_clear(L, &ctx->ssl_sess_cache);
        }
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
}

static int size_lua(lua_State *L)
{
    tls_cache_t *cache = luaL_checkudata(L, 1, NET_TLS_CACHE_MT);
    size_t nsessions   = count_sessions(L, cache->ssl_ctx_cache.ref_cache) +
                         count_sessions(L, cache->ssl_ctx_cache.ref_weak);

    lua_pushinteger(L, (lua_Integer)cache->ssl_ctx_cache.ncached);
    lua_pushinteger(L, (lua_Integer)nsessions);
    return 2;
}

static int clear_lua(lua_State *L)
{
    tls_cache_t *cache = luaL_checkudata(L, 1, NET_TLS_CACHE_MT);

    clear_sessions(L, cache->ssl_ctx_cache.ref_cache);
    clear_sessions(L, cache->ssl_ctx_cache.ref_weak);
    tls_cache_store_clear(L, &cache->ssl_ctx_cache);
    lua_pushboolean(L, 1);
    return 1;
}

static int tostring_lua(lua_State *L)
{
    luaL_checkudata(L, 1, NET_TLS_CACHE_MT);
    lua_pushfstring(L, NET_TLS_CACHE_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    tls_cache_t *cache = luaL_checkudata(L, 1, NET_TLS_CACHE_MT);

    tls_cache_store_dispose(L, &cache->ssl_ctx_cache);
    return 0;
}

static int new_lua(lua_State *L)
{
    static const optspec_t SPECS[] = {
        {"ctx_capacity",     check_ctx_capacity    },
        {"session_capacity", check_session_capacity},
    };
    cache_opts_t opts  = {0};
    tls_cache_t *cache = NULL;

    OPTSPEC_CHECK(L, 1, SPECS, &opts);

    cache  = lua_newuserdata(L, sizeof(*cache));
    *cache = (tls_cache_t){
        .session_capacity = opts.session_capacity,
    };
    lauxh_setmetatable(L, NET_TLS_CACHE_MT);
    tls_cache_store_init(L, &cache->ssl_ctx_cache, opts.ctx_capacity);
    return 1;
}

static int tls_ssl_ctx_gc_lua(lua_State *L)
{
    tls_ssl_ctx_t *ctx = luaL_checkudata(L, 1, NET_TLS_SSL_CTX_MT);

    if (ctx->ctx) {
        SSL_CTX_set_tlsext_servername_callback(ctx->ctx, NULL);
        SSL_CTX_set_tlsext_servername_arg(ctx->ctx, NULL);
        SSL_CTX_free(ctx->ctx);
        ctx->ctx = NULL;
    }
    tls_cache_store_dispose(L, &ctx->ssl_sess_cache);
    if (lauxh_isref(ctx->sni_callback_ref)) {
        ctx->sni_callback_ref = lauxh_unref(L, ctx->sni_callback_ref);
    }
    if (lauxh_isref(ctx->ref_alpn)) {
        ctx->ref_alpn = lauxh_unref(L, ctx->ref_alpn);
    }
    ctx->alpn     = NULL;
    ctx->alpn_len = 0;
    ctx->L        = NULL;
    return 0;
}

static int tls_ssl_session_gc_lua(lua_State *L)
{
    tls_ssl_session_t *item = luaL_checkudata(L, 1, NET_TLS_SSL_SESSION_MT);

    if (item->session) {
        SSL_SESSION_free(item->session);
        item->session = NULL;
    }
    return 0;
}

static void tls_ssl_ctx_init(lua_State *L)
{
    if (luaL_newmetatable(L, NET_TLS_SSL_CTX_MT)) {
        lua_pushcfunction(L, tls_ssl_ctx_gc_lua);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
}

static void tls_ssl_session_init(lua_State *L)
{
    if (luaL_newmetatable(L, NET_TLS_SSL_SESSION_MT)) {
        lua_pushcfunction(L, tls_ssl_session_gc_lua);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
}

LUALIB_API int luaopen_net_tls_cache(lua_State *L)
{
    static const struct luaL_Reg MMETHODS[] = {
        {"__gc",       gc_lua      },
        {"__tostring", tostring_lua},
        {NULL,         NULL        },
    };
    static const struct luaL_Reg METHODS[] = {
        {"clear", clear_lua},
        {"size",  size_lua },
        {NULL,    NULL     },
    };

    luaL_newmetatable(L, NET_TLS_CACHE_MT);
    for (const struct luaL_Reg *method = MMETHODS; method->name; method++) {
        lauxh_pushfn2tbl(L, method->name, method->func);
    }
    lua_newtable(L);
    for (const struct luaL_Reg *method = METHODS; method->name; method++) {
        lauxh_pushfn2tbl(L, method->name, method->func);
    }
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    tls_ssl_ctx_init(L);
    tls_ssl_session_init(L);
    lua_pushcfunction(L, new_lua);
    return 1;
}
