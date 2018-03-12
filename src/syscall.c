/*
 *  Copyright (C) 2018 Masatoshi Teruya
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
 *  src/syscall.c
 *  lua-net
 *  Created by Masatoshi Teruya on 18/03/12.
 *
 */
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
// lua
#include <lua.h>
#include <lauxlib.h>


static inline void pushfn2tbl( lua_State *L, const char *k, lua_CFunction v ){
    lua_pushstring( L, k );
    lua_pushcfunction( L, v );
    lua_rawset( L, -3 );
}


static int strerror_lua( lua_State *L )
{
    int err = lua_tointeger( L, 1 );

    lua_pushstring( L, strerror( err ) );

    return 1;
}


LUALIB_API int luaopen_net_syscall( lua_State *L )
{
    struct luaL_Reg funcs[] = {
        { "strerror", strerror_lua },
        { NULL, NULL }
    };
    struct luaL_Reg *ptr = funcs;

    lua_newtable( L );
    while( ptr->name ){
        pushfn2tbl( L, ptr->name, ptr->func );
        ptr++;
    }

    return 1;
}

