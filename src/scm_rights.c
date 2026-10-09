/**
 *  Copyright (C) 2015-2026 Masatoshi Fukunaga
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a
 *  copy of this software and associated documentation files (the "Software"),
 *  to deal in the Software without restriction, including without limitation
 *  the rights to use, copy, modify, merge, publish, distribute, sublicense,
 *  and/or sell copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 *  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *  DEALINGS IN THE SOFTWARE.
 *
 *  Created by Masatoshi Teruya on 15/12/17.
 */

#include "scm_rights.h"
#include "lauxhlib.h"
#include "lua_errno.h"
#include <errno.h>
#include <unistd.h>

#define NET_SCM_RIGHTS_MT "net.scm_rights"

static int peek_lua(lua_State *L)
{
    net_scm_rights_t *q = lauxh_checkudata(L, 1, NET_SCM_RIGHTS_MT);

    if (q->len) {
        lua_pushinteger(L, q->fds[q->len - 1]);
        return 1;
    }
    return 0;
}

static int get_lua(lua_State *L)
{
    net_scm_rights_t *q = lauxh_checkudata(L, 1, NET_SCM_RIGHTS_MT);

    if (q->len) {
        lua_pushinteger(L, q->fds[q->len - 1]);
        q->len--;
        return 1;
    }
    return 0;
}

static int len_lua(lua_State *L)
{
    net_scm_rights_t *q = lauxh_checkudata(L, 1, NET_SCM_RIGHTS_MT);
    lua_pushinteger(L, q->len);
    return 1;
}

static int close_lua(lua_State *L)
{
    net_scm_rights_t *q = lauxh_checkudata(L, 1, NET_SCM_RIGHTS_MT);
    int err             = net_scm_rights_close(q);

    if (err) {
        lua_errno_new(L, err, "close");
        return 1;
    }
    return 0;
}

static int gc_lua(lua_State *L)
{
    net_scm_rights_close(lauxh_checkudata(L, 1, NET_SCM_RIGHTS_MT));
    return 0;
}

int net_scm_rights_close(net_scm_rights_t *q)
{
    int err = 0;

    while (q->len) {
        int fd = q->fds[--q->len];
        if (close(fd) == -1 && !err) {
            err = errno;
        }
    }
    return err;
}

net_scm_rights_t *net_scm_rights_new(lua_State *L)
{
    net_scm_rights_t *q = lua_newuserdata(L, sizeof(*q));

    *q = (net_scm_rights_t){0};
    lauxh_setmetatable(L, NET_SCM_RIGHTS_MT);
    return q;
}

void net_scm_rights_init(lua_State *L)
{
    struct luaL_Reg method[] = {
        {"peek",  peek_lua },
        {"get",   get_lua  },
        {"len",   len_lua  },
        {"close", close_lua},
        {NULL,    NULL     }
    };

    luaL_newmetatable(L, NET_SCM_RIGHTS_MT);
    lauxh_pushfn2tbl(L, "__gc", gc_lua);
    lua_pushstring(L, "__index");
    lua_newtable(L);
    for (struct luaL_Reg *ptr = method; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    lua_rawset(L, -3);
    lua_pop(L, 1);
}
