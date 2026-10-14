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

#include "gcctx.h"
#include <assert.h>
#include <lauxlib.h>
#include <string.h>

#define NET_GCCTX_MT "net.gcctx"

void net_gcctx_dispose(lua_State *L, net_gcctx_t *ctx)
{
    void (*gc)(lua_State *, net_gcctx_t *) = ctx->gc;

    ctx->gc = NULL;
    if (gc) {
        gc(L, ctx);
    }
}

void net_gcctx_disarm(net_gcctx_t *ctx)
{
    ctx->gc = NULL;
}

net_gcctx_t *net_gcctx_new(lua_State *L, size_t size,
                           void (*gc)(lua_State *L, net_gcctx_t *ctx))
{
    assert(size >= sizeof(net_gcctx_t));

    net_gcctx_t *ctx = lua_newuserdata(L, size);
    memset(ctx, 0, size);
    ctx->gc = gc;
    luaL_getmetatable(L, NET_GCCTX_MT);
    lua_setmetatable(L, -2);
    return ctx;
}

static int gc_lua(lua_State *L)
{
    net_gcctx_dispose(L, luaL_checkudata(L, 1, NET_GCCTX_MT));
    return 0;
}

void net_gcctx_init(lua_State *L)
{
    luaL_newmetatable(L, NET_GCCTX_MT);
    lua_pushcfunction(L, gc_lua);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);
}
