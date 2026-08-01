/**
 *  Copyright (C) 2014-present Masatoshi Fukunaga
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to
 *  deal in the Software without restriction, including without limitation the
 *  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 *  sell copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 *  IN THE SOFTWARE.
 *
 *  Created by Masatoshi Teruya on 14/03/29.
 */

#ifndef net_addrinfo_h
#define net_addrinfo_h

// lua
#include "lauxhlib.h"

// system
#include <netdb.h>
#include <sys/un.h>

#define NET_ADDRINFO_MT "net.addrinfo"

// unix-domain socket max path length
#define UNIXPATH_MAX (sizeof(((struct sockaddr_un *)0)->sun_path))

typedef struct {
    int ai_addr_ref;
    int ai_canonname_ref;
    struct addrinfo ai;
} net_addrinfo_t;

LUALIB_API int luaopen_net_addrinfo(lua_State *L);

/**
 * @brief Allocate a net.addrinfo userdata that owns copies of `src`'s
 * sockaddr and canonical name.
 *
 * The sockaddr is copied into a Lua-managed sockaddr_storage userdata and
 * kept alive with a registry reference so the returned addrinfo stays valid
 * after the caller frees the source list.  The canonical name, if present,
 * is copied into a Lua string that is likewise referenced from the userdata.
 *
 * @param L Lua state.
 * @param src Source addrinfo whose contents are copied.
 * @return Pointer to the newly pushed net_addrinfo_t userdata.
 */
static inline net_addrinfo_t *net_addrinfo_new(lua_State *L,
                                               struct addrinfo *src)
{
    net_addrinfo_t *info = lua_newuserdata(L, sizeof(net_addrinfo_t));

    info->ai_addr_ref      = LUA_NOREF;
    info->ai_canonname_ref = LUA_NOREF;
    lauxh_setmetatable(L, NET_ADDRINFO_MT);

    // copy data
    memcpy((void *)&info->ai, (void *)src, sizeof(struct addrinfo));
    info->ai.ai_addr  = lua_newuserdata(L, sizeof(struct sockaddr_storage));
    info->ai_addr_ref = lauxh_ref(L);

    // copy sockaddr data
    info->ai.ai_addrlen = src->ai_addrlen;
    memcpy((void *)info->ai.ai_addr, (void *)src->ai_addr, src->ai_addrlen);

    // copy canonname data
    info->ai.ai_canonname = NULL;
    if (src->ai_canonname) {
        lua_pushstring(L, src->ai_canonname);
        info->ai.ai_canonname  = (char *)lua_tostring(L, -1);
        info->ai_canonname_ref = lauxh_ref(L);
    }

    return info;
}

#endif // net_addrinfo_h
