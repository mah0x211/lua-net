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
#include <lauxlib.h>

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

#endif // net_addrinfo_h
