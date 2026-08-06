/**
 *  Copyright (C) 2026 Masatoshi Fukunaga
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
 */

#ifndef net_sockopts_h
#define net_sockopts_h

#include "net_socket.h"
#include "optcheck.h"

#include <math.h>

typedef struct {
    int broadcast;
    int broadcast_set;
    int debug;
    int debug_set;
    int dontroute;
    int dontroute_set;
    int keepalive;
    int keepalive_set;
    int linger;
    int linger_set;
    const char *mcastif;
    int mcastif_set;
    int mcastloop;
    int mcastloop_set;
    int mcastttl;
    int mcastttl_set;
    int oobinline;
    int oobinline_set;
    int rcvbuf;
    int rcvbuf_set;
    int rcvlowat;
    int rcvlowat_set;
    double rcvtimeo;
    int rcvtimeo_set;
    int reuseaddr;
    int reuseaddr_set;
    int reuseport;
    int reuseport_set;
    int sndbuf;
    int sndbuf_set;
    int sndlowat;
    int sndlowat_set;
    double sndtimeo;
    int sndtimeo_set;
    int timestamp;
    int timestamp_set;
    int tcpkeepalive;
    int tcpkeepalive_set;
    int tcpkeepcnt;
    int tcpkeepcnt_set;
    int tcpkeepintvl;
    int tcpkeepintvl_set;
    int tcpcork;
    int tcpcork_set;
    int tcpnodelay;
    int tcpnodelay_set;
} sockopts_t;

static inline int sockopts_check_bool(lua_State *L, const char *name, void *ctx)
{
    sockopts_t *opts = ctx;
    int value        = 0;

    if (lua_type(L, -1) != LUA_TBOOLEAN) {
        return luaL_error(L, "opts.%s must be boolean, got %s", name,
                          luaL_typename(L, -1));
    }
    value = lua_toboolean(L, -1);

    if (strcmp(name, "broadcast") == 0) {
        opts->broadcast_set = 1;
        opts->broadcast     = value;
    } else if (strcmp(name, "debug") == 0) {
        opts->debug_set = 1;
        opts->debug     = value;
    } else if (strcmp(name, "dontroute") == 0) {
        opts->dontroute_set = 1;
        opts->dontroute     = value;
    } else if (strcmp(name, "keepalive") == 0) {
        opts->keepalive_set = 1;
        opts->keepalive     = value;
    } else if (strcmp(name, "mcastloop") == 0) {
        opts->mcastloop_set = 1;
        opts->mcastloop     = value;
    } else if (strcmp(name, "oobinline") == 0) {
        opts->oobinline_set = 1;
        opts->oobinline     = value;
    } else if (strcmp(name, "reuseaddr") == 0) {
        opts->reuseaddr_set = 1;
        opts->reuseaddr     = value;
    } else if (strcmp(name, "reuseport") == 0) {
        opts->reuseport_set = 1;
        opts->reuseport     = value;
    } else if (strcmp(name, "timestamp") == 0) {
        opts->timestamp_set = 1;
        opts->timestamp     = value;
    } else if (strcmp(name, "tcpcork") == 0) {
        opts->tcpcork_set = 1;
        opts->tcpcork     = value;
    } else if (strcmp(name, "tcpnodelay") == 0) {
        opts->tcpnodelay_set = 1;
        opts->tcpnodelay     = value;
    }

    return 0;
}

static inline int sockopts_check_int(lua_State *L, const char *name, void *ctx)
{
    sockopts_t *opts = ctx;
    int value        = 0;

    if (lua_type(L, -1) != LUA_TNUMBER) {
        return luaL_error(L, "opts.%s must be integer, got %s", name,
                          luaL_typename(L, -1));
    }
    value = lauxh_checkinteger(L, -1);

    if (strcmp(name, "linger") == 0) {
        opts->linger_set = 1;
        opts->linger     = value;
    } else if (strcmp(name, "mcastttl") == 0) {
        opts->mcastttl_set = 1;
        opts->mcastttl     = value;
    } else if (strcmp(name, "rcvbuf") == 0) {
        opts->rcvbuf_set = 1;
        opts->rcvbuf     = value;
    } else if (strcmp(name, "rcvlowat") == 0) {
        opts->rcvlowat_set = 1;
        opts->rcvlowat     = value;
    } else if (strcmp(name, "sndbuf") == 0) {
        opts->sndbuf_set = 1;
        opts->sndbuf     = value;
    } else if (strcmp(name, "sndlowat") == 0) {
        opts->sndlowat_set = 1;
        opts->sndlowat     = value;
    } else if (strcmp(name, "tcpkeepalive") == 0) {
        opts->tcpkeepalive_set = 1;
        opts->tcpkeepalive     = value;
    } else if (strcmp(name, "tcpkeepcnt") == 0) {
        opts->tcpkeepcnt_set = 1;
        opts->tcpkeepcnt     = value;
    } else if (strcmp(name, "tcpkeepintvl") == 0) {
        opts->tcpkeepintvl_set = 1;
        opts->tcpkeepintvl     = value;
    }

    return 0;
}

static inline int sockopts_check_timeval(lua_State *L, const char *name,
                                         void *ctx)
{
    sockopts_t *opts = ctx;
    double value     = 0;

    if (lua_type(L, -1) != LUA_TNUMBER) {
        return luaL_error(L, "opts.%s must be number, got %s", name,
                          luaL_typename(L, -1));
    }
    value = lua_tonumber(L, -1);

    if (strcmp(name, "rcvtimeo") == 0) {
        opts->rcvtimeo_set = 1;
        opts->rcvtimeo     = value;
    } else if (strcmp(name, "sndtimeo") == 0) {
        opts->sndtimeo_set = 1;
        opts->sndtimeo     = value;
    }

    return 0;
}

static inline int sockopts_check_string(lua_State *L, const char *name,
                                        void *ctx)
{
    sockopts_t *opts = ctx;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    if (strcmp(name, "mcastif") == 0) {
        opts->mcastif_set = 1;
        opts->mcastif     = lua_tostring(L, -1);
    }

    return 0;
}

static inline int sockopts_int_lua(lua_State *L, int fd, int level, int opt,
                                   int type, const char *name)
{
    int top       = lua_gettop(L);
    int flg       = 0;
    socklen_t len = sizeof(int);

    if (getsockopt(fd, level, opt, (void *)&flg, &len) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, name);
        return 2;
    }

    switch (type) {
    case LUA_TBOOLEAN:
        lua_pushboolean(L, flg);
        break;

    default:
        lua_pushinteger(L, flg);
    }

    if (top == 1 || lua_isnoneornil(L, 2)) {
        return 1;
    }

    switch (type) {
    case LUA_TBOOLEAN:
        flg = lauxh_checkboolean(L, 2);
        if (setsockopt(fd, level, opt, (void *)&flg, len) == 0) {
            return 1;
        }
        break;

    default:
        flg = lauxh_checkinteger(L, 2);
        if (setsockopt(fd, level, opt, (void *)&flg, len) == 0) {
            return 1;
        }
    }

    lua_pushnil(L);
    lua_errno_new(L, errno, name);
    return 2;
}

static inline int sockopts_timeval_lua(lua_State *L, int fd, int level, int opt,
                                       const char *name)
{
    int top             = lua_gettop(L);
    struct timeval tval = {0, 0};
    socklen_t len       = sizeof(struct timeval);

    if (getsockopt(fd, level, opt, (void *)&tval, &len) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, name);
        return 2;
    }

    lua_pushnumber(L, (double)tval.tv_sec + ((double)tval.tv_usec / 1000000));
    if (top != 1 && !lua_isnoneornil(L, 2)) {
        double hi   = 0;
        double lo   = 0;
        double tnum = (double)luaL_checknumber(L, 2);

        lo           = modf(tnum, &hi);
        tval.tv_sec  = (time_t)hi;
        tval.tv_usec = (suseconds_t)(lo * 1000000);
        if (setsockopt(fd, level, opt, (void *)&tval, len) != 0) {
            lua_pushnil(L);
            lua_errno_new(L, errno, name);
            return 2;
        }
    }

    return 1;
}

static inline int sockopts_set_bool(int fd, int optname, int value)
{
    return setsockopt(fd, SOL_SOCKET, optname, (void *)&value, sizeof(value));
}

static inline int sockopts_set_int(int fd, int level, int optname, int value)
{
    return setsockopt(fd, level, optname, (void *)&value, sizeof(value));
}

static inline int sockopts_set_timeval(int fd, int optname, double value)
{
    struct timeval tval = {0, 0};
    double hi           = 0;
    double lo           = modf(value, &hi);

    tval.tv_sec  = (time_t)hi;
    tval.tv_usec = (suseconds_t)(lo * 1000000);

    return setsockopt(fd, SOL_SOCKET, optname, (void *)&tval, sizeof(tval));
}

static inline int sockopts_set_linger(int fd, int value)
{
    struct linger l = {.l_onoff = value >= 0, .l_linger = value};
#if defined(SO_LINGER_SEC)
    int opt = SO_LINGER_SEC;
#else
    int opt = SO_LINGER;
#endif

    return setsockopt(fd, SOL_SOCKET, opt, (void *)&l, sizeof(l));
}

static inline int sockopts_set_mcast_bool(int fd, int family, int v4opt,
                                          int v6opt, int value)
{
    switch (family) {
    case AF_INET:
        return sockopts_set_int(fd, IPPROTO_IP, v4opt, value);
    case AF_INET6:
        return sockopts_set_int(fd, IPPROTO_IPV6, v6opt, value);
    default:
        errno = EAFNOSUPPORT;
        return -1;
    }
}

static inline int sockopts_set_mcastif(int fd, int family, const char *ifname)
{
    switch (family) {
    case AF_INET: {
        struct ifreq ifr  = {0};
        struct in_addr ia = {0};

        strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
        if (ioctl(fd, SIOCGIFADDR, &ifr) != 0) {
            return -1;
        }

        ia = ((struct sockaddr_in *)&ifr.ifr_addr)->sin_addr;
        return setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, (void *)&ia,
                          sizeof(ia));
    }
    case AF_INET6: {
        unsigned int idx = if_nametoindex(ifname);

        if (idx == 0) {
            errno = ENODEV;
            return -1;
        }
        return setsockopt(fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, (void *)&idx,
                          sizeof(idx));
    }
    default:
        errno = EAFNOSUPPORT;
        return -1;
    }
}

static inline int sockopts_apply(int fd, int family, const sockopts_t *opts)
{
    if (opts->broadcast_set &&
        sockopts_set_bool(fd, SO_BROADCAST, opts->broadcast) != 0) {
        return -1;
    } else if (opts->debug_set &&
               sockopts_set_bool(fd, SO_DEBUG, opts->debug) != 0) {
        return -1;
    } else if (opts->dontroute_set &&
               sockopts_set_bool(fd, SO_DONTROUTE, opts->dontroute) != 0) {
        return -1;
    } else if (opts->keepalive_set &&
               sockopts_set_bool(fd, SO_KEEPALIVE, opts->keepalive) != 0) {
        return -1;
    } else if (opts->oobinline_set &&
               sockopts_set_bool(fd, SO_OOBINLINE, opts->oobinline) != 0) {
        return -1;
    } else if (opts->reuseaddr_set &&
               sockopts_set_bool(fd, SO_REUSEADDR, opts->reuseaddr) != 0) {
        return -1;
    } else if (opts->timestamp_set &&
               sockopts_set_bool(fd, SO_TIMESTAMP, opts->timestamp) != 0) {
        return -1;
    } else if (opts->rcvbuf_set &&
               sockopts_set_int(fd, SOL_SOCKET, SO_RCVBUF, opts->rcvbuf) != 0) {
        return -1;
    } else if (opts->rcvlowat_set &&
               sockopts_set_int(fd, SOL_SOCKET, SO_RCVLOWAT, opts->rcvlowat) !=
                   0) {
        return -1;
    } else if (opts->sndbuf_set &&
               sockopts_set_int(fd, SOL_SOCKET, SO_SNDBUF, opts->sndbuf) != 0) {
        return -1;
    } else if (opts->sndlowat_set &&
               sockopts_set_int(fd, SOL_SOCKET, SO_SNDLOWAT, opts->sndlowat) !=
                   0) {
        return -1;
    } else if (opts->rcvtimeo_set &&
               sockopts_set_timeval(fd, SO_RCVTIMEO, opts->rcvtimeo) != 0) {
        return -1;
    } else if (opts->sndtimeo_set &&
               sockopts_set_timeval(fd, SO_SNDTIMEO, opts->sndtimeo) != 0) {
        return -1;
    } else if (opts->linger_set && sockopts_set_linger(fd, opts->linger) != 0) {
        return -1;
    }

    if (opts->reuseport_set) {
#if defined(SO_REUSEPORT)
        if (sockopts_set_bool(fd, SO_REUSEPORT, opts->reuseport) != 0) {
            return -1;
        }
#else
        errno = EOPNOTSUPP;
        return -1;
#endif
    }

    if (opts->tcpnodelay_set &&
        sockopts_set_int(fd, IPPROTO_TCP, TCP_NODELAY, opts->tcpnodelay) != 0) {
        return -1;
    } else if (opts->tcpkeepintvl_set &&
               sockopts_set_int(fd, IPPROTO_TCP, TCP_KEEPINTVL,
                                opts->tcpkeepintvl) != 0) {
        return -1;
    } else if (opts->tcpkeepcnt_set &&
               sockopts_set_int(fd, IPPROTO_TCP, TCP_KEEPCNT,
                                opts->tcpkeepcnt) != 0) {
        return -1;
    }

    if (opts->tcpkeepalive_set) {
#if defined(TCP_KEEPALIVE)
        if (sockopts_set_int(fd, IPPROTO_TCP, TCP_KEEPALIVE,
                             opts->tcpkeepalive) != 0) {
            return -1;
        }
#elif defined(TCP_KEEPIDLE)
        if (sockopts_set_int(fd, IPPROTO_TCP, TCP_KEEPIDLE,
                             opts->tcpkeepalive) != 0) {
            return -1;
        }
#else
        errno = EOPNOTSUPP;
        return -1;
#endif
    }

    if (opts->tcpcork_set) {
#if defined(TCP_CORK)
        if (sockopts_set_int(fd, IPPROTO_TCP, TCP_CORK, opts->tcpcork) != 0) {
            return -1;
        }
#elif defined(TCP_NOPUSH)
        if (sockopts_set_int(fd, IPPROTO_TCP, TCP_NOPUSH, opts->tcpcork) != 0) {
            return -1;
        }
#else
        errno = EOPNOTSUPP;
        return -1;
#endif
    }

    if (opts->mcastloop_set &&
        sockopts_set_mcast_bool(fd, family, IP_MULTICAST_LOOP,
                                IPV6_MULTICAST_LOOP, opts->mcastloop) != 0) {
        return -1;
    } else if (opts->mcastttl_set) {
        if (family == AF_INET) {
            return sockopts_set_int(fd, IPPROTO_IP, IP_MULTICAST_TTL,
                                    opts->mcastttl);
        } else if (family == AF_INET6) {
            return sockopts_set_int(fd, IPPROTO_IPV6, IPV6_MULTICAST_HOPS,
                                    opts->mcastttl);
        }
        errno = EAFNOSUPPORT;
        return -1;
    } else if (opts->mcastif_set &&
               sockopts_set_mcastif(fd, family, opts->mcastif) != 0) {
        return -1;
    }

    return 0;
}

#endif // net_sockopts_h
