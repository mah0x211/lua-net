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

#ifndef net_pcall_h
#define net_pcall_h

#include <lua.h>

/* Call fn with arg as its sole lightuserdata argument. Lua results and
 * errors are discarded; C results belong in arg. Always restore the stack.
 * Unlike preparing a closure before lua_pcall(), setup is also OOM-safe. */
static inline int net_pcall(lua_State *L, lua_CFunction fn, void *arg)
{
    int top = lua_gettop(L);
    int status;

#if LUA_VERSION_NUM == 501
    status = lua_cpcall(L, fn, arg);
#else
    if (!lua_checkstack(L, 2)) {
        return LUA_ERRMEM;
    }
    // A zero-upvalue C function does not allocate in Lua 5.2 and later.
    lua_pushcfunction(L, fn);
    lua_pushlightuserdata(L, arg);
    status = lua_pcall(L, 1, 0, 0);
#endif
    lua_settop(L, top);
    return status;
}

#endif // net_pcall_h
