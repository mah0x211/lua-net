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
#include "net_pcall.h"
#include <assert.h>
#include <lauxlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    size_t blocks;
    size_t allocations;
    size_t fail_after;
} allocator_t;

static void *allocate(void *ud, void *ptr, size_t oldsize, size_t size)
{
    allocator_t *a = ud;
    void *result;
    int is_new = ptr == NULL;

    if (!size) {
        if (ptr) {
            a->blocks--;
        }
        free(ptr);
        return NULL;
    }
    if (!ptr || size > oldsize) {
        a->allocations++;
        // Keep failing so Lua's emergency GC cannot mask the fault.
        if (a->fail_after && a->allocations >= a->fail_after) {
            return NULL;
        }
    }
    result = realloc(ptr, size);
    if (result && is_new) {
        a->blocks++;
    }
    return result;
}

static int allocate_lua(lua_State *L)
{
    int *completed = lua_touserdata(L, 1);
    char text[512];
    memset(text, 'x', sizeof(text));
    lua_newuserdata(L, sizeof(text));
    lua_createtable(L, 0, 8);
    lua_pushlstring(L, text, sizeof(text));
    lua_setfield(L, -2, "text");
    *completed = 1;
    return 2; // Results must not leak into the caller's stack.
}

static int error_lua(lua_State *L)
{
    lua_pushlightuserdata(L, lua_touserdata(L, 1));
    return lua_error(L); // A non-string error needs no conversion.
}

static int nested_lua(lua_State *L)
{
    void *arg = lua_touserdata(L, 1);
    assert(net_pcall(L, error_lua, arg) == LUA_ERRRUN);
    assert(lua_gettop(L) == 1);
    assert(lua_touserdata(L, 1) == arg);
    return 0;
}

static size_t allocation_test(size_t fail_after)
{
    allocator_t a = {0};
    lua_State *L  = lua_newstate(allocate, &a);
    int completed = 0;
    int status;
    size_t allocations;
    assert(L);
    lua_pushinteger(L, 42);
    a.allocations = 0;
    a.fail_after  = fail_after;
    status        = net_pcall(L, allocate_lua, &completed);
    allocations   = a.allocations;
    a.fail_after  = 0;
    assert(lua_gettop(L) == 1);
    assert(lua_tointeger(L, 1) == 42);
    if (fail_after) {
        assert(status == LUA_ERRMEM);
        assert(!completed);
    } else {
        assert(status == 0);
        assert(completed);
        assert(net_pcall(L, error_lua, &completed) == LUA_ERRRUN);
        assert(net_pcall(L, nested_lua, &completed) == 0);
        assert(lua_gettop(L) == 1);
        assert(lua_tointeger(L, 1) == 42);
    }
    lua_close(L);
    assert(a.blocks == 0);
    return allocations;
}

int main(void)
{
    size_t allocations = allocation_test(0);
    assert(allocations > 0);
    for (size_t n = 1; n <= allocations; n++) {
        allocation_test(n);
    }
    printf("%s: protected calls passed (%zu allocation failure points)\n",
           LUA_VERSION, allocations);
    return 0;
}
