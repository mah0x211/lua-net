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

#ifndef _GNU_SOURCE
# define _GNU_SOURCE
#endif

#include "pcall.h"
#include "lauxhlib.h"
#include <assert.h>
#include <lauxlib.h>

typedef struct {
    lua_CFunction fn;
    void *arg;
    int nresults;
    int status;
#if LUA_VERSION_NUM == 501
    lua_State *retvals;
    int ref;
#endif
} net_pcall_ctx_t;

static int net_pcall_hook(lua_State *L)
{
    net_pcall_ctx_t *ctx = lua_touserdata(L, 1);

    // Reserve on the protected state, including room for the outer results.
    luaL_checkstack(L, ctx->nresults + 2, "too many results");
#if LUA_VERSION_NUM == 501
    if (ctx->nresults) {
        ctx->retvals = lua_newthread(L);
        ctx->ref     = luaL_ref(L, LUA_REGISTRYINDEX);
    }
#endif

    lua_pushcfunction(L, ctx->fn);
    lua_pushlightuserdata(L, ctx->arg);
    int status = lua_pcall(L, 1, ctx->nresults, 0);
    if (status != LUA_OK) {
        // Stringification stays inside the outer protected call. If it fails,
        // propagate that error without retrying the metamethod.
        if (lua_type(L, -1) != LUA_TSTRING) {
            lauxh_tostr(L, -1);
        }
        // Preserve the original status when rethrowing a converted error.
        ctx->status = status;
        return lua_error(L);
    }

#if LUA_VERSION_NUM == 501
    // An empty new thread already has LUA_MINSTACK slots available.
    if (ctx->nresults) {
        lua_xmove(L, ctx->retvals, ctx->nresults);
    }
    return 0;
#else
    return ctx->nresults;
#endif
}

#if LUA_VERSION_NUM == 501

int net_pcall_ex(lua_State *L, lua_CFunction fn, void *arg, int nresults)
{
    int status          = 0;
    net_pcall_ctx_t ctx = {
        .fn       = fn,
        .arg      = arg,
        .nresults = nresults,
        .ref      = LUA_NOREF,
    };

    assert(nresults >= 0 && nresults <= LUA_MINSTACK);

    status = lua_cpcall(L, net_pcall_hook, &ctx);
    if (ctx.status != LUA_OK) {
        status = ctx.status;
    } else if (status == LUA_OK && nresults) {
        // Physical capacity was reserved in the hook. Update the original
        // frame's limit without allocating before moving results back.
        if (!lua_checkstack(L, nresults)) {
            lua_pushliteral(L, "not enough memory");
            status = LUA_ERRMEM;
        } else {
            lua_xmove(ctx.retvals, L, nresults);
        }
    }
    if (ctx.ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, ctx.ref);
    }
    return status;
}

#else

int net_pcall_ex(lua_State *L, lua_CFunction fn, void *arg, int nresults)
{
    net_pcall_ctx_t ctx = {
        .fn       = fn,
        .arg      = arg,
        .nresults = nresults,
    };
    assert(nresults >= 0 && nresults <= LUA_MINSTACK);
    if (!lua_checkstack(L, nresults + 2)) {
        lua_pushliteral(L, "not enough memory");
        return LUA_ERRMEM;
    }
    // A zero-upvalue C function does not allocate in Lua 5.2 and later.
    lua_pushcfunction(L, net_pcall_hook);
    lua_pushlightuserdata(L, &ctx);
    int status = lua_pcall(L, 1, nresults, 0);
    return ctx.status != LUA_OK ? ctx.status : status;
}

#endif

int net_pcall(lua_State *L, lua_CFunction fn, void *arg)
{
    return net_pcall_ex(L, fn, arg, 0);
}
