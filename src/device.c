/**
 *  Copyright 2015-present Masatoshi Fukunaga. All rights reserved.
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
 */

#define _GNU_SOURCE
// depend
#include "lauxhlib.h"
#include "lua_errno.h"
// lua
#include <lauxlib.h>
// system
#include <errno.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#if defined(__linux__)
# include <linux/if_packet.h>
#else
# include <net/if_dl.h>
#endif

typedef struct {
    const char *name;
    unsigned int value;
} ifa_flag_t;

static const ifa_flag_t IFA_FLAGS[] = {
    {"up",           IFF_UP         },
    {"broadcast",    IFF_BROADCAST  },
    {"debug",        IFF_DEBUG      },
    {"loopback",     IFF_LOOPBACK   },
    {"pointtopoint", IFF_POINTOPOINT},
    {"notrailers",   IFF_NOTRAILERS },
    {"running",      IFF_RUNNING    },
    {"noarp",        IFF_NOARP      },
    {"promisc",      IFF_PROMISC    },
    {"allmulti",     IFF_ALLMULTI   },
    {"multicast",    IFF_MULTICAST  },
#if defined(IFF_OACTIVE)
    {"oactive",      IFF_OACTIVE    },
#endif
#if defined(IFF_SIMPLEX)
    {"simplex",      IFF_SIMPLEX    },
#endif
#if defined(IFF_MASTER)
    {"master",       IFF_MASTER     },
#endif
#if defined(IFF_SLAVE)
    {"slave",        IFF_SLAVE      },
#endif
#if defined(IFF_PORTSEL)
    {"portsel",      IFF_PORTSEL    },
#endif
#if defined(IFF_AUTOMEDIA)
    {"automedia",    IFF_AUTOMEDIA  },
#endif
#if defined(IFF_DYNAMIC)
    {"dynamic",      IFF_DYNAMIC    },
#endif
#if defined(IFF_LOWER_UP)
    {"lower_up",     IFF_LOWER_UP   },
#endif
#if defined(IFF_DORMANT)
    {"dormant",      IFF_DORMANT    },
#endif
#if defined(IFF_ECHO)
    {"echo",         IFF_ECHO       },
#endif
    {NULL,           0              },
};

static inline void add_ifa_flags(lua_State *L, unsigned int ifa_flags)
{
    for (const ifa_flag_t *flag = IFA_FLAGS; flag->name; flag++) {
        if (ifa_flags & flag->value) {
            lauxh_pushbool2tbl(L, flag->name, 1);
        }
    }
}

static inline void add_ifa_index(lua_State *L, const char *ifa_name)
{
    unsigned int idx = if_nametoindex(ifa_name);

    if (idx != 0) {
        lauxh_pushint2tbl(L, "index", idx);
    }
}

static inline void add_ifa_mtu(lua_State *L, const char *ifa_name)
{
    int fd = socket(AF_INET, SOCK_DGRAM, 0);

    if (fd != -1) {
        struct ifreq ifr = {0};

        strncpy(ifr.ifr_name, ifa_name, IFNAMSIZ - 1);
        if (ioctl(fd, SIOCGIFMTU, &ifr) == 0) {
            lauxh_pushint2tbl(L, "mtu", ifr.ifr_mtu);
        }
        close(fd);
    }
}

static inline void add_ifa_ether(lua_State *L, const unsigned char *addr,
                                 size_t len)
{
    char host[18] = {0};

    if (len >= 6) {
        snprintf(host, sizeof(host), "%02x:%02x:%02x:%02x:%02x:%02x",
                 (unsigned int)addr[0], (unsigned int)addr[1],
                 (unsigned int)addr[2], (unsigned int)addr[3],
                 (unsigned int)addr[4], (unsigned int)addr[5]);
        lauxh_pushstr2tbl(L, "ether", host);
    }
}

static inline int gettable(lua_State *L, int tblidx, const char *name)
{
    lua_pushstring(L, name);
    lua_rawget(L, tblidx);
    if (!lauxh_istable(L, -1)) {
        lua_pop(L, 1);
        lua_pushstring(L, name);
        lua_newtable(L);
        lua_rawset(L, tblidx);
        lua_pushstring(L, name);
        lua_rawget(L, tblidx);
        return 1;
    }
    return 0;
}

/**
 * Build the Lua interface table from the list pointer stored in upvalue 1.
 * This function runs under lua_pcall so a Lua allocation error cannot bypass
 * the freeifaddrs call in getifaddrs_lua.
 */
static int push_ifaddrs(lua_State *L)
{
    struct ifaddrs **listp = lua_touserdata(L, lua_upvalueindex(1));
    struct ifaddrs *list   = *listp;
    const int tblidx       = 1;
    char host[NI_MAXHOST]  = {0};
    socklen_t addrlen      = 0;

    lua_newtable(L);
    for (struct ifaddrs *ifa = list; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_name || !ifa->ifa_addr) {
            continue;
        }

        if (gettable(L, tblidx, ifa->ifa_name) == 1) {
            add_ifa_flags(L, ifa->ifa_flags);
            add_ifa_index(L, ifa->ifa_name);
            add_ifa_mtu(L, ifa->ifa_name);
        }

        switch (ifa->ifa_addr->sa_family) {
        case AF_INET: {
            gettable(L, tblidx + 1, "inet");
            addrlen = sizeof(struct sockaddr_in);
        } break;

        case AF_INET6: {
            gettable(L, tblidx + 1, "inet6");
            addrlen = sizeof(struct sockaddr_in6);
        } break;

#if defined(__linux__)
        case AF_PACKET: {
            struct sockaddr_ll *addr = (struct sockaddr_ll *)ifa->ifa_addr;

            add_ifa_ether(L, addr->sll_addr, addr->sll_halen);
            lua_pop(L, 1);
            continue;
        }
#else
        case AF_LINK: {
            struct sockaddr_dl *addr = (struct sockaddr_dl *)ifa->ifa_addr;

            add_ifa_ether(L, (const unsigned char *)LLADDR(addr),
                          addr->sdl_alen);
            lua_pop(L, 1);
            continue;
        }
#endif
        default:
            lua_pop(L, 1);
            continue;
        }

        lua_createtable(L, 0, 4);
        if (getnameinfo(ifa->ifa_addr, addrlen, host, NI_MAXHOST, NULL, 0,
                        NI_NUMERICHOST) == 0) {
            lauxh_pushstr2tbl(L, "address", host);
        }
        if (ifa->ifa_netmask &&
            getnameinfo(ifa->ifa_netmask, addrlen, host, NI_MAXHOST, NULL, 0,
                        NI_NUMERICHOST) == 0) {
            lauxh_pushstr2tbl(L, "netmask", host);
        }
        if (ifa->ifa_flags & IFF_BROADCAST && ifa->ifa_broadaddr &&
            getnameinfo(ifa->ifa_broadaddr, addrlen, host, NI_MAXHOST, NULL, 0,
                        NI_NUMERICHOST) == 0) {
            lauxh_pushstr2tbl(L, "broadcast", host);
        }
        if (ifa->ifa_flags & IFF_POINTOPOINT && ifa->ifa_dstaddr &&
            getnameinfo(ifa->ifa_dstaddr, addrlen, host, NI_MAXHOST, NULL, 0,
                        NI_NUMERICHOST) == 0) {
            lauxh_pushstr2tbl(L, "point2point", host);
        }
        lua_rawseti(L, -2, lauxh_rawlen(L, -2) + 1);
        lua_pop(L, 1);
        lua_pop(L, 1);
    }

    return 1;
}

static int getifaddrs_lua(lua_State *L)
{
    struct ifaddrs *list = NULL;
    int rc               = 0;

    // Allocate the protected worker before acquiring the system list. Once
    // getifaddrs succeeds, no allocating Lua API runs outside lua_pcall.
    lua_pushlightuserdata(L, &list);
    lua_pushcclosure(L, push_ifaddrs, 1);
    if (getifaddrs(&list) != 0) {
        lua_pop(L, 1);
        lua_pushnil(L);
        lua_errno_new(L, errno, "getifaddrs");
        return 2;
    }

    rc = lua_pcall(L, 0, 1, 0);
    freeifaddrs(list);
    if (rc != 0) {
        return lua_error(L);
    }
    return 1;
}

LUALIB_API int luaopen_net_device(lua_State *L)
{
    static const struct luaL_Reg methods[] = {
        {"getifaddrs", getifaddrs_lua},
        {NULL,         NULL          }
    };

    lua_errno_loadlib(L);
    lua_newtable(L);
    for (const struct luaL_Reg *method = methods; method->name; method++) {
        lauxh_pushfn2tbl(L, method->name, method->func);
    }

    return 1;
}
