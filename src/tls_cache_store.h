/*
 * Copyright (C) 2026 Masatoshi Fukunaga
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
 * USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#ifndef net_tls_cache_store_h
#define net_tls_cache_store_h

#include "lauxhlib.h"
#include <lauxlib.h>
#include <limits.h>
#include <lua.h>
#include <stddef.h>

typedef struct {
    size_t capacity;
    size_t ncached;
    int ref_cache;
    int ref_weak;
} tls_ssl_store_t;

static inline int tls_absindex(lua_State *L, int idx)
{
    if (idx > 0 || idx <= LUA_REGISTRYINDEX) {
        return idx;
    }
    return lua_gettop(L) + idx + 1;
}

static inline void tls_ssl_store_init(lua_State *L, tls_ssl_store_t *store,
                                      size_t capacity)
{
    *store = (tls_ssl_store_t){
        .capacity  = capacity,
        .ncached   = 0,
        .ref_cache = LUA_NOREF,
        .ref_weak  = LUA_NOREF,
    };
    if (capacity == 0) {
        return;
    }

    lua_createtable(L, 0, (int)(capacity > INT_MAX ? INT_MAX : capacity));
    store->ref_cache = lauxh_ref(L);

    lua_newtable(L);
    lua_createtable(L, 0, 1);
    lua_pushliteral(L, "v");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    store->ref_weak = lauxh_ref(L);
}

static inline void tls_ssl_store_dispose(lua_State *L, tls_ssl_store_t *store)
{
    if (lauxh_isref(store->ref_cache)) {
        store->ref_cache = lauxh_unref(L, store->ref_cache);
    }
    if (lauxh_isref(store->ref_weak)) {
        store->ref_weak = lauxh_unref(L, store->ref_weak);
    }
    store->ncached = 0;
}

static inline void tls_ssl_store_clear(lua_State *L, tls_ssl_store_t *store)
{
    size_t capacity = store->capacity;

    tls_ssl_store_dispose(L, store);
    tls_ssl_store_init(L, store, capacity);
}

/* A weak hit is promoted and the value remains on the Lua stack on success. */
static inline int tls_ssl_store_get(lua_State *L, tls_ssl_store_t *store,
                                    const char *key, size_t keylen);

/* Store the value at value_idx. Nothing is retained when capacity is zero. */
static inline void tls_ssl_store_put(lua_State *L, tls_ssl_store_t *store,
                                     const char *key, size_t keylen,
                                     int value_idx)
{
    int value = tls_absindex(L, value_idx);
    int strong;
    int exists;

    if (store->capacity == 0) {
        return;
    }

    lauxh_pushref(L, store->ref_cache);
    strong = lua_gettop(L);
    lua_pushlstring(L, key, keylen);
    lua_rawget(L, strong);
    exists = !lua_isnil(L, -1);
    lua_pop(L, 1);

    if (!exists && store->ncached >= store->capacity) {
        lua_pushnil(L);
        if (lua_next(L, strong) != 0) {
            int oldkey = lua_gettop(L) - 1;
            int oldval = lua_gettop(L);

            lauxh_pushref(L, store->ref_weak);
            lua_pushvalue(L, oldkey);
            lua_pushvalue(L, oldval);
            lua_rawset(L, -3);
            lua_pop(L, 1);

            lua_pushvalue(L, oldkey);
            lua_pushnil(L);
            lua_rawset(L, strong);
            lua_pop(L, 2);
            store->ncached--;
        }
    }

    lua_pushlstring(L, key, keylen);
    lua_pushvalue(L, value);
    lua_rawset(L, strong);
    if (!exists) {
        store->ncached++;
    }
    lua_pop(L, 1);

    /* A promoted or replaced value must not remain in the weak table. */
    lauxh_pushref(L, store->ref_weak);
    lua_pushlstring(L, key, keylen);
    lua_pushnil(L);
    lua_rawset(L, -3);
    lua_pop(L, 1);
}

static inline int tls_ssl_store_get(lua_State *L, tls_ssl_store_t *store,
                                    const char *key, size_t keylen)
{
    if (store->capacity == 0) {
        return 0;
    }

    lauxh_pushref(L, store->ref_cache);
    lua_pushlstring(L, key, keylen);
    lua_rawget(L, -2);
    if (!lua_isnil(L, -1)) {
        lua_remove(L, -2);
        return 1;
    }
    lua_pop(L, 2);

    lauxh_pushref(L, store->ref_weak);
    lua_pushlstring(L, key, keylen);
    lua_rawget(L, -2);
    if (!lua_isnil(L, -1)) {
        lua_remove(L, -2);
        tls_ssl_store_put(L, store, key, keylen, -1);
        return 1;
    }
    lua_pop(L, 2);
    return 0;
}

#endif /* net_tls_cache_store_h */
