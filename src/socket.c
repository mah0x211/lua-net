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

// project
#include "constants.h"
#include "net_socket.h"
#include "optcheck.h"
#include "sockopts.h"
// depends
#include "lauxhlib.h"
#include "lua_errno.h"
#include "lua_error.h"

#ifndef LUA_OK
# define LUA_OK 0
#endif

#define DEFAULT_RECVSIZE 4096

static inline void dostring(lua_State *L, const char *s, int argidx, int nres)
{
    int top  = lua_gettop(L);
    int narg = (argidx > 0 && argidx <= top) ? (top - argidx + 1) : 0;

    // loadstring() pushes the compiled chunk on top of the stack, so we can
    // call it with the narg arguments already on the stack.  If loadstring()
    // fails, it pushes the error message on top of the stack and returns
    // non-zero.
    if (luaL_loadstring(L, s) != 0) {
        lua_error(L);
    }

    // move the compiled chunk below the arguments so that the arguments are in
    // the correct order for the call.  If there are no arguments, we don't need
    // to do anything.
    if (narg > 0) {
        lua_insert(L, argidx);
    }
    lua_call(L, narg, nres);
}

static inline int set_fd_flag(int fd, int getfl, int setfl, int fl)
{
    int flg = fcntl(fd, getfl);
    if (flg == -1) {
        // failed to get the flag
        return -1;
    }
    // set the flag
    return (fcntl(fd, setfl, flg | fl) == -1) ? -1 : 0;
}

// set FD_CLOEXEC on fd; return 0 on success, -1 on error
static inline int set_cloexec(int fd)
{
    return set_fd_flag(fd, F_GETFD, F_SETFD, FD_CLOEXEC);
}

// set O_NONBLOCK on fd; return 0 on success, -1 on error
static inline int set_nonblock(int fd)
{
    return set_fd_flag(fd, F_GETFL, F_SETFL, O_NONBLOCK);
}

// set cloexec + nonblock on fd; return 0 on success, -1 on error
static inline int set_cloexec_nonblock(int fd)
{
    return (set_cloexec(fd) == -1 || set_nonblock(fd) == -1) ? -1 : 0;
}

static int cloexec_nonblock_lua(lua_State *L, const char *op, int getfl,
                                int setfl, int fl)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int enabled     = lauxh_optboolean(L, 2, -1);
    int flg         = fcntl(s->fd, getfl);
    int oldfl       = flg & fl;

    if (flg == -1) {
        lua_pushnil(L);
        lua_errno_new(L, errno, op);
        return 2;
    }

    // get the flag
    if (enabled == -1) {
        lua_pushboolean(L, flg & fl);
        return 1;
    }

    // set or clear the flag
    if (enabled) {
        flg |= fl;
    } else {
        flg &= ~fl;
    }
    if (fcntl(s->fd, setfl, flg) == -1) {
        lua_pushnil(L);
        lua_errno_new(L, errno, op);
        return 2;
    }
    lua_pushboolean(L, oldfl);
    return 1;
}

static int cloexec_lua(lua_State *L)
{
    return cloexec_nonblock_lua(L, "cloexec", F_GETFD, F_SETFD, FD_CLOEXEC);
}

static int nonblock_lua(lua_State *L)
{
    return cloexec_nonblock_lua(L, "nonblock", F_GETFL, F_SETFL, O_NONBLOCK);
}

// multicast

static int mcastloop_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    switch (s->socktype) {
    case SOCK_RAW:
    case SOCK_DGRAM:
        switch (s->family) {
        case AF_INET:
            return sockopts_int_lua(L, s->fd, IPPROTO_IP, IP_MULTICAST_LOOP,
                                    LUA_TBOOLEAN, "mcastloop");

        case AF_INET6:
            return sockopts_int_lua(L, s->fd, IPPROTO_IPV6, IPV6_MULTICAST_LOOP,
                                    LUA_TBOOLEAN, "mcastloop");

        default:
            lua_pushnil(L);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "mcastloop_lua");
            return 2;
        }

    default:
        lua_pushnil(L);
        errno = ESOCKTNOSUPPORT;
        lua_errno_new(L, errno, "mcastloop_lua");
        return 2;
    }
}

static int mcastttl_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    switch (s->socktype) {
    case SOCK_RAW:
    case SOCK_DGRAM:
        switch (s->family) {
        case AF_INET:
            return sockopts_int_lua(L, s->fd, IPPROTO_IP, IP_MULTICAST_TTL,
                                    LUA_TNUMBER, "mcastttl");

        case AF_INET6:
            return sockopts_int_lua(L, s->fd, IPPROTO_IPV6, IPV6_MULTICAST_HOPS,
                                    LUA_TNUMBER, "mcastttl");
        default:
            lua_pushnil(L);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "mcastttl_lua");
            return 2;
        }

    default:
        lua_pushnil(L);
        errno = ESOCKTNOSUPPORT;
        lua_errno_new(L, errno, "mcastttl_lua");
        return 2;
    }
}

static int mcastif4_lua(lua_State *L, net_socket_t *s)
{
    int top              = lua_gettop(L);
    struct in_addr addr  = {0};
    socklen_t addrlen    = sizeof(addr);
    struct ifaddrs *list = NULL;

    if (getsockopt(s->fd, IPPROTO_IP, IP_MULTICAST_IF, (void *)&addr,
                   &addrlen) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "getsockopt");
        return 2;
    } else if (getifaddrs(&list) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "getifaddrs");
        return 2;
    }

    // push the IP_MULTICAST_IF value if found
    lua_pushnil(L);
    for (struct ifaddrs *ptr = list; ptr; ptr = ptr->ifa_next) {
        struct sockaddr_in *ifa_addr = (struct sockaddr_in *)ptr->ifa_addr;

        if (ptr->ifa_addr->sa_family == AF_INET &&
            addr.s_addr == ifa_addr->sin_addr.s_addr) {
            lua_pushstring(L, ptr->ifa_name);
            break;
        }
    }
    freeifaddrs(list);

    if (top > 1) {
        if (lua_isnoneornil(L, 2)) {
            // disable the interface setting
            addr.s_addr = 0;
            if (setsockopt(s->fd, IPPROTO_IP, IP_MULTICAST_IF, (void *)&addr,
                           sizeof(addr)) != 0) {
                lua_pushnil(L);
                lua_errno_new(L, errno, "setsockopt");
                return 2;
            }
        } else {
            const char *ifname = lauxh_checkstring(L, 2);
            struct ifreq ifr   = {0};

            strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
            // get interface address
            if (ioctl(s->fd, SIOCGIFADDR, &ifr) != 0) {
                // got error
                lua_pushnil(L);
                lua_errno_new(L, errno, "ioctl");
                return 2;
            }

            // set address to multicast_if
            addr = ((struct sockaddr_in *)&ifr.ifr_addr)->sin_addr;
            if (setsockopt(s->fd, IPPROTO_IP, IP_MULTICAST_IF, (void *)&addr,
                           sizeof(addr)) != 0) {
                // got error
                lua_pushnil(L);
                lua_errno_new(L, errno, "setsockopt");
                return 2;
            }
        }
    }

    return 1;
}

static int mcastif6_lua(lua_State *L, net_socket_t *s)
{
    int top            = lua_gettop(L);
    unsigned int idx   = 0;
    socklen_t idxlen   = sizeof(idx);
    char buf[IFNAMSIZ] = {0};
    char *ifname       = NULL;

    if (getsockopt(s->fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, (void *)&idx,
                   &idxlen) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "getsockopt");
        return 2;
    }

    ifname = if_indextoname(idx, buf);
    if (ifname) {
        lua_pushstring(L, ifname);
    } else if (errno == ENXIO) {
        // unknown device name
        lua_pushnil(L);
    } else {
        lua_pushnil(L);
        lua_errno_new(L, errno, "if_indextoname");
        return 2;
    }

    if (top > 1) {
        if (lua_isnoneornil(L, 2)) {
            // disable the interface setting
            idx = 0;
            if (setsockopt(s->fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, (void *)&idx,
                           sizeof(idx)) != 0) {
                lua_pushnil(L);
                lua_errno_new(L, errno, "setsockopt");
                return 2;
            }
        } else {
            // change
            ifname = (char *)lauxh_checkstring(L, 2);
            idx    = if_nametoindex(ifname);

            if (idx == 0) {
                lua_pushnil(L);
                lua_errno_new(L, errno, "if_nametoindex");
                return 2;
            } else if (setsockopt(s->fd, IPPROTO_IPV6, IPV6_MULTICAST_IF,
                                  (void *)&idx, sizeof(idx)) != 0) {
                lua_pushnil(L);
                lua_errno_new(L, errno, "setsockopt");
                return 2;
            }
        }
    }

    return 1;
}

static int mcastif_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    switch (s->socktype) {
    case SOCK_RAW:
    case SOCK_DGRAM:
        switch (s->family) {
        case AF_INET:
            return mcastif4_lua(L, s);

        case AF_INET6:
            return mcastif6_lua(L, s);

        default:
            lua_pushnil(L);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "mcastif_lua");
            return 2;
        }

    default:
        // got error
        lua_pushnil(L);
        errno = ESOCKTNOSUPPORT;
        lua_errno_new(L, errno, "mcastif_lua");
        return 2;
    }
}

static inline int mcast4group_lua(lua_State *L, net_socket_t *s, int opt)
{
    net_addrinfo_t *grp = lauxh_checkudata(L, 2, NET_ADDRINFO_MT);
    const char *ifname  = lauxh_optstring(L, 3, NULL);
    struct ip_mreq mr;

    if (grp->ai.ai_family != AF_INET) {
        lua_pushboolean(L, 0);
        errno = EAFNOSUPPORT;
        lua_errno_new(L, errno, "mcastif_lua");
        return 2;
    }

    mr = (struct ip_mreq){
        .imr_multiaddr = ((struct sockaddr_in *)grp->ai.ai_addr)->sin_addr,
        .imr_interface = {INADDR_ANY},
    };
    if (ifname) {
        struct ifreq ifr = {0};

        strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
        // get interface address
        if (ioctl(s->fd, SIOCGIFADDR, &ifr) != 0) {
            lua_pushboolean(L, 0);
            lua_errno_new(L, errno, "ioctl");
            return 2;
        }
        // set in_addr
        mr.imr_interface = ((struct sockaddr_in *)&ifr.ifr_addr)->sin_addr;
    }

    if (setsockopt(s->fd, IPPROTO_IP, opt, (void *)&mr,
                   sizeof(struct ip_mreq)) != 0) {
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "setsockopt");
        return 2;
    }

    lua_pushboolean(L, 1);

    return 1;
}

static inline int mcast6group_lua(lua_State *L, net_socket_t *s, int opt)
{
    net_addrinfo_t *grp = lauxh_checkudata(L, 2, NET_ADDRINFO_MT);
    const char *ifname  = lauxh_optstring(L, 3, NULL);
    struct ipv6_mreq mr;

    if (grp->ai.ai_family != AF_INET6) {
        lua_pushboolean(L, 0);
        errno = EAFNOSUPPORT;
        lua_errno_new(L, errno, "mcast6group_lua");
        return 2;
    }

    mr = (struct ipv6_mreq){
        .ipv6mr_multiaddr = ((struct sockaddr_in6 *)grp->ai.ai_addr)->sin6_addr,
        .ipv6mr_interface = 0,
    };

    if (ifname && (mr.ipv6mr_interface = if_nametoindex(ifname)) == 0) {
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "if_nametoindex");
        return 2;
    } else if (setsockopt(s->fd, IPPROTO_IPV6, opt, (void *)&mr,
                          sizeof(struct ipv6_mreq)) != 0) {
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "setsockopt");
        return 2;
    }

    lua_pushboolean(L, 1);

    return 1;
}

static int mcastjoin_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    switch (s->socktype) {
    case SOCK_RAW:
    case SOCK_DGRAM:
        // check socket family
        switch (s->family) {
        case AF_INET:
            return mcast4group_lua(L, s, IP_ADD_MEMBERSHIP);

        case AF_INET6:
            return mcast6group_lua(L, s, IPV6_JOIN_GROUP);

        default:
            lua_pushboolean(L, 0);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "mcastjoin_lua");
            return 2;
        }

    default:
        lua_pushboolean(L, 0);
        errno = ESOCKTNOSUPPORT;
        lua_errno_new(L, errno, "mcastjoin_lua");
        return 2;
    }
}

static int mcastleave_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    switch (s->socktype) {
    case SOCK_RAW:
    case SOCK_DGRAM:
        // check socket family
        switch (s->family) {
        case AF_INET:
            return mcast4group_lua(L, s, IP_DROP_MEMBERSHIP);

        case AF_INET6:
            return mcast6group_lua(L, s, IPV6_LEAVE_GROUP);

        default:
            lua_pushboolean(L, 0);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "mcastleave_lua");
            return 2;
        }

    default:
        lua_pushboolean(L, 0);
        errno = ESOCKTNOSUPPORT;
        lua_errno_new(L, errno, "mcastleave_lua");
        return 2;
    }
}

static inline int mcastsrcgroup_lua(lua_State *L, net_socket_t *s, int proto,
                                    int opt)
{
    net_addrinfo_t *grp = lauxh_checkudata(L, 2, NET_ADDRINFO_MT);
    net_addrinfo_t *src = lauxh_checkudata(L, 3, NET_ADDRINFO_MT);
    const char *ifname  = lauxh_optstring(L, 4, NULL);
    struct group_source_req gsr;

    if (grp->ai.ai_family != AF_INET6 || src->ai.ai_family != AF_INET6) {
        lua_pushboolean(L, 0);
        errno = EAFNOSUPPORT;
        lua_errno_new(L, errno, "mcastsrcgroup_lua");
        return 2;
    }

    memset(&gsr, 0, sizeof(gsr));
    memcpy(&gsr.gsr_group, grp->ai.ai_addr, grp->ai.ai_addrlen);
    memcpy(&gsr.gsr_source, src->ai.ai_addr, src->ai.ai_addrlen);
    if (ifname && (gsr.gsr_interface = if_nametoindex(ifname)) == 0) {
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "if_nametoindex");
        return 2;
    } else if (setsockopt(s->fd, proto, opt, (void *)&gsr, sizeof(gsr)) != 0) {
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "setsockopt");
        return 2;
    }

    lua_pushboolean(L, 1);

    return 1;
}

static inline int mcast4srcgroup_lua(lua_State *L, net_socket_t *s, int opt)
{
    net_addrinfo_t *grp      = lauxh_checkudata(L, 2, NET_ADDRINFO_MT);
    net_addrinfo_t *src      = lauxh_checkudata(L, 3, NET_ADDRINFO_MT);
    const char *ifname       = lauxh_optstring(L, 4, NULL);
    struct ip_mreq_source mr = {
        .imr_multiaddr  = ((struct sockaddr_in *)grp->ai.ai_addr)->sin_addr,
        .imr_sourceaddr = ((struct sockaddr_in *)src->ai.ai_addr)->sin_addr,
        .imr_interface  = {INADDR_ANY},
    };

    if (grp->ai.ai_family != AF_INET || src->ai.ai_family != AF_INET) {
        lua_pushboolean(L, 0);
        errno = EAFNOSUPPORT;
        lua_errno_new(L, errno, "mcast4srcgroup_lua");
        return 2;
    } else if (ifname) {
        struct ifreq ifr = {0};

        strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
        // get interface address
        if (ioctl(s->fd, SIOCGIFADDR, &ifr) != 0) {
            lua_pushboolean(L, 0);
            lua_errno_new(L, errno, "ioctl");
            return 2;
        }
        // set in_addr
        mr.imr_interface = ((struct sockaddr_in *)&ifr.ifr_addr)->sin_addr;
    }

    if (setsockopt(s->fd, IPPROTO_IP, opt, (void *)&mr,
                   sizeof(struct ip_mreq_source)) != 0) {
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "setsockopt");
        return 2;
    }

    lua_pushboolean(L, 1);

    return 1;
}

static int mcastjoinsrc_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    switch (s->socktype) {
    case SOCK_RAW:
    case SOCK_DGRAM:
        // check socket family
        switch (s->family) {
        case AF_INET:
            return mcast4srcgroup_lua(L, s, IP_ADD_SOURCE_MEMBERSHIP);

        case AF_INET6:
            return mcastsrcgroup_lua(L, s, IPPROTO_IPV6,
                                     MCAST_JOIN_SOURCE_GROUP);
        default:
            lua_pushboolean(L, 0);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "mcastjoinsrc_lua");
            return 2;
        }

    default:
        lua_pushboolean(L, 0);
        errno = ESOCKTNOSUPPORT;
        lua_errno_new(L, errno, "mcastjoinsrc_lua");
        return 2;
    }
}

static int mcastleavesrc_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    switch (s->socktype) {
    case SOCK_RAW:
    case SOCK_DGRAM:
        // check socket family
        switch (s->family) {
        case AF_INET:
            return mcast4srcgroup_lua(L, s, IP_DROP_SOURCE_MEMBERSHIP);

        case AF_INET6:
            return mcastsrcgroup_lua(L, s, IPPROTO_IPV6,
                                     MCAST_LEAVE_SOURCE_GROUP);

        default:
            lua_pushboolean(L, 0);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "mcastleavesrc_lua");
            return 2;
        }

    default:
        lua_pushboolean(L, 0);
        errno = ESOCKTNOSUPPORT;
        lua_errno_new(L, errno, "mcastleavesrc_lua");
        return 2;
    }
}

static int mcastblocksrc_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    switch (s->socktype) {
    case SOCK_RAW:
    case SOCK_DGRAM:
        // check socket family
        switch (s->family) {
        case AF_INET:
            return mcast4srcgroup_lua(L, s, IP_BLOCK_SOURCE);

        case AF_INET6:
            return mcastsrcgroup_lua(L, s, IPPROTO_IPV6, MCAST_BLOCK_SOURCE);

        default:
            lua_pushboolean(L, 0);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "mcastblocksrc_lua");
            return 2;
        }

    default:
        lua_pushboolean(L, 0);
        errno = ESOCKTNOSUPPORT;
        lua_errno_new(L, errno, "mcastblocksrc_lua");
        return 2;
    }
}

static int mcastunblocksrc_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    switch (s->socktype) {
    case SOCK_RAW:
    case SOCK_DGRAM:
        // check socket family
        switch (s->family) {
        case AF_INET:
            return mcast4srcgroup_lua(L, s, IP_UNBLOCK_SOURCE);

        case AF_INET6:
            return mcastsrcgroup_lua(L, s, IPPROTO_IPV6, MCAST_UNBLOCK_SOURCE);

        default:
            lua_pushboolean(L, 0);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "mcastunblocksrc_lua");
            return 2;
        }

    default:
        lua_pushboolean(L, 0);
        errno = ESOCKTNOSUPPORT;
        lua_errno_new(L, errno, "mcastunblocksrc_lua");
        return 2;
    }
}

// MARK: socket option
static inline int sockopt_int_lua(lua_State *L, int level, int optname,
                                  int type, const char *name)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    return sockopts_int_lua(L, s->fd, level, optname, type, name);
}

// readonly

static int error_lua(lua_State *L)
{
    int rv = sockopt_int_lua(L, SOL_SOCKET, SO_ERROR, LUA_TNUMBER, "error");
    if (rv == 1) {
        int err = lua_tointeger(L, -1);
        if (err == 0) {
            lua_pushnil(L);
        } else {
            lua_errno_new(L, err, "error");
        }
    }
    return rv;
}

static int acceptconn_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_ACCEPTCONN, LUA_TBOOLEAN,
                           "acceptconn");
}

// writable
static int tcpnodelay_lua(lua_State *L)
{
    return sockopt_int_lua(L, IPPROTO_TCP, TCP_NODELAY, LUA_TBOOLEAN,
                           "tcpnodelay");
}

static int tcpkeepintvl_lua(lua_State *L)
{
    return sockopt_int_lua(L, IPPROTO_TCP, TCP_KEEPINTVL, LUA_TNUMBER,
                           "tcpkeepintvl");
}

static int tcpkeepcnt_lua(lua_State *L)
{
    return sockopt_int_lua(L, IPPROTO_TCP, TCP_KEEPCNT, LUA_TNUMBER,
                           "tcpkeepcnt");
}

static int tcpkeepalive_lua(lua_State *L)
{
#if defined(TCP_KEEPALIVE)
    return sockopt_int_lua(L, IPPROTO_TCP, TCP_KEEPALIVE, LUA_TNUMBER,
                           "tcpkeepalive");

#elif defined(TCP_KEEPIDLE)
    return sockopt_int_lua(L, IPPROTO_TCP, TCP_KEEPIDLE, LUA_TNUMBER,
                           "tcpkeepalive");

#else
    // tcpkeepalive does not implemented in this platform
    lua_pushnil(L);
    errno = EOPNOTSUPP;
    lua_errno_new(L, errno, "tcpkeepalive_lua");
    return 2;

#endif
}

static int tcpcork_lua(lua_State *L)
{
#if defined(TCP_CORK)
    return sockopt_int_lua(L, IPPROTO_TCP, TCP_CORK, LUA_TBOOLEAN, "tcpcork");

#elif defined(TCP_NOPUSH)
    return sockopt_int_lua(L, IPPROTO_TCP, TCP_NOPUSH, LUA_TBOOLEAN, "tcpcork");

#else
    // tcpcork does not implmeneted in this platform
    lua_pushnil(L);
    errno = EOPNOTSUPP;
    lua_errno_new(L, errno, "tcpcork_lua");
    return 2;

#endif
}

static int reuseport_lua(lua_State *L)
{
#if defined(SO_REUSEPORT)
    return sockopt_int_lua(L, SOL_SOCKET, SO_REUSEPORT, LUA_TBOOLEAN,
                           "reuseport");

#else
    // reuseport does not implmeneted in this platform
    lua_pushnil(L);
    errno = EOPNOTSUPP;
    lua_errno_new(L, errno, "reuseport_lua");
    return 2;

#endif
}

static int reuseaddr_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_REUSEADDR, LUA_TBOOLEAN,
                           "reuseaddr");
}

static int broadcast_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_BROADCAST, LUA_TBOOLEAN,
                           "broadcast");
}

static int debug_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_DEBUG, LUA_TBOOLEAN, "debug");
}

static int keepalive_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_KEEPALIVE, LUA_TBOOLEAN,
                           "keepalive");
}

static int oobinline_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_OOBINLINE, LUA_TBOOLEAN,
                           "oobinline");
}

static int dontroute_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_DONTROUTE, LUA_TBOOLEAN,
                           "dontroute");
}

static int timestamp_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_TIMESTAMP, LUA_TBOOLEAN,
                           "timestamp");
}

static int ip_recvttl_lua(lua_State *L)
{
    return sockopt_int_lua(L, IPPROTO_IP, IP_RECVTTL, LUA_TBOOLEAN,
                           "ip_recvttl");
}

static int ip_recvtos_lua(lua_State *L)
{
    return sockopt_int_lua(L, IPPROTO_IP, IP_RECVTOS, LUA_TBOOLEAN,
                           "ip_recvtos");
}

static int ipv6_recvhoplimit_lua(lua_State *L)
{
    return sockopt_int_lua(L, IPPROTO_IPV6, IPV6_RECVHOPLIMIT, LUA_TBOOLEAN,
                           "ipv6_recvhoplimit");
}

static int rcvbuf_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_RCVBUF, LUA_TNUMBER, "rcvbuf");
}

static int rcvlowat_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_RCVLOWAT, LUA_TNUMBER, "rcvlowat");
}

static int sndbuf_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_SNDBUF, LUA_TNUMBER, "sndbuf");
}

static int sndlowat_lua(lua_State *L)
{
    return sockopt_int_lua(L, SOL_SOCKET, SO_SNDLOWAT, LUA_TNUMBER, "sndlowat");
}

static inline int sockopt_timeval_lua(lua_State *L, int level, int opt,
                                      const char *name)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    return sockopts_timeval_lua(L, s->fd, level, opt, name);
}

static int rcvtimeo_lua(lua_State *L)
{
    return sockopt_timeval_lua(L, SOL_SOCKET, SO_RCVTIMEO, "rcvtimeo");
}

static int sndtimeo_lua(lua_State *L)
{
    return sockopt_timeval_lua(L, SOL_SOCKET, SO_SNDTIMEO, "sndtimeo");
}

static int linger_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    struct linger l = {0, 0};
    socklen_t len   = sizeof(struct linger);
#if defined(SO_LINGER_SEC)
    int opt = SO_LINGER_SEC;
#else
    int opt = SO_LINGER;
#endif
    int top = lua_gettop(L);

    if (getsockopt(s->fd, SOL_SOCKET, opt, (void *)&l, &len) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "linger");
        return 2;
    }

    if (l.l_onoff) {
        lua_pushinteger(L, l.l_linger);
    } else {
        lua_pushinteger(L, -1);
    }

    // change
    if (top > 1 && !lua_isnoneornil(L, 2)) {
        // set linger option
        l.l_linger = lauxh_checkinteger(L, 2);
        l.l_onoff  = l.l_linger >= 0;
        if (setsockopt(s->fd, SOL_SOCKET, opt, (void *)&l, len) != 0) {
            lua_pushnil(L);
            lua_errno_new(L, errno, "linger");
            return 2;
        }
    }

    return 1;
}

// MARK: state

static int atmark_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int rc          = sockatmark(s->fd);

    if (rc == -1) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "sockatmark");
        return 2;
    }
    lua_pushboolean(L, rc);

    return 1;
}

// MARK: address info

static int getsockname_lua(lua_State *L)
{
    net_socket_t *s              = lauxh_checkudata(L, 1, SOCKET_MT);
    struct sockaddr_storage addr = {0};
    socklen_t addrlen            = sizeof(struct sockaddr_storage);
    struct addrinfo wrap;

    if (getsockname(s->fd, (struct sockaddr *)&addr, &addrlen) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "getsockname");
        return 2;
    }

    wrap = (struct addrinfo){
        .ai_flags     = 0,
        .ai_family    = s->family,
        .ai_socktype  = s->socktype,
        .ai_protocol  = s->protocol,
        .ai_addrlen   = addrlen,
        .ai_addr      = (struct sockaddr *)&addr,
        .ai_canonname = NULL,
        .ai_next      = NULL,
    };
    // push the addrinfo object to Lua stack
    net_addrinfo_new(L, &wrap);

    return 1;
}

static int getpeername_lua(lua_State *L)
{
    net_socket_t *s              = lauxh_checkudata(L, 1, SOCKET_MT);
    socklen_t len                = sizeof(struct sockaddr_storage);
    struct sockaddr_storage addr = {0};
    struct addrinfo wrap;

    if (getpeername(s->fd, (struct sockaddr *)&addr, &len) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "getpeername");
        return 2;
    }

    wrap = (struct addrinfo){
        .ai_flags     = 0,
        .ai_family    = s->family,
        .ai_socktype  = s->socktype,
        .ai_protocol  = s->protocol,
        .ai_addrlen   = len,
        .ai_addr      = (struct sockaddr *)&addr,
        .ai_canonname = NULL,
        .ai_next      = NULL,
    };
    // TODO: allocate addrinfo with net.addrinfo module
    net_addrinfo_new(L, &wrap);

    return 1;
}

// MARK: method

/**
 * @brief Convert an optional shutdown direction argument at Lua stack index
 * `idx` to the corresponding SHUT_* constant.  Accepted strings are "rd",
 * "wr", "rdwr".  Returns `defval` if the argument is absent, nil, or false.
 * Raises a Lua error on any other value.
 */
static int checkshutflag(lua_State *L, int idx, int defval)
{
    const char *s = NULL;
    int value     = 0;

    if (lua_isnoneornil(L, idx)) {
        return defval;
    }
    if (lua_type(L, idx) != LUA_TSTRING) {
        return luaL_error(L, "how must be string, got %s",
                          luaL_typename(L, idx));
    }
    s = lua_tostring(L, idx);
    if (net_shutdown_value(s, &value)) {
        return value;
    }
    return luaL_error(L,
                      "how='%s' is not a recognized shutdown direction "
                      "(must be one of \"rd\", \"wr\", \"rdwr\")",
                      s);
}

static inline int shutdownfd(lua_State *L, int fd, int how)
{
    if (shutdown(fd, how) != 0) {
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "shutdown");
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int shutdown_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int how         = checkshutflag(L, 2, SHUT_RDWR);

    return shutdownfd(L, s->fd, how);
}

static inline int closefd(lua_State *L, int fd, int how, int with_shutdown)
{
    int err = 0;

    if (with_shutdown) {
        if (shutdown(fd, how)) {
            err = errno;
        }
    }

    if (close(fd) == 0) {
        if (err) {
            lua_pushboolean(L, 0);
            lua_errno_new(L, errno, "shutdown");
            return 2;
        }
    } else if (err) {
        lua_pushboolean(L, 0);
        lua_errno_new(L, err, "shutdown");
        lua_errno_new_ex(L, LUA_ERRNO_T_DEFAULT, errno, "close", NULL, -1, 0);
        lua_replace(L, -2);
        return 2;
    } else {
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "close");
        return 2;
    }

    lua_pushboolean(L, 1);
    return 1;
}

static int close_lua(lua_State *L)
{
    net_socket_t *s   = lauxh_checkudata(L, 1, SOCKET_MT);
    int with_shutdown = !lua_isnoneornil(L, 2);
    int how           = checkshutflag(L, 2, -1);
    int fd            = s->fd;

    net_gcthread_close(L, s);
    if (fd == -1) {
        lua_pushboolean(L, 1);
        return 1;
    }
    s->fd = -1;

    return closefd(L, fd, how, with_shutdown);
}

static int listen_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int backlog     = (int)lauxh_optinteger(L, 2, SOMAXCONN);

    // listen
    if (listen(s->fd, (int)backlog) != 0) {
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "listen");
        return 2;
    }

    lua_pushboolean(L, 1);
    return 1;
}

static inline int acceptfd(int sfd, struct sockaddr *addr, socklen_t *addrlen)
{
    int flg = fcntl(sfd, F_GETFL);

    if (flg != -1) {
#if defined(HAVE_ACCEPT4)
        flg = SOCK_CLOEXEC | ((flg & O_NONBLOCK) ? SOCK_NONBLOCK : 0);
        return accept4(sfd, addr, addrlen, flg);

#else
        int fd = accept(sfd, addr, addrlen);

        if (fd != -1) {
            // set close-on-exec and server socket flags
            if (set_cloexec(fd) == 0 && fcntl(fd, F_SETFL, flg) == 0) {
                return fd;
            }
            close(fd);
        }
#endif
    }

    return -1;
}

static int acceptfd_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int fd          = acceptfd(s->fd, NULL, NULL);

    if (fd != -1) {
        lua_pushinteger(L, fd);
        return 1;
    } else if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ||
               errno == ECONNABORTED) {
        lua_pushnil(L);
        lua_pushnil(L);
        lua_pushboolean(L, 1);
        return 3;
    }

    // got error
    lua_pushnil(L);
    lua_errno_new(L, errno, "acceptfd");
    return 2;
}

static int accept_lua(lua_State *L)
{
    net_socket_t *s               = lauxh_checkudata(L, 1, SOCKET_MT);
    int with_addr                 = lauxh_optboolean(L, 2, 0);
    net_socket_t *cs              = lua_newuserdata(L, sizeof(net_socket_t));
    socklen_t saddrlen            = sizeof(struct sockaddr_storage);
    struct sockaddr_storage saddr = {0};
    struct sockaddr *addr         = NULL;
    socklen_t *addrlen            = NULL;

    // initialize the new socket object
    *cs = (net_socket_t){
        .fd            = -1,
        .family        = s->family,
        .socktype      = s->socktype,
        .protocol      = s->protocol,
        .gc_thread_ref = LUA_NOREF,
        .gc_thread     = lua_newthread(L),
    };

    if (with_addr) {
        addr    = (struct sockaddr *)&saddr;
        addrlen = &saddrlen;
    }

    // accept the connection
    cs->fd = acceptfd(s->fd, addr, addrlen);
    if (cs->fd == -1) {
        lua_pushnil(L);
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ||
            errno == ECONNABORTED) {
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        // got error
        lua_errno_new(L, errno, "acceptfd");
        return 2;
    }
    // keep a reference to the gc thread in the new socket object
    cs->gc_thread_ref = lauxh_ref(L);
    lauxh_setmetatable(L, SOCKET_MT);

    if (with_addr) {
        struct addrinfo wrap = {
            .ai_flags     = 0,
            .ai_family    = s->family,
            .ai_socktype  = s->socktype,
            .ai_protocol  = s->protocol,
            .ai_addrlen   = saddrlen,
            .ai_addr      = addr,
            .ai_canonname = NULL,
            .ai_next      = NULL,
        };
        lua_pushnil(L);
        lua_pushnil(L);
        // push the addrinfo object to Lua stack
        net_addrinfo_new(L, &wrap);
        return 4;
    }

    return 1;
}

/**
 * @brief Parse `MSG_*` flag arguments starting at `startidx` on the Lua
 * stack.  Each argument must be a string naming one of the recognised
 * MSG_* names (`oob`, `peek`, ...).  nil / none arguments are skipped so
 * callers can spread the argument list with `...`.
 *
 * @param L Lua state.
 * @param startidx First stack index to inspect.
 * @return int OR-ed bitmask of the parsed MSG_* values.
 */
static int net_check_msgflags(lua_State *L, int startidx)
{
    int flg = 0;
    int top = lua_gettop(L);

    for (int i = startidx; i <= top; i++) {
        const char *s = NULL;
        int value     = 0;

        if (lua_isnoneornil(L, i)) {
            continue;
        }
        if (lua_type(L, i) != LUA_TSTRING) {
            return luaL_argerror(L, i, "flag must be a string");
        }
        s = lua_tostring(L, i);
        if (!net_msgflag_value(s, &value)) {
            return luaL_argerror(
                L, i, lua_pushfstring(L, "unknown MSG_* flag: '%s'", s));
        }
        flg |= value;
    }
    return flg;
}

static int send_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    size_t len      = 0;
    const char *buf = lauxh_checklstring(L, 2, &len);
    int flg         = net_check_msgflags(L, 3);
    ssize_t rv      = 0;

    // invalid length
    if (!len) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "send_lua");
        return 2;
    }

    rv = send(s->fd, buf, len, flg);
    switch (rv) {
    case -1:
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            // again
            lua_pushinteger(L, 0);
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        // got error
        // closed by peer: EPIPE || ECONNRESET
        lua_pushnil(L);
        lua_errno_new(L, errno, "send");
        return 2;

    default:
        lua_pushinteger(L, rv);
        lua_pushnil(L);
        lua_pushboolean(L, len - (size_t)rv);
        return 3;
    }
}

static int sendto_lua(lua_State *L)
{
    net_socket_t *s      = lauxh_checkudata(L, 1, SOCKET_MT);
    size_t len           = 0;
    const char *buf      = lauxh_checklstring(L, 2, &len);
    net_addrinfo_t *info = lauxh_checkudata(L, 3, NET_ADDRINFO_MT);
    int flg              = net_check_msgflags(L, 4);
    ssize_t rv           = 0;

    // invalid length
    if (!len) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "sendto_lua");
        return 2;
    }

    rv = sendto(s->fd, buf, len, flg, (const struct sockaddr *)info->ai.ai_addr,
                info->ai.ai_addrlen);
    switch (rv) {
    case -1:
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            // again
            lua_pushinteger(L, 0);
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        // got error
        // closed by peer: EPIPE || ECONNRESET
        lua_pushnil(L);
        lua_errno_new(L, errno, "sendto");
        return 2;

    default:
        lua_pushinteger(L, rv);
        lua_pushnil(L);
        lua_pushboolean(L, len - (size_t)rv);
        return 3;
    }
}

static int sendfd_lua(lua_State *L)
{
    net_socket_t *s        = lauxh_checkudata(L, 1, SOCKET_MT);
    lua_Integer fd         = lauxh_checkinteger(L, 2);
    net_addrinfo_t *info   = lauxh_optudata(L, 3, NET_ADDRINFO_MT, NULL);
    int flg                = net_check_msgflags(L, 4);
    // NOTE: on linux, auxiliary data must be sent along with at least 1 byte of
    // real data in order to be sent.
    char iov_data          = 1;
    struct iovec empty_iov = {
        .iov_base = &iov_data,
        .iov_len  = sizeof(iov_data),
    };
    union {
        unsigned char buf[CMSG_SPACE(sizeof(int))];
        struct cmsghdr data;
    } ctrl = {
        .data.cmsg_len   = CMSG_LEN(sizeof(int)),
        .data.cmsg_level = SOL_SOCKET,
        .data.cmsg_type  = SCM_RIGHTS,
    };
    struct msghdr data = {
        .msg_name       = NULL,
        .msg_namelen    = 0,
        .msg_iov        = &empty_iov,
        .msg_iovlen     = 1,
        .msg_control    = &ctrl.data,
        .msg_controllen = ctrl.data.cmsg_len,
        .msg_flags      = 0,
    };

    // set fd
    *(int *)CMSG_DATA(&ctrl.data) = fd;

    // set msg_name
    if (info) {
        data.msg_name    = (void *)info->ai.ai_addr;
        data.msg_namelen = info->ai.ai_addrlen;
    }

    switch (sendmsg(s->fd, &data, flg)) {
    case -1:
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            // again
            lua_pushinteger(L, 0);
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        // got error
        // closed by peer: EPIPE || ECONNRESET
        lua_pushnil(L);
        lua_errno_new(L, errno, "sendmsg");
        return 2;

    default:
        lua_pushinteger(L, 0);
        return 1;
    }
}

static int sendmsg_lua(lua_State *L)
{
    net_socket_t *s      = lauxh_checkudata(L, 1, SOCKET_MT);
    // arg 2: msg string (optional)
    size_t msglen        = 0;
    const char *msgbuf   = lauxh_optlstring(L, 2, NULL, &msglen);
    // arg 3: net.addrinfo (optional; destination address)
    net_addrinfo_t *addr = lauxh_optudata(L, 3, NET_ADDRINFO_MT, NULL);
    // arg 4: cmsg table (optional; ancillary data descriptors)
    int flgs             = 0;
    struct iovec iov     = {
        .iov_base = (void *)msgbuf,
        .iov_len  = msglen,
    };
    struct msghdr data = {
        .msg_name       = (addr) ? (void *)addr->ai.ai_addr : NULL,
        .msg_namelen    = (addr) ? addr->ai.ai_addrlen : 0,
        .msg_iov        = (msgbuf) ? &iov : NULL,
        .msg_iovlen     = (msgbuf) ? 1 : 0,
        .msg_control    = NULL,
        .msg_controllen = 0,
        .msg_flags      = 0,
    };
    int has_cmsgs = 0;
    ssize_t rv    = 0;

    // arg 4: check cmsg table (optional; ancillary data descriptors) specified
    if (!lua_isnoneornil(L, 4)) {
        luaL_checktype(L, 4, LUA_TTABLE);
        has_cmsgs = 1;
    }

    // args 5+: flags.  Parse flag arguments before pushing the assembled cmsg
    // control-buffer string, so that net_check_msgflags does not scan past
    // the actual sendmsg arguments and pick up the pushed string as an
    // additional flag.
    flgs = net_check_msgflags(L, 5);

    // arg 4: build cmsg control-buffer string
    if (has_cmsgs && net_cmsg_build_buffer(L, 4)) {
        size_t controllen  = 0;
        const char *ctlbuf = lua_tolstring(L, -1, &controllen);
        if (controllen > 0) {
            data.msg_control    = (void *)ctlbuf;
            data.msg_controllen = (socklen_t)controllen;
        }
    }

    if (msgbuf == NULL && data.msg_controllen == 0) {
        // Nothing to send.  Match the send()/sendto() convention of raising
        // EINVAL rather than silently succeeding.
        lua_settop(L, 0);
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "sendmsg");
        return 2;
    }

    rv = sendmsg(s->fd, &data, flgs);
    if (rv == -1) {
        int err = errno;
        lua_settop(L, 0);
        if (err == EAGAIN || err == EWOULDBLOCK || err == EINTR) {
            lua_pushinteger(L, 0);
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        // Got error (closed by peer: EPIPE || ECONNRESET)
        lua_pushnil(L);
        lua_errno_new(L, err, "sendmsg");
        return 2;
    }
    lua_pushinteger(L, rv);
    lua_pushnil(L);
    // again == true if we haven't sent everything (only meaningful when there
    // was payload data in the iov).
    lua_pushboolean(L, msgbuf != NULL && msglen > (size_t)rv);
    return 3;
}

static inline int checkfile(lua_State *L, int idx)
{
    if (lauxh_isinteger(L, idx)) {
        return lua_tointeger(L, idx);
    }
    return fileno(lauxh_checkfile(L, idx));
}

#if defined(HAVE_SENDFILE)

# if defined(__linux__)
#  include <sys/sendfile.h>

static int sendfile_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int fd          = checkfile(L, 2);
    size_t len      = (size_t)lauxh_checkinteger(L, 3);
    off_t offset    = (off_t)lauxh_optinteger(L, 4, 0);
    ssize_t rv      = 0;

    if (!len) {
        // invalid length
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "sendfile_lua");
        return 2;
    } else if ((rv = sendfile(s->fd, fd, &offset, len)) != -1) {
        lua_pushinteger(L, rv);
        if (len - (size_t)rv) {
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        return 1;
    } else if (errno == EAGAIN || errno == EINTR) {
        // again
        lua_pushinteger(L, 0);
        lua_pushnil(L);
        lua_pushboolean(L, 1);
        return 3;
    }

    // got error
    // closed by peer: EPIPE || ECONNRESET
    lua_pushnil(L);
    lua_errno_new(L, errno, "sendfile");
    return 2;
}

# elif defined(__APPLE__)

static int sendfile_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int fd          = checkfile(L, 2);
    off_t len       = (off_t)lauxh_checkinteger(L, 3);
    off_t offset    = (off_t)lauxh_optinteger(L, 4, 0);

    // invalid length
    if (!len) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "sendfile_lua");
        return 2;
    } else if (sendfile(fd, s->fd, offset, &len, NULL, 0) != -1) {
        lua_pushinteger(L, len);
        return 1;
    } else if (errno == EAGAIN || errno == EINTR) {
        // again
        lua_pushinteger(L, len);
        lua_pushnil(L);
        lua_pushboolean(L, 1);
        return 3;
    }

    // got error
    // closed by peer: EPIPE
    lua_pushnil(L);
    lua_errno_new(L, errno, "sendfile");
    return 2;
}

# elif defined(__DragonFly__) || defined(__FreeBSD__) ||                       \
     defined(__NetBSD__) || defined(__OpenBSD__)

static int sendfile_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int fd          = checkfile(L, 2);
    size_t len      = (size_t)lauxh_checkinteger(L, 3);
    off_t offset    = (off_t)lauxh_optinteger(L, 4, 0);
    off_t nbytes    = 0;

    if (!len) {
        // invalid length
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "sendfile_lua");
        return 2;
    } else if (sendfile(fd, s->fd, offset, len, NULL, &nbytes, 0) != -1) {
        lua_pushinteger(L, nbytes);
        return 1;
    } else if (errno == EAGAIN || errno == EINTR) {
        // again
        lua_pushinteger(L, nbytes);
        lua_pushnil(L);
        lua_pushboolean(L, 1);
        return 3;
    }

    // got error
    // closed by peer: EPIPE
    lua_pushnil(L);
    lua_errno_new(L, errno, "sendfile");
    return 2;
}

# else

// sendfile does not supported in this platform
#  undef HAVE_SENDFILE

# endif
#endif

#if !defined(HAVE_SENDFILE)

// sendfile implements for unsupported platform
static int sendfile_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int fd          = checkfile(L, 2);
    size_t len      = (size_t)lauxh_checkinteger(L, 3);
    off_t offset    = (off_t)lauxh_optinteger(L, 4, 0);
    ssize_t nbytes  = 0;
    void *buf       = NULL;

    lua_settop(L, 0);

    // invalid length
    if (!len) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "sendfile_lua");
        return 2;
    }

    // read data from file
    buf    = lua_newuserdata(L, len);
    nbytes = pread(fd, buf, len, offset);
    if (!nbytes) {
        // reached to end-of-file
        lua_pushinteger(L, 0);
        return 1;
    } else if (nbytes == -1) {
        // again
        if (errno == EAGAIN || errno == EINTR) {
            lua_pushinteger(L, 0);
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        lua_pushnil(L);
        lua_errno_new(L, errno, "pread");
        return 2;
    }

    nbytes = send(s->fd, buf, nbytes, 0);
    switch (nbytes) {
    case -1:
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            // again
            lua_pushinteger(L, 0);
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        // got error
        // closed by peer: EPIPE || ECONNRESET
        lua_pushnil(L);
        lua_errno_new(L, errno, "send");
        return 2;

    default:
        lua_pushinteger(L, nbytes);
        if (len - (size_t)nbytes) {
            lua_pushnil(L);
            lua_pushboolean(L, len - (size_t)nbytes);
            return 3;
        }
        return 1;
    }
}

#endif

static int recv_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    lua_Integer len = lauxh_optinteger(L, 2, DEFAULT_RECVSIZE);
    int flg         = net_check_msgflags(L, 3);
    char *buf       = NULL;
    ssize_t rv      = 0;

    lua_settop(L, 0);

    // invalid length
    if (len <= 0) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "recv_lua");
        return 2;
    }

    buf = lua_newuserdata(L, len);
    rv  = recv(s->fd, buf, (size_t)len, flg);
    switch (rv) {
    case -1:
        // got error
        lua_pushnil(L);
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            // again
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        lua_errno_new(L, errno, "recv");
        return 2;

    case 0:
        // close by peer
        if (s->socktype != SOCK_DGRAM && s->socktype != SOCK_RAW) {
            return 0;
        }
        // fall through

    default:
        lua_pushlstring(L, buf, rv);
        return 1;
    }
}

static int recvfrom_lua(lua_State *L)
{
    net_socket_t *s             = lauxh_checkudata(L, 1, SOCKET_MT);
    lua_Integer len             = lauxh_optinteger(L, 2, DEFAULT_RECVSIZE);
    int flg                     = net_check_msgflags(L, 3);
    socklen_t slen              = sizeof(struct sockaddr_storage);
    struct sockaddr_storage src = {0};
    ssize_t rv                  = 0;
    char *buf                   = NULL;

    // invalid length
    if (len <= 0) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "recvfrom_lua");
        return 2;
    }

    buf = lua_newuserdata(L, len);
    rv = recvfrom(s->fd, buf, (size_t)len, flg, (struct sockaddr *)&src, &slen);
    switch (rv) {
    case -1:
        // got error
        lua_pushnil(L);
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            // again
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        lua_errno_new(L, errno, "recvfrom");
        return 2;

    case 0:
        // close by peer
        if (s->socktype != SOCK_DGRAM && s->socktype != SOCK_RAW) {
            return 0;
        }
        // fall-through

    default:
        lua_pushlstring(L, buf, rv);
        if (slen > 0) {
            // with addrinfo
            struct addrinfo wrap = {
                .ai_flags     = 0,
                .ai_family    = s->family,
                .ai_socktype  = s->socktype,
                .ai_protocol  = s->protocol,
                .ai_addrlen   = slen,
                .ai_addr      = (struct sockaddr *)&src,
                .ai_canonname = NULL,
                .ai_next      = NULL,
            };

            lua_pushnil(L);
            lua_pushnil(L);
            // push the addrinfo object to Lua stack
            net_addrinfo_new(L, &wrap);
            return 4;
        }
        // no addrinfo
        return 1;
    }
}

static int recvfd_lua(lua_State *L)
{
    net_socket_t *s        = lauxh_checkudata(L, 1, SOCKET_MT);
    int flg                = net_check_msgflags(L, 2);
    char empty_iov_base    = 0;
    struct iovec empty_iov = {
        .iov_base = &empty_iov_base,
        .iov_len  = sizeof(empty_iov_base),
    };
    union {
        unsigned char buf[CMSG_SPACE(sizeof(int))];
        struct cmsghdr data;
    } ctrl = {
        .data.cmsg_len   = CMSG_LEN(sizeof(int)),
        .data.cmsg_level = 0,
        .data.cmsg_type  = 0,
    };
    struct msghdr data = (struct msghdr){
        .msg_name       = NULL,
        .msg_namelen    = 0,
        .msg_iov        = &empty_iov,
        .msg_iovlen     = 1,
        .msg_control    = &ctrl.data,
        .msg_controllen = ctrl.data.cmsg_len,
        .msg_flags      = 0,
    };
    ssize_t rv = recvmsg(s->fd, &data, flg);

    switch (rv) {
    case -1:
        // got error
        lua_pushnil(L);
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            // again
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        lua_errno_new(L, errno, "recvmsg");
        return 2;

    default:
        if (ctrl.data.cmsg_level == SOL_SOCKET &&
            ctrl.data.cmsg_type == SCM_RIGHTS) {
            lua_pushinteger(L, *(int *)CMSG_DATA(&ctrl.data));
            return 1;
        } else if (!rv && s->socktype != SOCK_DGRAM &&
                   s->socktype != SOCK_RAW) {
            // close by peer
            return 0;
        }

        // again - discard received messages
        lua_pushnil(L);
        lua_pushnil(L);
        lua_pushboolean(L, 1);
        return 3;
    }
}

static int recvmsg_lua(lua_State *L)
{
    net_socket_t *s                = lauxh_checkudata(L, 1, SOCKET_MT);
    // arg 2 : bufsize (optional, integer)
    lua_Integer bufsize            = lauxh_optinteger(L, 2, 0);
    // arg 3 : cmsgbuf (optional, integer)
    lua_Integer cmsgbuf_size       = lauxh_optinteger(L, 3, 0);
    // args 4+ : flags
    int flg                        = net_check_msgflags(L, 4);
    char *databuf                  = NULL;
    unsigned char *controlbuf      = NULL;
    struct iovec iov               = {0};
    struct sockaddr_storage src_ss = {0};
    struct msghdr data             = {
        .msg_name       = &src_ss,
        .msg_namelen    = sizeof(src_ss),
        .msg_iov        = NULL,
        .msg_iovlen     = 0,
        .msg_control    = NULL,
        .msg_controllen = 0,
        .msg_flags      = 0,
    };
    ssize_t rv = 0;

    if (bufsize < 0) {
        return luaL_argerror(L, 2, "bufsize must be non-negative");
    } else if (cmsgbuf_size < 0) {
        return luaL_argerror(L, 3, "cmsgbuf must be non-negative");
    } else if (bufsize == 0 && cmsgbuf_size == 0) {
        // Neither data nor cmsg was requested.
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "recvmsg");
        return 2;
    }

    if (bufsize > 0) {
        // Allocate a userdata buffer for the data to be received.
        databuf         = (char *)lua_newuserdata(L, (size_t)bufsize);
        iov.iov_base    = databuf;
        iov.iov_len     = (size_t)bufsize;
        data.msg_iov    = &iov;
        data.msg_iovlen = 1;
    }

    if (cmsgbuf_size > 0) {
        // Allocate a userdata buffer for the control messages to be received.
        controlbuf = (unsigned char *)lua_newuserdata(L, (size_t)cmsgbuf_size);
        data.msg_control    = controlbuf;
        data.msg_controllen = (socklen_t)cmsgbuf_size;
    }

    rv = recvmsg(s->fd, &data, flg);
    if (rv == -1) {
        int err = errno;
        if (err == EAGAIN || err == EWOULDBLOCK || err == EINTR) {
            lua_pushnil(L);
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        lua_pushnil(L);
        lua_errno_new(L, err, "recvmsg");
        return 2;
    }

    // EOF check: for stream sockets, rv == 0 with no cmsg means the peer
    // closed the connection.  Return all nil to match recv()'s convention.
    if (bufsize > 0 && rv == 0 && data.msg_controllen == 0 &&
        s->socktype != SOCK_DGRAM && s->socktype != SOCK_RAW) {
        return 0;
    }

    // Build the msg table on the Lua stack.
    lua_createtable(L, 0, 3);
    if (bufsize > 0) {
        lua_pushlstring(L, databuf, (size_t)rv);
        lua_setfield(L, -2, "data");
    }
    if (net_cmsg_push_table(L, &data)) {
        lua_setfield(L, -2, "cmsgs");
    }

    if (data.msg_namelen > 0) {
        struct addrinfo ai = {
            .ai_flags     = 0,
            .ai_family    = ((struct sockaddr *)&src_ss)->sa_family,
            .ai_socktype  = s->socktype,
            .ai_protocol  = s->protocol,
            .ai_addrlen   = data.msg_namelen,
            .ai_addr      = (struct sockaddr *)&src_ss,
            .ai_canonname = NULL,
            .ai_next      = NULL,
        };
        net_addrinfo_new(L, &ai);
        lua_setfield(L, -2, "addr");
    }

    return 1;
}

static int write_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    size_t len      = 0;
    const char *buf = lauxh_checklstring(L, 2, &len);
    ssize_t rv      = 0;

    // invalid length
    if (!len) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "write_lua");
        return 2;
    }

    rv = write(s->fd, buf, len);
    switch (rv) {
    case -1:
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            // again
            lua_pushinteger(L, 0);
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        // got error
        // closed by peer: EPIPE || ECONNRESET
        lua_pushnil(L);
        lua_errno_new(L, errno, "write");
        return 2;

    default:
        lua_pushinteger(L, rv);
        lua_pushnil(L);
        lua_pushboolean(L, len - (size_t)rv);
        return 3;
    }
}

static int read_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    lua_Integer len = lauxh_optinteger(L, 2, DEFAULT_RECVSIZE);
    char *buf       = NULL;
    ssize_t rv      = 0;

    lua_settop(L, 0);

    // invalid length
    if (len <= 0) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "read_lua");
        return 2;
    }

    buf = lua_newuserdata(L, len);
    rv  = read(s->fd, buf, (size_t)len);
    switch (rv) {
    // got error
    case -1:
        lua_pushnil(L);
        // again
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        // got error
        lua_errno_new(L, errno, "read");
        return 2;

    case 0:
        if (s->socktype != SOCK_DGRAM && s->socktype != SOCK_RAW) {
            // close by peer
            return 0;
        }
        // fall through

    default:
        lua_pushlstring(L, buf, rv);
        return 1;
    }
}

static int connect_lua(lua_State *L)
{
    net_socket_t *s      = lauxh_checkudata(L, 1, SOCKET_MT);
    net_addrinfo_t *info = lauxh_checkudata(L, 2, NET_ADDRINFO_MT);

    if (connect(s->fd, info->ai.ai_addr, info->ai.ai_addrlen) == 0 ||
        errno == EALREADY) {
        // connect completed synchronously, or a previous non-blocking
        // connect() attempt is still in progress; either way the socket is
        // owned by the kernel and the caller only needs to wait for I/O
        // readiness to finish the handshake.
        lua_pushboolean(L, 1);
        return 1;
    } else if (errno == EINPROGRESS) {
        // non-blocking connect started; the caller should wait for the
        // socket to become writable before checking SO_ERROR.
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        lua_pushboolean(L, 1);
        return 3;
    }

    // any other errno (ECONNREFUSED, ETIMEDOUT, EAGAIN, EPIPE, ...) is a
    // terminal error: the fd cannot be re-used to retry the same connect().
    lua_pushboolean(L, 0);
    lua_errno_new(L, errno, "connect");
    return 2;
}

static inline int select_lua(lua_State *L, int receivable, int sendable)
{
    net_socket_t *s        = lauxh_checkudata(L, 1, SOCKET_MT);
    lua_Number sec         = luaL_optnumber(L, 2, 0);
    int except             = lauxh_optboolean(L, 3, 0);
    struct timeval timeout = {.tv_sec = 0, .tv_usec = 0};
    fd_set *rptr           = NULL;
    fd_set *wptr           = NULL;
    fd_set *eptr           = NULL;
    fd_set rfds;
    fd_set wfds;
    fd_set efds;

    lua_settop(L, 0);
    if (sec > 0) {
        timeout.tv_sec  = sec;
        timeout.tv_usec = (sec - (lua_Number)timeout.tv_sec) * 1000000;
    }

    // select receivable
    if (receivable) {
        rptr = &rfds;
        FD_ZERO(rptr);
        FD_SET(s->fd, rptr);
    }
    // select sendable
    if (sendable) {
        wptr = &wfds;
        FD_ZERO(wptr);
        FD_SET(s->fd, wptr);
    }
    // select exception
    if (except) {
        eptr = &efds;
        FD_ZERO(eptr);
        FD_SET(s->fd, eptr);
    }

    // wait until usable or exceeded timeout
    switch (select(s->fd + 1, rptr, wptr, eptr, &timeout)) {
    case 0:
        // timeout
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        lua_pushboolean(L, 1);
        return 3;

    case -1:
        // got error
        lua_pushboolean(L, 0);
        lua_errno_new(L, errno, "select");
        return 2;

    default:
        // selected
        lua_pushboolean(L, 1);
        return 1;
    }
}

static int sendable_lua(lua_State *L)
{
    return select_lua(L, 0, 1);
}

static int recvable_lua(lua_State *L)
{
    return select_lua(L, 1, 0);
}

static int bind_lua(lua_State *L)
{
    net_socket_t *s      = lauxh_checkudata(L, 1, SOCKET_MT);
    net_addrinfo_t *info = lauxh_checkudata(L, 2, NET_ADDRINFO_MT);

    if (bind(s->fd, (struct sockaddr *)info->ai.ai_addr, info->ai.ai_addrlen) ==
        0) {
        lua_pushboolean(L, 1);
        return 1;
    }

    // got error
    lua_pushboolean(L, 0);
    lua_errno_new(L, errno, "bind");
    return 2;
}

static int protocol_lua(lua_State *L)
{
    net_socket_t *s  = lauxh_checkudata(L, 1, SOCKET_MT);
    const char *name = net_protocol_name(s->protocol);

    if (!name) {
        return luaL_error(L, "unsupported protocol value: %d", s->protocol);
    }
    lua_pushstring(L, name);
    return 1;
}

static int socktype_lua(lua_State *L)
{
    net_socket_t *s  = lauxh_checkudata(L, 1, SOCKET_MT);
    const char *name = net_socktype_name(s->socktype);

    if (!name) {
        return luaL_error(L, "unsupported socket type value: %d", s->socktype);
    }
    lua_pushstring(L, name);
    return 1;
}

static int family_lua(lua_State *L)
{
    net_socket_t *s  = lauxh_checkudata(L, 1, SOCKET_MT);
    const char *name = net_family_name(s->family);

    if (!name) {
        return luaL_error(L, "unsupported address family value: %d", s->family);
    }
    lua_pushstring(L, name);
    return 1;
}

static int fd_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    lua_pushinteger(L, s->fd);
    return 1;
}

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, SOCKET_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);

    if (s->fd != -1) {
        net_gcthread_close(L, s);
        close(s->fd);
        s->fd = -1;
    }
    return 0;
}

static int dup_lua(lua_State *L)
{
    net_socket_t *s  = lauxh_checkudata(L, 1, SOCKET_MT);
    net_socket_t *sd = lua_newuserdata(L, sizeof(net_socket_t));

    // Initialize the new socket object with the same properties as the original
    // socket.
    *sd = (net_socket_t){
        .family        = s->family,
        .socktype      = s->socktype,
        .protocol      = s->protocol,
        .gc_thread_ref = LUA_NOREF,
        .gc_thread     = lua_newthread(L),
    };

    // Duplicate the file descriptor and set it to close-on-exec.
    sd->fd = dup(s->fd);
    if (sd->fd == -1) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "dup");
        return 2;
    } else if (set_cloexec(sd->fd) == -1) {
        close(sd->fd);
        lua_pushnil(L);
        lua_errno_new(L, errno, "fcntl");
        return 2;
    }
    sd->gc_thread_ref = lauxh_ref(L);
    lauxh_setmetatable(L, SOCKET_MT);

    return 1;
}

static int delgcfn_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    return net_gcthread_del(L, s, 2);
}

static int addgcfn_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    return net_gcthread_add(L, s, 2);
}

static int unwrap_lua(lua_State *L)
{
    net_socket_t *s = lauxh_checkudata(L, 1, SOCKET_MT);
    int fd          = s->fd;

    // Unwrap the socket by closing the associated garbage collection thread and
    // setting the file descriptor to -1. This effectively disables the socket
    // object while returning the original file descriptor to the caller.
    lua_settop(L, 1);
    net_gcthread_close(L, s);

    // remove metatable
    lua_pushnil(L);
    lua_setmetatable(L, -2);
    s->fd = -1;

    // return fd
    lua_pushinteger(L, fd);
    return 1;
}

static int wrap_lua(lua_State *L)
{
    int fd = (int)lauxh_checkinteger(L, 1);
    struct sockaddr_storage addr;
    socklen_t addrlen = sizeof(struct sockaddr_storage);
    net_socket_t *s   = NULL;
    socklen_t typelen = sizeof(int);
#if defined(SO_PROTOCOL)
    socklen_t protolen = sizeof(int);
#endif

    lua_settop(L, 1);

    // allocate a new socket userdata and initialize it with the provided file
    // descriptor.
    s  = lua_newuserdata(L, sizeof(net_socket_t));
    *s = (net_socket_t){
        .fd            = fd,
        .family        = 0,
        .socktype      = 0,
        .protocol      = 0,
        .gc_thread_ref = LUA_NOREF,
        .gc_thread     = lua_newthread(L),
    };

    if (getsockname(fd, (void *)&addr, &addrlen) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "getsockname");
        return 2;
    } else if (
#if defined(SO_PROTOCOL)
        getsockopt(fd, SOL_SOCKET, SO_PROTOCOL, &s->protocol, &protolen) != 0 ||
#endif
        getsockopt(fd, SOL_SOCKET, SO_TYPE, &s->socktype, &typelen) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "getsockopt");
        return 2;
    } else if (set_nonblock(fd) == -1) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "fcntl");
        return 2;
    }

    // Set the socket family and protocol based on the retrieved information.
    s->family = addr.ss_family;
#if !defined(SO_PROTOCOL)
    s->protocol = 0;
#endif
    s->gc_thread_ref = lauxh_ref(L);
    lauxh_setmetatable(L, SOCKET_MT);

    return 1;
}

static int shutdownfd_lua(lua_State *L)
{
    int fd  = (int)lauxh_checkinteger(L, 1);
    int how = checkshutflag(L, 2, SHUT_RDWR);
    return shutdownfd(L, fd, how);
}

static int closefd_lua(lua_State *L)
{
    int fd            = (int)lauxh_checkinteger(L, 1);
    int with_shutdown = !lua_isnoneornil(L, 2);
    int how           = checkshutflag(L, 2, -1);
    return closefd(L, fd, how, with_shutdown);
}

// Parsed opts destination for net.socket.new / net.socket.pair.
typedef enum {
    // inet stream/dgram operations
    OP_NEW_INET = 0x1,
    OP_NEW_INET6,
    OP_BIND_INET,
    OP_CONNECT_INET,

    // unix stream/dgram operations
    OP_NEW_UNIX = 0x80,
    OP_BIND_UNIX,
    OP_CONNECT_UNIX,
#define IS_UNIX_OP(op) ((op) & 0x80)

} so_operation_t;

const char *so_operation_to_string(so_operation_t op_type)
{
    switch (op_type) {
    case OP_NEW_INET:
        return "socket.new_inet";
    case OP_NEW_INET6:
        return "socket.new_inet6";
    case OP_BIND_INET:
        return "socket.bind_inet";
    case OP_CONNECT_INET:
        return "socket.connect_inet";

    case OP_NEW_UNIX:
        return "socket.new_unix";
    case OP_BIND_UNIX:
        return "socket.bind_unix";
    case OP_CONNECT_UNIX:
        return "socket.connect_unix";

    default:
        return "unknown_op_type";
    }
}

typedef struct {
    so_operation_t op;
    net_addrinfo_t *addr;
    sockopts_t opts;
    int family;
    int socktype;
    int protocol;
} so_config_t;

static int check_constant(lua_State *L, const char *name, const char *kind,
                          int (*lookup)(const char *, int *), int *out)
{
    const char *s = NULL;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }

    s = lua_tostring(L, -1);
    if (lookup(s, out)) {
        return 0;
    }
    return luaL_error(L, "opts.%s='%s' is not a recognized %s", name, s, kind);
}

/**
 * @brief opts.socktype callback: map string to SOCK_* and store in
 * `((so_config_t *)ctx)->socktype`.
 */
static int check_socktype(lua_State *L, const char *name, void *ctx)
{
    so_config_t *cfg = ctx;
    return check_constant(L, name, "socket type", net_socktype_value,
                          &cfg->socktype);
}

/**
 * @brief opts.protocol callback: map string to IPPROTO_* and store in
 * `((so_config_t *)ctx)->protocol`.
 */
static int check_protocol(lua_State *L, const char *name, void *ctx)
{
    so_config_t *cfg = ctx;
    return check_constant(L, name, "protocol", net_protocol_value,
                          &cfg->protocol);
}

// low-level socketpair(): net.socket.pair({ socktype=..., protocol=... })
//
// The family is always AF_UNIX (socketpair(2) only supports it), so opts.family
// is not accepted.  socktype is required; protocol defaults to "auto"=0.
static int pair_lua(lua_State *L)
{
    static const net_socket_option_spec_t SPECS[] = {
        {"socktype", check_socktype},
        {"protocol", check_protocol},
    };
    so_config_t cfg = {
        .family   = AF_UNIX,
        .socktype = -1,
        .protocol = 0,
    };
    int fds[2]         = {-1, -1};
    net_socket_t *s[2] = {NULL, NULL};

    NET_SOCKET_CHECK_OPTIONS(L, 1, SPECS, &cfg);
    if (cfg.socktype == -1) {
        return luaL_error(L, "opts.socktype is required");
    }

    // create a table to hold the two socket userdata
    lua_settop(L, 0);
    lua_createtable(L, 2, 0);
    for (int i = 0; i < 2; i++) {
        s[i]  = lua_newuserdata(L, sizeof(net_socket_t));
        *s[i] = (net_socket_t){
            .fd            = -1,
            .family        = AF_UNIX,
            .socktype      = cfg.socktype,
            .protocol      = cfg.protocol,
            .gc_thread_ref = LUA_NOREF,
            .gc_thread     = lua_newthread(L),
        };
        s[i]->gc_thread_ref = lauxh_ref(L);
        lauxh_setmetatable(L, SOCKET_MT);
        lua_rawseti(L, -2, i + 1);
    }

    // create the socketpair and store the fds in the pre-allocated userdata
    if (socketpair(AF_UNIX, cfg.socktype, cfg.protocol, fds) != 0) {
        lua_pushnil(L);
        lua_errno_new(L, errno, "pair");
        return 2;
    }

    // set FD_CLOEXEC and O_NONBLOCK on both fds, closing both fds and returning
    // an error if either fcntl() fails.
    for (int i = 0; i < 2; i++) {
        if (set_cloexec_nonblock(fds[i]) == -1) {
            int err = errno;
            close(fds[0]);
            close(fds[1]);
            lua_pushnil(L);
            lua_errno_new(L, err, "socketpair");
            return 2;
        }
    }

    // ownership of both fds transfers to the pre-allocated userdata
    s[0]->fd = fds[0];
    s[1]->fd = fds[1];

    return 1;
}

static net_socket_t *new_socket(lua_State *L, so_config_t *cfg)
{
    net_socket_t *s = lua_newuserdata(L, sizeof(net_socket_t));

    if (cfg->addr) {
        // addr-driven: family/socktype/protocol come from the resolved
        // addrinfo (used by bind_inet/connect_inet/bind_unix/connect_unix
        // via new_net_socket()).
        *s = (net_socket_t){
            .family        = cfg->addr->ai.ai_family,
            .socktype      = cfg->addr->ai.ai_socktype,
            .protocol      = cfg->addr->ai.ai_protocol,
            .gc_thread_ref = LUA_NOREF,
            .gc_thread     = lua_newthread(L),
        };
    } else {
        // addr-less: raw socket() with the caller-supplied family and
        // opts.socktype / opts.protocol (used by new_inet / new_inet6 /
        // new_unix).
        *s = (net_socket_t){
            .family        = cfg->family,
            .socktype      = cfg->socktype,
            .protocol      = cfg->protocol,
            .gc_thread_ref = LUA_NOREF,
            .gc_thread     = lua_newthread(L),
        };
    }
    s->fd = socket(s->family, s->socktype, s->protocol);
    if (s->fd == -1) {
        // socket(2) failed, return the error to the callback
        // pop the socket userdata and gc_thread
        lua_pop(L, 2);
        return NULL;
    }
    // store a reference to the gc thread in the socket userdata so that it can
    // be used later for cleanup when the socket is closed.
    s->gc_thread_ref = lauxh_ref(L);
    lauxh_setmetatable(L, SOCKET_MT);

    if (set_cloexec_nonblock(s->fd) == -1 ||
        sockopts_apply(s->fd, s->family, &cfg->opts) != 0) {
        // set_cloexec_nonblock failed, close the socket and return the error to
        // the callback
        int err = errno;
        close(s->fd);
        s->fd = -1;
        errno = err;
        lua_pop(L, 1);
        return NULL;
    }

    return s;
}

/**
 * @brief Create a new network socket with the specified operation, options, and
 * resolver function. The function resolves the address information using the
 * provided resolver and then creates a new socket based on the resolved
 * address. The callback function is called with the created socket or an error
 * if the socket creation fails.
 *
 * @param L The Lua state.
 * @param op The socket operation type (e.g., OP_NEW_INET,
 * OP_BIND_UNIX).
 * @param spec The option specifications for the socket operation.
 * @param nspecs The number of option specifications.
 * @param resolver The name of the resolver function to use for address
 * resolution.
 * @param cb The callback function to be called with the created socket or an
 * error.
 * @return int The number of return values pushed onto the Lua stack. Returns 1
 * on success (the created socket), or 2 on failure (nil and an error message).
 */
static int new_net_socket(lua_State *L, so_operation_t op,
                          const net_socket_option_spec_t specs[], int nspecs,
                          const char *resolver)
{
    int top         = lua_gettop(L);
    so_config_t cfg = {
        .op = op,
    };
    int addrindex = 1;
    int tblindex  = 0;
    int optindex  = 2;
    int err       = 0;

// unix socket arguments: pathname|ai, opts
// inet socket argument: <host, port>|ai, opts
#define DO_CHECK_OPTIONS()                                                     \
    if (optindex <= top) {                                                     \
        net_socket_check_options(L, optindex, specs, nspecs, &cfg.opts);       \
    }

    // If the first argument is not a net.addrinfo userdata, call the
    // resolver function to resolve the address information. The resolver
    // function is expected to return either a net.addrinfo userdata or a
    // table of net.addrinfo userdata on success, or nil + err on failure.
    if (!lauxh_isuserdataof(L, 1, NET_ADDRINFO_MT)) {
        char code[256] = {0};

        // set the index of the options argument based on the operation type
        if (!IS_UNIX_OP(op)) {
            optindex = 3;
        }

        // copy the arguments to the top of the stack for the resolver function
        for (int i = 1; i <= top; i++) {
            lua_pushvalue(L, i);
        }

        // Call the resolver function in the net.addrinfo module with the copied
        // arguments.
        snprintf(code, sizeof(code), "return require('net.addrinfo').%s(...)",
                 resolver);
        dostring(L, code, top + 1, LUA_MULTRET);

        // The resolver function should return either a net.addrinfo userdata or
        // a table of net.addrinfo userdata on success, or nil + err on failure.
        switch (lua_gettop(L) - top) {
        default:
            // got unexpected return value from resolver function, return an
            // error
            lua_settop(L, top);
            lua_pushnil(L);
            lua_pushfstring(L, "%s: unexpected return value from %s",
                            so_operation_to_string(op), resolver);
            lua_error_new(L, -1);
            return 2;

        case 2:
            lua_pushfstring(
                L, "%s: failed to resolve arguments via net.addrinfo.%s",
                so_operation_to_string(op), resolver);
            lua_insert(L, lua_gettop(L) - 1);
            lua_error_new(L, -2);
            return 2;

        case 1:
            // success: return the net.addrinfo userdata or table of
            // net.addrinfo userdata on top of the stack
            addrindex = top + 1;
            if (lua_istable(L, addrindex)) {
                tblindex  = addrindex;
                addrindex = -1;
                DO_CHECK_OPTIONS();
                lua_pushnil(L);
                goto CHECK_NEXT_ADDR;
            }
            break;
        }
    }

    DO_CHECK_OPTIONS();

#undef DO_CHECK_OPTIONS

    do {
        net_socket_t *s = NULL;
        if (lauxh_isuserdataof(L, addrindex, NET_ADDRINFO_MT)) {
            cfg.addr = (net_addrinfo_t *)lua_touserdata(L, addrindex);
            s        = new_socket(L, &cfg);
        }

        if (s) {
            errno = 0;
            switch (op) {
            case OP_NEW_INET:
            case OP_NEW_UNIX:
                // no additional action needed for new socket
                return 1;

            case OP_BIND_INET:
            case OP_BIND_UNIX:
                if (bind(s->fd, cfg.addr->ai.ai_addr,
                         cfg.addr->ai.ai_addrlen) == 0) {
                    return 1;
                }
                break;

            case OP_CONNECT_INET:
            case OP_CONNECT_UNIX:
                if (connect(s->fd, cfg.addr->ai.ai_addr,
                            cfg.addr->ai.ai_addrlen) == 0) {
                    return 1;
                } else if (errno == EINPROGRESS) {
                    // non-blocking connect in progress
                    lua_pushnil(L);
                    lua_pushboolean(L, 1);
                    return 3;
                }
                break;

            default:
                // unknown operation type
                lua_pushnil(L);
                lua_pushfstring(L, "%s: unknown operation type",
                                so_operation_to_string(op));
                lua_error_new(L, -1);
                return 2;
            }

            // close the socket and remove it from the stack
            err = errno;
            close(s->fd);
            s->fd = -1;
            lua_pop(L, 1);
        }

        lua_pop(L, 1);

CHECK_NEXT_ADDR:;
    } while (tblindex && lua_next(L, tblindex) != 0);

    // If we reach here, it means that we have exhausted all the addresses in
    // the table (if any) and failed to create a socket.  Set errno to the last
    // error encountered (if any) or EADDRNOTAVAIL if no error was encountered,
    // and return nil + err to the caller.
    lua_settop(L, 0);
    lua_pushnil(L);
    errno = err ? err : EADDRNOTAVAIL;
    lua_errno_new(L, errno, so_operation_to_string(op));
    return 2;
}

// Common implementation for new_inet / new_inet6 / new_unix: create a raw
// socket(family, opts.socktype, opts.protocol) with FD_CLOEXEC + O_NONBLOCK
// and apply setsockopt keys listed in `specs`.  This is a pure socket(2)
// creation path with no getaddrinfo / bind / connect side-effects; the
// caller uses the returned socket via s:bind(ai) / s:connect(ai) later.
static int new_raw_socket_lua(lua_State *L, so_operation_t op, int family,
                              const net_socket_option_spec_t specs[],
                              int nspecs)
{
    so_config_t cfg = {
        .op       = op,
        .family   = family,
        .socktype = -1,
        .protocol = 0,
    };
    net_socket_t *s = NULL;

    // The specs share a single ctx = &cfg: check_socktype / check_protocol
    // write into cfg.socktype / cfg.protocol, while cfg_check_* wrappers
    // forward setsockopt keys into cfg.opts.
    net_socket_check_options(L, 1, specs, nspecs, &cfg);
    if (cfg.socktype == -1) {
        return luaL_error(L, "opts.socktype is required");
    }

    lua_settop(L, 0);
    s = new_socket(L, &cfg);
    if (!s) {
        lua_pushnil(L);
        lua_errno_new(L, errno, so_operation_to_string(op));
        return 2;
    }
    return 1;
}

/**
 * @name so_config_t wrappers for sockopts_check_* callbacks
 * @brief These wrap the sockopts.h callbacks so that all specs in
 * new_inet_specs / new_inet6_specs / new_unix_specs can share a single
 * `so_config_t *` context (used by check_socktype / check_protocol) while
 * still writing setsockopt keys into `cfg->opts` (a `sockopts_t`).  Existing
 * bind_/connect_ specs used via new_net_socket() keep passing `&cfg->opts`
 * directly and are unaffected.
 */
static int cfg_check_bool(lua_State *L, const char *name, void *ctx)
{
    so_config_t *cfg = ctx;
    return sockopts_check_bool(L, name, &cfg->opts);
}

static int cfg_check_int(lua_State *L, const char *name, void *ctx)
{
    so_config_t *cfg = ctx;
    return sockopts_check_int(L, name, &cfg->opts);
}

static int cfg_check_timeval(lua_State *L, const char *name, void *ctx)
{
    so_config_t *cfg = ctx;
    return sockopts_check_timeval(L, name, &cfg->opts);
}

static int cfg_check_string(lua_State *L, const char *name, void *ctx)
{
    so_config_t *cfg = ctx;
    return sockopts_check_string(L, name, &cfg->opts);
}

// new_inet(opts): create an AF_INET socket with opts.socktype /
// opts.protocol.  The socket is not bound or connected; use s:bind(ai) /
// s:connect(ai) with an addrinfo userdata for the following step.
static int new_inet_lua(lua_State *L)
{
    static const net_socket_option_spec_t new_inet_specs[] = {
        {"socktype",     check_socktype   },
        {"protocol",     check_protocol   },
        {"broadcast",    cfg_check_bool   },
        {"debug",        cfg_check_bool   },
        {"dontroute",    cfg_check_bool   },
        {"keepalive",    cfg_check_bool   },
        {"linger",       cfg_check_int    },
        {"mcastif",      cfg_check_string },
        {"mcastloop",    cfg_check_bool   },
        {"mcastttl",     cfg_check_int    },
        {"oobinline",    cfg_check_bool   },
        {"rcvbuf",       cfg_check_int    },
        {"rcvlowat",     cfg_check_int    },
        {"rcvtimeo",     cfg_check_timeval},
        {"reuseaddr",    cfg_check_bool   },
        {"reuseport",    cfg_check_bool   },
        {"sndbuf",       cfg_check_int    },
        {"sndlowat",     cfg_check_int    },
        {"sndtimeo",     cfg_check_timeval},
        {"timestamp",    cfg_check_bool   },
        {"tcpkeepalive", cfg_check_int    },
        {"tcpkeepcnt",   cfg_check_int    },
        {"tcpkeepintvl", cfg_check_int    },
        {"tcpcork",      cfg_check_bool   },
        {"tcpnodelay",   cfg_check_bool   },
    };
    return new_raw_socket_lua(L, OP_NEW_INET, AF_INET, new_inet_specs,
                              sizeof(new_inet_specs) /
                                  sizeof(new_inet_specs[0]));
}

// new_inet6(opts): create an AF_INET6 socket with opts.socktype /
// opts.protocol.  Uses the same option set as new_inet; family-specific
// setsockopt validity (e.g. IP_MULTICAST_TTL vs IPV6_MULTICAST_HOPS) is
// handled by sockopts_apply based on the socket's family.
static int new_inet6_lua(lua_State *L)
{
    static const net_socket_option_spec_t new_inet6_specs[] = {
        {"socktype",     check_socktype   },
        {"protocol",     check_protocol   },
        {"debug",        cfg_check_bool   },
        {"dontroute",    cfg_check_bool   },
        {"keepalive",    cfg_check_bool   },
        {"linger",       cfg_check_int    },
        {"mcastif",      cfg_check_string },
        {"mcastloop",    cfg_check_bool   },
        {"mcastttl",     cfg_check_int    },
        {"oobinline",    cfg_check_bool   },
        {"rcvbuf",       cfg_check_int    },
        {"rcvlowat",     cfg_check_int    },
        {"rcvtimeo",     cfg_check_timeval},
        {"reuseaddr",    cfg_check_bool   },
        {"reuseport",    cfg_check_bool   },
        {"sndbuf",       cfg_check_int    },
        {"sndlowat",     cfg_check_int    },
        {"sndtimeo",     cfg_check_timeval},
        {"timestamp",    cfg_check_bool   },
        {"tcpkeepalive", cfg_check_int    },
        {"tcpkeepcnt",   cfg_check_int    },
        {"tcpkeepintvl", cfg_check_int    },
        {"tcpcork",      cfg_check_bool   },
        {"tcpnodelay",   cfg_check_bool   },
    };
    return new_raw_socket_lua(L, OP_NEW_INET6, AF_INET6, new_inet6_specs,
                              sizeof(new_inet6_specs) /
                                  sizeof(new_inet6_specs[0]));
}

// new_unix(opts): create an AF_UNIX socket with opts.socktype /
// opts.protocol.  The socket is not bound or connected; use s:bind(ai) /
// s:connect(ai) with a unix addrinfo userdata for the following step.
static int new_unix_lua(lua_State *L)
{
    static const net_socket_option_spec_t new_unix_specs[] = {
        {"socktype", check_socktype   },
        {"protocol", check_protocol   },
        {"debug",    cfg_check_bool   },
        {"linger",   cfg_check_int    },
        {"rcvbuf",   cfg_check_int    },
        {"rcvlowat", cfg_check_int    },
        {"rcvtimeo", cfg_check_timeval},
        {"sndbuf",   cfg_check_int    },
        {"sndlowat", cfg_check_int    },
        {"sndtimeo", cfg_check_timeval},
    };
    return new_raw_socket_lua(L, OP_NEW_UNIX, AF_UNIX, new_unix_specs,
                              sizeof(new_unix_specs) /
                                  sizeof(new_unix_specs[0]));
}

// bind_inet(host, port, opts)
static int bind_inet_lua(lua_State *L)
{
    static const net_socket_option_spec_t bind_inet_specs[] = {
        {"broadcast", sockopts_check_bool   },
        {"debug",     sockopts_check_bool   },
        {"dontroute", sockopts_check_bool   },
        {"mcastif",   sockopts_check_string },
        {"mcastloop", sockopts_check_bool   },
        {"mcastttl",  sockopts_check_int    },
        {"rcvbuf",    sockopts_check_int    },
        {"rcvlowat",  sockopts_check_int    },
        {"rcvtimeo",  sockopts_check_timeval},
        {"reuseaddr", sockopts_check_bool   },
        {"reuseport", sockopts_check_bool   },
        {"sndbuf",    sockopts_check_int    },
        {"sndlowat",  sockopts_check_int    },
        {"sndtimeo",  sockopts_check_timeval},
        {"timestamp", sockopts_check_bool   },
    };
    return new_net_socket(L, OP_BIND_INET, bind_inet_specs,
                          sizeof(bind_inet_specs) / sizeof(bind_inet_specs[0]),
                          "getaddrinfo");
}

// bind_unix(pathname|ai, opts)
static int bind_unix_lua(lua_State *L)
{
    static const net_socket_option_spec_t bind_unix_specs[] = {
        {"debug",    sockopts_check_bool   },
        {"linger",   sockopts_check_int    },
        {"rcvbuf",   sockopts_check_int    },
        {"rcvlowat", sockopts_check_int    },
        {"rcvtimeo", sockopts_check_timeval},
        {"sndbuf",   sockopts_check_int    },
        {"sndlowat", sockopts_check_int    },
        {"sndtimeo", sockopts_check_timeval},
    };
    return new_net_socket(L, OP_BIND_UNIX, bind_unix_specs,
                          sizeof(bind_unix_specs) / sizeof(bind_unix_specs[0]),
                          "unix");
}

// connect_inet(host, port, opts) or connect_inet(ai, opts)
static int connect_inet_lua(lua_State *L)
{
    static const net_socket_option_spec_t connect_inet_specs[] = {
        {"debug",        sockopts_check_bool   },
        {"dontroute",    sockopts_check_bool   },
        {"keepalive",    sockopts_check_bool   },
        {"linger",       sockopts_check_int    },
        {"oobinline",    sockopts_check_bool   },
        {"rcvbuf",       sockopts_check_int    },
        {"rcvlowat",     sockopts_check_int    },
        {"rcvtimeo",     sockopts_check_timeval},
        {"sndbuf",       sockopts_check_int    },
        {"sndlowat",     sockopts_check_int    },
        {"sndtimeo",     sockopts_check_timeval},
        {"tcpkeepalive", sockopts_check_int    },
        {"tcpkeepcnt",   sockopts_check_int    },
        {"tcpkeepintvl", sockopts_check_int    },
        {"tcpcork",      sockopts_check_bool   },
        {"tcpnodelay",   sockopts_check_bool   },
    };
    return new_net_socket(L, OP_CONNECT_INET, connect_inet_specs,
                          sizeof(connect_inet_specs) /
                              sizeof(connect_inet_specs[0]),
                          "getaddrinfo");
}

// connect_unix(pathname|ai, opts)
static int connect_unix_lua(lua_State *L)
{
    static const net_socket_option_spec_t connect_unix_specs[] = {
        {"debug",    sockopts_check_bool   },
        {"linger",   sockopts_check_int    },
        {"rcvbuf",   sockopts_check_int    },
        {"rcvlowat", sockopts_check_int    },
        {"rcvtimeo", sockopts_check_timeval},
        {"sndbuf",   sockopts_check_int    },
        {"sndlowat", sockopts_check_int    },
        {"sndtimeo", sockopts_check_timeval},
    };
    return new_net_socket(
        L, OP_CONNECT_UNIX, connect_unix_specs,
        sizeof(connect_unix_specs) / sizeof(connect_unix_specs[0]), "unix");
}

LUALIB_API int luaopen_net_socket(lua_State *L)
{
    // load dependencies: error, errno, and net.addrinfo modules
    lua_errno_loadlib(L);
    dostring(L, "require('net.addrinfo')", 0, 0);

    // create socket metatable
    if (luaL_newmetatable(L, SOCKET_MT)) {
        struct luaL_Reg mmethod[] = {
            {"__gc",       gc_lua      },
            {"__tostring", tostring_lua},
            {NULL,         NULL        }
        };
        struct luaL_Reg method[] = {
            {"addgcfn",           addgcfn_lua          },
            {"delgcfn",           delgcfn_lua          },
            {"unwrap",            unwrap_lua           },
            {"dup",               dup_lua              },
            {"fd",                fd_lua               },
            {"family",            family_lua           },
            {"socktype",          socktype_lua         },
            {"protocol",          protocol_lua         },
            {"bind",              bind_lua             },
            {"recvable",          recvable_lua         },
            {"sendable",          sendable_lua         },
            {"connect",           connect_lua          },
            {"shutdown",          shutdown_lua         },
            {"close",             close_lua            },
            {"listen",            listen_lua           },
            {"accept",            accept_lua           },
            {"acceptfd",          acceptfd_lua         },
            {"send",              send_lua             },
            {"sendto",            sendto_lua           },
            {"sendfd",            sendfd_lua           },
            {"sendmsg",           sendmsg_lua          },
            {"sendfile",          sendfile_lua         },
            {"recv",              recv_lua             },
            {"recvfrom",          recvfrom_lua         },
            {"recvfd",            recvfd_lua           },
            {"recvmsg",           recvmsg_lua          },
            {"write",             write_lua            },
            {"read",              read_lua             },

            // state
            {"atmark",            atmark_lua           },

            // address info
            {"getsockname",       getsockname_lua      },
            {"getpeername",       getpeername_lua      },

            // fd option
            {"cloexec",           cloexec_lua          },
            {"nonblock",          nonblock_lua         },

            // read-only socket option
            {"error",             error_lua            },
            {"acceptconn",        acceptconn_lua       },
            // socket option
            {"tcpnodelay",        tcpnodelay_lua       },
            {"tcpkeepintvl",      tcpkeepintvl_lua     },
            {"tcpkeepcnt",        tcpkeepcnt_lua       },
            {"tcpkeepalive",      tcpkeepalive_lua     },
            {"tcpcork",           tcpcork_lua          },
            {"reuseport",         reuseport_lua        },
            {"reuseaddr",         reuseaddr_lua        },
            {"broadcast",         broadcast_lua        },
            {"debug",             debug_lua            },
            {"keepalive",         keepalive_lua        },
            {"oobinline",         oobinline_lua        },
            {"dontroute",         dontroute_lua        },
            {"timestamp",         timestamp_lua        },
            {"ip_recvttl",        ip_recvttl_lua       },
            {"ip_recvtos",        ip_recvtos_lua       },
            {"ipv6_recvhoplimit", ipv6_recvhoplimit_lua},
            {"rcvbuf",            rcvbuf_lua           },
            {"rcvlowat",          rcvlowat_lua         },
            {"sndbuf",            sndbuf_lua           },
            {"sndlowat",          sndlowat_lua         },
            {"rcvtimeo",          rcvtimeo_lua         },
            {"sndtimeo",          sndtimeo_lua         },
            {"linger",            linger_lua           },
            // multicast
            {"mcastloop",         mcastloop_lua        },
            {"mcastttl",          mcastttl_lua         },
            {"mcastif",           mcastif_lua          },
            {"mcastjoin",         mcastjoin_lua        },
            {"mcastleave",        mcastleave_lua       },
            {"mcastjoinsrc",      mcastjoinsrc_lua     },
            {"mcastleavesrc",     mcastleavesrc_lua    },
            {"mcastblocksrc",     mcastblocksrc_lua    },
            {"mcastunblocksrc",   mcastunblocksrc_lua  },
            {NULL,                NULL                 }
        };
        struct luaL_Reg *ptr = mmethod;

        // lock metatable
        lauxh_pushnum2tbl(L, "__metatable", 1);
        // metamethods
        do {
            lauxh_pushfn2tbl(L, ptr->name, ptr->func);
            ptr++;
        } while (ptr->name);
        // methods
        lua_pushstring(L, "__index");
        lua_newtable(L);
        ptr = method;
        do {
            lauxh_pushfn2tbl(L, ptr->name, ptr->func);
            ptr++;
        } while (ptr->name);
        lua_rawset(L, -3);
    }
    lua_pop(L, 1);

    // create table
    lua_newtable(L);

    // connect both unix and inet stream sockets
    lauxh_pushfn2tbl(L, "connect_unix", connect_unix_lua);
    lauxh_pushfn2tbl(L, "connect_inet", connect_inet_lua);

    // bind both unix and inet stream sockets
    lauxh_pushfn2tbl(L, "bind_unix", bind_unix_lua);
    lauxh_pushfn2tbl(L, "bind_inet", bind_inet_lua);

    // high-level convenience functions
    lauxh_pushfn2tbl(L, "new_unix", new_unix_lua);
    lauxh_pushfn2tbl(L, "new_inet", new_inet_lua);
    lauxh_pushfn2tbl(L, "new_inet6", new_inet6_lua);

    lauxh_pushfn2tbl(L, "pair", pair_lua);

    // socket creation
    lauxh_pushfn2tbl(L, "wrap", wrap_lua);
    lauxh_pushfn2tbl(L, "close", closefd_lua);
    lauxh_pushfn2tbl(L, "shutdown", shutdownfd_lua);

    return 1;
}
