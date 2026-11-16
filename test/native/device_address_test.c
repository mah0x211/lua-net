/* Copyright (C) 2026 Masatoshi Fukunaga. MIT license; see LICENSE. */
#include "../../src/device.c"
#include <assert.h>

static void check_address(lua_State *L, const unsigned char *addr, size_t len,
                          const char *expected)
{
    lua_newtable(L);
    add_ifa_ether(L, addr, len);
    assert(lua_gettop(L) == 1);
    lua_getfield(L, 1, "ether");
    if (expected) {
        assert(lua_type(L, -1) == LUA_TSTRING);
        assert(strcmp(lua_tostring(L, -1), expected) == 0);
    } else {
        assert(lua_isnil(L, -1));
    }
    lua_settop(L, 0);
}

int main(void)
{
    const unsigned char addr[] = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99,
        0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x80, 0x01, 0xfe, 0xff,
    };
    lua_State *L = luaL_newstate();
    assert(L);
    check_address(L, addr, 0, NULL);
    check_address(L, addr, 5, NULL);
    check_address(L, addr, 6, "00:11:22:33:44:55");
    check_address(L, addr, 8, "00:11:22:33:44:55:66:77");
    check_address(L, addr, sizeof(addr),
                  "00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff:80:01:fe:ff");
    lua_close(L);
    puts("device link-layer address tests passed");
    return 0;
}
