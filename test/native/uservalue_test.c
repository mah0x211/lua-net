/* Copyright (C) 2026 Masatoshi Fukunaga. MIT license; see LICENSE. */
#include "net_socket.h"
#include <assert.h>
#include <stdio.h>

static int check_upvalue(lua_State *L)
{
    lua_pushinteger(L, 11);
    net_setuservalue(L, lua_upvalueindex(1));
    assert(lua_gettop(L) == 0);
    net_getdeluservalue(L, lua_upvalueindex(1));
    assert(lua_gettop(L) == 1 && lua_tointeger(L, -1) == 11);
    lua_pop(L, 1);
    net_getuservalue(L, lua_upvalueindex(1));
    assert(lua_isnil(L, -1));
    lua_pop(L, 1);
    return 0;
}

int main(void)
{
    lua_State *L = luaL_newstate();
    lua_State *thread = NULL;
    assert(L);

    lua_newuserdata(L, 1);
    lua_pushnil(L);
    net_setuservalue(L, -2);
    assert(lua_gettop(L) == 1);
    net_getuservalue(L, -1);
    assert(lua_gettop(L) == 2 && lua_isnil(L, -1));
    lua_pop(L, 1);

    // Weak values let real GC check whether the owner or stack retains them.
    lua_newtable(L);
    lua_newtable(L);
    lua_pushliteral(L, "v");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, 2);

    thread = lua_newthread(L);
    lua_pushvalue(L, -1);
    lua_rawseti(L, 2, 1);
    net_setuservalue(L, -3);
    assert(lua_gettop(L) == 2);
    lua_gc(L, LUA_GCCOLLECT, 0);
    net_getuservalue(L, -2);
    assert(lua_gettop(L) == 3 && lua_tothread(L, -1) == thread);
    lua_pop(L, 1);
    net_deluservalue(L, -2);
    assert(lua_gettop(L) == 2);
    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_rawgeti(L, 2, 1);
    assert(lua_isnil(L, -1));
    lua_pop(L, 1);

    thread = lua_newthread(L);
    lua_pushvalue(L, -1);
    lua_rawseti(L, 2, 1);
    net_setuservalue(L, -3);
    net_getdeluservalue(L, 1);
    assert(lua_gettop(L) == 3 && lua_tothread(L, -1) == thread);
    net_getuservalue(L, 1);
    assert(lua_isnil(L, -1));
    lua_pop(L, 1);
    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_rawgeti(L, 2, 1);
    assert(lua_tothread(L, -1) == thread);
    lua_pop(L, 2);
    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_rawgeti(L, 2, 1);
    assert(lua_isnil(L, -1));
    lua_pop(L, 1);

    net_getdeluservalue(L, -2);
    assert(lua_gettop(L) == 3 && lua_isnil(L, -1));
    lua_pop(L, 1);
    net_deluservalue(L, -2);
    assert(lua_gettop(L) == 2);
    lua_pushinteger(L, 7);
    net_setuservalue(L, 1);
    lua_pushinteger(L, 9);
    net_setuservalue(L, -3);
    net_getuservalue(L, -2);
    assert(lua_gettop(L) == 3 && lua_tointeger(L, -1) == 9);
    lua_pop(L, 1);

    // The target userdata can also be the value consumed from the stack.
    lua_pushvalue(L, 1);
    net_setuservalue(L, -1);
    assert(lua_gettop(L) == 2);
    net_getuservalue(L, 1);
    assert(lua_rawequal(L, 1, -1));
    lua_pop(L, 1);
    lua_pushvalue(L, 1);
    lua_pushcclosure(L, check_upvalue, 1);
    lua_call(L, 0, 0);
    assert(lua_gettop(L) == 2);
    lua_close(L);
    puts(LUA_VERSION ": uservalue helpers passed");
    return 0;
}
