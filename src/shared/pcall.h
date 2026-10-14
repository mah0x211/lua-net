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

#ifndef LUA_OK
# define LUA_OK 0
#endif

/* Call fn with arg as its sole lightuserdata argument. nresults must be
 * in 0..LUA_MINSTACK. On success, leave the requested results (padding with
 * nil). On failure, leave one error regardless of nresults. Non-string errors
 * are stringified inside the protected call. If stringification fails, leave
 * that error unchanged rather than retrying.
 * The caller must have one free error slot (two free slots in Lua 5.1 for
 * lua_cpcall setup). Call setup is protected against allocation failures too.
 */
int net_pcall_ex(lua_State *L, lua_CFunction fn, void *arg, int nresults);
int net_pcall(lua_State *L, lua_CFunction fn, void *arg);

#endif // net_pcall_h
