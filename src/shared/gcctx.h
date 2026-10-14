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

#ifndef NET_GCCTX_H
#define NET_GCCTX_H

#include <lua.h>
#include <stddef.h>

typedef struct net_gcctx net_gcctx_t;

/* Common header for all garbage-collected contexts.
 * How to construct a derived context:
 * 1. Define a structure that embeds `net_gcctx_t` as the first member.
 * 2. Implement a cleanup function that releases all owned resources.
 * 3. Allocate the context using `net_gcctx_new`, passing the cleanup function.
 * 4. Keep the userdata rooted until it is no longer needed.
 * 5. Call `net_gcctx_dispose` to release resources manually, or rely on the
 *    `__gc` metamethod for automatic cleanup.
 */
struct net_gcctx {
    void (*gc)(lua_State *L, net_gcctx_t *ctx);
};

/* Register the shared metatable before allocating any contexts. */
void net_gcctx_init(lua_State *L);

/* Allocate zeroed userdata and leave it on the stack. size must include
 * the common header as the first member. Keep it rooted until disposal
 * or ownership transfer. gc must not raise errors or yield. */
net_gcctx_t *net_gcctx_new(lua_State *L, size_t size,
                           void (*gc)(lua_State *L, net_gcctx_t *ctx));

/* Release owned resources once. Also used by the __gc metamethod. */
void net_gcctx_dispose(lua_State *L, net_gcctx_t *ctx);

/* Disable cleanup only after transferring all owned resources. */
void net_gcctx_disarm(net_gcctx_t *ctx);

#endif
