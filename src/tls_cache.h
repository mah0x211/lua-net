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

#ifndef net_tls_cache_h
#define net_tls_cache_h

#include "tls_cache_store.h"
#include <lauxlib.h>
#include <lua.h>
#include <openssl/ssl.h>
#include <stddef.h>
#include <time.h>

#define NET_TLS_CACHE_MT       "net.tls.cache"
#define NET_TLS_SSL_CTX_MT     "net.tls.ssl_ctx"
#define NET_TLS_SSL_SESSION_MT "net.tls.ssl_session"

typedef struct {
    SSL_SESSION *session;
} tls_ssl_session_t;

typedef struct {
    lua_State *L;
    SSL_CTX *ctx;
    tls_cache_store_t ssl_sess_cache;
    int sni_callback_ref;
    int ref_alpn;
    unsigned char *alpn;
    size_t alpn_len;
} tls_ssl_ctx_t;

typedef struct {
    tls_cache_store_t ssl_ctx_cache;
    size_t session_capacity;
} tls_cache_t;

static inline void tls_cache_loadlib(lua_State *L)
{
    lua_getglobal(L, "require");
    lua_pushliteral(L, "net.tls.cache");
    lua_call(L, 1, 1);
    lua_pop(L, 1);
}

static inline tls_ssl_ctx_t *
tls_ssl_ctx_new(lua_State *L, const SSL_METHOD *method, tls_cache_t *cache)
{
    tls_ssl_ctx_t *ctx      = lua_newuserdata(L, sizeof(*ctx));
    size_t session_capacity = cache ? cache->session_capacity : 0;

    *ctx = (tls_ssl_ctx_t){
        .ctx              = NULL,
        .sni_callback_ref = LUA_NOREF,
        .ref_alpn         = LUA_NOREF,
    };
    luaL_getmetatable(L, NET_TLS_SSL_CTX_MT);
    if (lua_isnil(L, -1)) {
        luaL_error(L, "net.tls.cache is not initialized");
    }
    lua_setmetatable(L, -2);
    tls_cache_store_init(L, &ctx->ssl_sess_cache, session_capacity);
    ctx->ctx = SSL_CTX_new(method);
    return ctx;
}

/* On a hit, leave the context userdata on the Lua stack for the caller. */
static inline tls_ssl_ctx_t *
tls_cache_ssl_ctx_get(lua_State *L, tls_cache_t *cache, int keyidx)
{
    size_t keylen;
    const char *key;

    if (!cache) {
        return NULL;
    }
    key = lua_tolstring(L, keyidx, &keylen);
    if (!tls_cache_store_get(L, &cache->ssl_ctx_cache, key, keylen)) {
        return NULL;
    }
    return lua_touserdata(L, -1);
}

static inline void tls_cache_ssl_ctx_put(lua_State *L, tls_cache_t *cache,
                                         int keyidx, int ctxidx)
{
    size_t keylen;
    const char *key;

    if (!cache) {
        return;
    }
    key = lua_tolstring(L, keyidx, &keylen);
    tls_cache_store_put(L, &cache->ssl_ctx_cache, key, keylen, ctxidx);
}

static inline int tls_cache_ssl_sess_enabled(const tls_ssl_ctx_t *ctx)
{
    return ctx && ctx->ssl_sess_cache.capacity > 0;
}

/*
 * Move one owned session reference from a GC-managed owner into the cache.
 * Lua errors before the transfer leave the reference in *owned_session.
 */
static inline void tls_cache_ssl_sess_put(lua_State *L, tls_ssl_ctx_t *ctx,
                                          const char *key, size_t keylen,
                                          SSL_SESSION **owned_session)
{
    tls_ssl_session_t *item;
    SSL_SESSION *session = owned_session ? *owned_session : NULL;

    if (!session) {
        return;
    }
    if (!tls_cache_ssl_sess_enabled(ctx) || !SSL_SESSION_has_ticket(session) ||
        !SSL_SESSION_is_resumable(session)) {
        *owned_session = NULL;
        SSL_SESSION_free(session);
        return;
    }

    item          = lua_newuserdata(L, sizeof(*item));
    item->session = NULL;
    luaL_getmetatable(L, NET_TLS_SSL_SESSION_MT);
    if (lua_isnil(L, -1)) {
        luaL_error(L, "net.tls.cache is not initialized");
    }
    lua_setmetatable(L, -2);
    item->session  = session;
    *owned_session = NULL;
    tls_cache_store_put(L, &ctx->ssl_sess_cache, key, keylen, -1);
    lua_pop(L, 1);
}

/* Return one owned session reference, discarding stale or unusable entries. */
static inline SSL_SESSION *tls_cache_ssl_sess_take(lua_State *L,
                                                   tls_ssl_ctx_t *ctx,
                                                   const char *key,
                                                   size_t keylen)
{
    tls_ssl_session_t *item;
    SSL_SESSION *session;
    time_t now;
    time_t started;
    long timeout;
    double age;

    if (!tls_cache_ssl_sess_enabled(ctx) ||
        !tls_cache_store_take(L, &ctx->ssl_sess_cache, key, keylen)) {
        return NULL;
    }
    item          = luaL_checkudata(L, -1, NET_TLS_SSL_SESSION_MT);
    session       = item->session;
    item->session = NULL;
    lua_pop(L, 1);

    now = time(NULL);
#if OPENSSL_VERSION_NUMBER >= 0x30400000L
    started = SSL_SESSION_get_time_ex(session);
#else
    started = (time_t)SSL_SESSION_get_time(session);
#endif
    timeout = SSL_SESSION_get_timeout(session);
    age     = now == (time_t)-1 ? -1 : difftime(now, started);
    if (age < 0 || timeout <= 0 || age >= (double)timeout ||
        !SSL_SESSION_has_ticket(session) ||
        !SSL_SESSION_is_resumable(session)) {
        SSL_SESSION_free(session);
        return NULL;
    }
    return session;
}

#endif /* net_tls_cache_h */
