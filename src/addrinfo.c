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
 *
 *  Created by Masatoshi Teruya on 15/12/14.
 */

#define _GNU_SOURCE
#if defined(__APPLE__) && !defined(__APPLE_USE_RFC_3542)
# define __APPLE_USE_RFC_3542
#endif
#include "config.h"
// project
#include "addrinfo.h"
#include "constants.h"
// depend
#include "lauxhlib.h"
#include "lua_errno.h"
// lua
#include <lauxlib.h>
// system
#include <arpa/inet.h>
#include <math.h>
#include <netdb.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>

// opts parsing framework (shared with src/socket.c)
#include "optcheck.h"

/**
 * @brief opts.family callback: map string to AF_* and store in
 * `((struct addrinfo *)ctx)->ai_family`.
 */
static int check_family(lua_State *L, const char *name, void *ctx)
{
    struct addrinfo *hints = ctx;
    const char *s          = NULL;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    s = lua_tostring(L, -1);
    if (net_family_value(s, &hints->ai_family)) {
        return 0;
    }
    return luaL_error(L, "invalid opts.%s value: '%s'", name, s);
}

/**
 * @brief opts.socktype callback: map string to SOCK_* and store in
 * `((struct addrinfo *)ctx)->ai_socktype`.
 */
static int check_socktype(lua_State *L, const char *name, void *ctx)
{
    struct addrinfo *hints = ctx;
    const char *s          = NULL;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    s = lua_tostring(L, -1);
    if (net_socktype_value(s, &hints->ai_socktype)) {
        return 0;
    }
    return luaL_error(L, "invalid opts.%s value: '%s'", name, s);
}

/**
 * @brief opts.protocol callback: map string to IPPROTO_* and store in
 * `((struct addrinfo *)ctx)->ai_protocol`.
 */
static int check_protocol(lua_State *L, const char *name, void *ctx)
{
    struct addrinfo *hints = ctx;
    const char *s          = NULL;

    if (lua_type(L, -1) != LUA_TSTRING) {
        return luaL_error(L, "opts.%s must be string, got %s", name,
                          luaL_typename(L, -1));
    }
    s = lua_tostring(L, -1);
    if (net_protocol_value(s, &hints->ai_protocol)) {
        return 0;
    }
    return luaL_error(L, "invalid opts.%s value: '%s'", name, s);
}

/**
 * @brief opts.flags callback: parse array of AI_* flag name strings and
 * OR-combine into `((struct addrinfo *)ctx)->ai_flags`.
 */
static int check_flags(lua_State *L, const char *name, void *ctx)
{
    struct addrinfo *hints = ctx;
    lua_Integer len        = 0;
    lua_Integer i          = 0;
    const char *s          = NULL;
    int flags              = 0;

    if (lua_type(L, -1) != LUA_TTABLE) {
        return luaL_error(L, "opts.%s must be table, got %s", name,
                          luaL_typename(L, -1));
    }
    len = lauxh_rawlen(L, -1);
    for (i = 1; i <= len; i++) {
        lua_rawgeti(L, -1, i);
        if (lua_type(L, -1) != LUA_TSTRING) {
            return luaL_error(L, "opts.%s[%d] must be string, got %s", name,
                              (int)i, luaL_typename(L, -1));
        }
        int value = 0;
        s         = lua_tostring(L, -1);
        lua_pop(L, 1);
        if (!net_addrinfo_flag_value(s, &value)) {
            return luaL_error(L, "invalid opts.%s[%d] value: '%s'", name,
                              (int)i, s);
        }
        flags |= value;
    }
    hints->ai_flags |= flags;
    return 0;
}

/**
 * @brief opts.passive callback: OR AI_PASSIVE into
 * `((struct addrinfo *)ctx)->ai_flags` when the value is true.
 */
static int check_passive(lua_State *L, const char *name, void *ctx)
{
    struct addrinfo *hints = ctx;

    if (lua_type(L, -1) != LUA_TBOOLEAN) {
        return luaL_error(L, "opts.%s must be boolean, got %s", name,
                          luaL_typename(L, -1));
    }
    if (lua_toboolean(L, -1)) {
        hints->ai_flags |= AI_PASSIVE;
    }
    return 0;
}

/**
 * @brief opts.canonname callback: OR AI_CANONNAME into
 * `((struct addrinfo *)ctx)->ai_flags` when the value is true.
 */
static int check_canonname(lua_State *L, const char *name, void *ctx)
{
    struct addrinfo *hints = ctx;

    if (lua_type(L, -1) != LUA_TBOOLEAN) {
        return luaL_error(L, "opts.%s must be boolean, got %s", name,
                          luaL_typename(L, -1));
    }
    if (lua_toboolean(L, -1)) {
        hints->ai_flags |= AI_CANONNAME;
    }
    return 0;
}

// Shared spec arrays used by multiple entry points.
static const net_socket_option_spec_t OPTS_ADDRINFO_SPECS[] = {
    {"socktype",  check_socktype },
    {"protocol",  check_protocol },
    {"flags",     check_flags    },
    {"passive",   check_passive  },
    {"canonname", check_canonname},
};

// ---------------------------------------------------------------------------
// Metatable methods
// ---------------------------------------------------------------------------

/**
 * @brief Lua method: ai:getnameinfo(...flag_strs)
 *
 * Wrap getnameinfo(3) and return a table `{host, service}` on success or
 * (nil, error) on failure.  The variadic string arguments must be flag
 * names in NI_FLAG_NAMES.
 *
 * @param L Lua state.
 * @return Number of Lua return values (1 on success, 2 on error).
 */
static int getnameinfo_lua(lua_State *L)
{
    net_addrinfo_t *info  = NULL;
    int flags             = 0;
    char host[NI_MAXHOST] = {0};
    char serv[NI_MAXSERV] = {0};
    int rc                = 0;
    int top               = 0;
    int i                 = 0;
    const char *s         = NULL;

    info = lauxh_checkudata(L, 1, NET_ADDRINFO_MT);
    top  = lua_gettop(L);
    for (i = 2; i <= top; i++) {
        if (lua_type(L, i) != LUA_TSTRING) {
            luaL_error(L, "flag #%d must be string, got %s", i - 1,
                       luaL_typename(L, i));
        }
        int value = 0;
        s         = lua_tostring(L, i);
        if (!net_nameinfo_flag_value(s, &value)) {
            luaL_error(L, "invalid flag: '%s'", s);
        }
        flags |= value;
    }
    rc = getnameinfo(info->ai.ai_addr, info->ai.ai_addrlen, host, NI_MAXHOST,
                     serv, NI_MAXSERV, flags);

    // got error
    if (rc != 0) {
        lua_pushnil(L);
        lua_errno_eai_new(L, rc, "getnameinfo");
        return 2;
    }

    lua_createtable(L, 0, 2);
    lauxh_pushstr2tbl(L, "host", host);
    lauxh_pushstr2tbl(L, "service", serv);
    return 1;
}

/**
 * @brief Lua method: ai:addr()
 *
 * Return the sockaddr's presentation address as a Lua string.  Returns nil
 * for address families that are not AF_INET / AF_INET6 / AF_UNIX.
 *
 * @param L Lua state.
 * @return Number of Lua return values (always 1).
 */
static int addr_lua(lua_State *L)
{
    net_addrinfo_t *info       = lauxh_checkudata(L, 1, NET_ADDRINFO_MT);
    char buf[INET6_ADDRSTRLEN] = {0};

    switch (info->ai.ai_family) {
    case AF_INET: {
        struct sockaddr_in *addr = (struct sockaddr_in *)info->ai.ai_addr;
        lua_pushstring(L, inet_ntop(AF_INET, (const void *)&addr->sin_addr, buf,
                                    INET6_ADDRSTRLEN));
    } break;

    case AF_INET6: {
        struct sockaddr_in6 *addr = (struct sockaddr_in6 *)info->ai.ai_addr;
        lua_pushstring(L, inet_ntop(AF_INET6, (const void *)&addr->sin6_addr,
                                    buf, INET6_ADDRSTRLEN));
    } break;

    case AF_UNIX: {
        struct sockaddr_un *addr = (struct sockaddr_un *)info->ai.ai_addr;
        lua_pushstring(L, addr->sun_path);
    } break;

    // unsupported family
    default:
        lua_pushnil(L);
    }

    return 1;
}

/**
 * @brief Lua method: ai:port()
 *
 * Return the port as an integer for AF_INET / AF_INET6.  Returns nil for
 * other address families (Unix domain sockets have no port).
 *
 * @param L Lua state.
 * @return Number of Lua return values (always 1).
 */
static int port_lua(lua_State *L)
{
    net_addrinfo_t *info = lauxh_checkudata(L, 1, NET_ADDRINFO_MT);

    switch (info->ai.ai_family) {
    case AF_INET: {
        struct sockaddr_in *addr = (struct sockaddr_in *)info->ai.ai_addr;
        lua_pushinteger(L, ntohs(addr->sin_port));
    } break;

    case AF_INET6: {
        struct sockaddr_in6 *addr = (struct sockaddr_in6 *)info->ai.ai_addr;
        lua_pushinteger(L, ntohs(addr->sin6_port));
    } break;

    // unsupported family
    default:
        lua_pushnil(L);
    }

    return 1;
}

/**
 * @brief Lua method: ai:canonname()
 *
 * Return the canonical name as a Lua string when getaddrinfo populated it
 * (typically via AI_CANONNAME), otherwise return no value.
 *
 * @param L Lua state.
 * @return Number of Lua return values (0 or 1).
 */
static int canonname_lua(lua_State *L)
{
    net_addrinfo_t *info = lauxh_checkudata(L, 1, NET_ADDRINFO_MT);

    if (info->ai.ai_canonname) {
        lua_pushstring(L, info->ai.ai_canonname);
        return 1;
    }
    return 0;
}

/**
 * @brief Lua method: ai:protocol()
 * @param L Lua state.
 * @return Number of Lua return values (always 1).
 */
static int protocol_lua(lua_State *L)
{
    net_addrinfo_t *info = lauxh_checkudata(L, 1, NET_ADDRINFO_MT);
    const char *name     = net_protocol_name(info->ai.ai_protocol);

    if (!name) {
        return luaL_error(L, "unsupported protocol value: %d",
                          info->ai.ai_protocol);
    }
    lua_pushstring(L, name);
    return 1;
}

/**
 * @brief Lua method: ai:socktype()
 * @param L Lua state.
 * @return Number of Lua return values (always 1).
 */
static int socktype_lua(lua_State *L)
{
    net_addrinfo_t *info = lauxh_checkudata(L, 1, NET_ADDRINFO_MT);
    const char *name     = net_socktype_name(info->ai.ai_socktype);

    if (!name) {
        return luaL_error(L, "unsupported socket type value: %d",
                          info->ai.ai_socktype);
    }
    lua_pushstring(L, name);
    return 1;
}

/**
 * @brief Lua method: ai:family()
 * @param L Lua state.
 * @return Number of Lua return values (always 1).
 */
static int family_lua(lua_State *L)
{
    net_addrinfo_t *info = lauxh_checkudata(L, 1, NET_ADDRINFO_MT);
    const char *name     = net_family_name(info->ai.ai_family);

    if (!name) {
        return luaL_error(L, "unsupported address family value: %d",
                          info->ai.ai_family);
    }
    lua_pushstring(L, name);
    return 1;
}

/**
 * @brief __tostring metamethod: format the userdata as "net.addrinfo: 0x...".
 *
 * @param L Lua state.
 * @return Number of Lua return values (always 1).
 */
static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, NET_ADDRINFO_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

/**
 * @brief __gc metamethod: release the registry references that keep the
 * sockaddr storage and canonical name string alive.
 *
 * @param L Lua state.
 * @return Number of Lua return values (always 0).
 */
static int gc_lua(lua_State *L)
{
    net_addrinfo_t *info   = lauxh_checkudata(L, 1, NET_ADDRINFO_MT);
    info->ai_addr_ref      = lauxh_unref(L, info->ai_addr_ref);
    info->ai_canonname_ref = lauxh_unref(L, info->ai_canonname_ref);
    return 0;
}

// ---------------------------------------------------------------------------
// getaddrinfo family
// ---------------------------------------------------------------------------

/**
 * @brief Parse the host / port pair accepted by getaddrinfo-family functions
 * and return them as C strings, converting a numeric port to its decimal
 * representation.
 *
 * An empty or missing host is reported as `*host = NULL` (wildcard).  Only
 * strings and integers in the range [0, UINT16_MAX] are accepted for the
 * port; anything else yields -1.
 *
 * @param L Lua state.
 * @param[out] host Set to the resolved host string or NULL.
 * @param[out] serv Set to the resolved service string or NULL.
 * @param servbuf Scratch buffer for the decimal port representation.
 * @param bufsz Size of `servbuf` in bytes.
 * @return 0 on success, -1 when the port argument is not a valid value.
 */
static int parse_host_port(lua_State *L, const char **host, const char **serv,
                           char *servbuf, size_t bufsz)
{
    size_t hlen  = 0;
    size_t slen  = 0;
    lua_Number p = 0;

    *host = lauxh_optlstring(L, 1, NULL, &hlen);
    if (hlen == 0) {
        *host = NULL;
    }

    *serv = NULL;
    switch (lua_type(L, 2)) {
    case LUA_TNONE:
    case LUA_TNIL:
        break;

    case LUA_TSTRING:
        *serv = lauxh_optlstring(L, 2, NULL, &slen);
        if (slen == 0) {
            *serv = NULL;
        }
        break;

    case LUA_TNUMBER:
        p = lua_tonumber(L, 2);
        if (isfinite(p) && floor(p) == p && p >= 0 && p <= UINT16_MAX) {
            snprintf(servbuf, bufsz, "%d", (int)p);
            *serv = servbuf;
            break;
        }
        return -1;

    default:
        return -1;
    }
    return 0;
}

/**
 * @brief Protected worker for do_getaddrinfo.  Builds the result table by
 * iterating the addrinfo list carried in upvalue 1 (as a lightuserdata) and
 * calling net_addrinfo_new for each entry.  Runs under lua_pcall so an OOM here
 * long-jumps back to do_getaddrinfo instead of leaking the C list.
 *
 * @param L Lua state.  On entry the stack is empty for this closure; on
 * successful return the freshly built array table sits at the top.
 * @return Number of Lua return values (always 1: the result table).
 */
static int build_addrinfo_list(lua_State *L)
{
    struct addrinfo *list = lua_touserdata(L, lua_upvalueindex(1));
    struct addrinfo *ptr  = NULL;
    int idx               = 1;

    lua_createtable(L, 2, 0);
    for (ptr = list; ptr; ptr = ptr->ai_next) {
        net_addrinfo_new(L, ptr);
        lua_rawseti(L, -2, idx);
        idx++;
    }
    return 1;
}

/**
 * @brief Run getaddrinfo(3) with the supplied hints and either push the
 * resulting array of net.addrinfo userdata or push (nil, error) on failure.
 *
 * @param L Lua state.
 * @param host Host name or numeric address, or NULL for the wildcard.
 * @param serv Service name or numeric port, or NULL.
 * @param hints Hints passed to getaddrinfo.
 * @return Number of Lua return values (1 on success, 2 on error).
 */
static int do_getaddrinfo(lua_State *L, const char *host, const char *serv,
                          struct addrinfo *hints)
{
    struct addrinfo *list = NULL;
    int rc                = 0;
    int status            = 0;

    rc = getaddrinfo(host, serv, hints, &list);
    if (rc != 0) {
        lua_pushnil(L);
        lua_errno_eai_new(L, rc, "getaddrinfo");
        return 2;
    }

    // Build the result table under lua_pcall so that a Lua error inside
    // the loop (for example OOM from lua_newuserdata) does not skip the
    // freeaddrinfo below.
    lua_pushlightuserdata(L, list);
    lua_pushcclosure(L, build_addrinfo_list, 1);
    status = lua_pcall(L, 0, 1, 0);
    freeaddrinfo(list);
    if (status != 0) {
        return lua_error(L);
    }
    return 1;
}

/**
 * @brief Lua function: addrinfo.getaddrinfo(host?, port?, opts?)
 *
 * Resolve the host / port pair via getaddrinfo(3) using the family,
 * socktype, protocol, and flags supplied in `opts`.
 *
 * @param L Lua state.
 * @return Number of Lua return values (1 on success, 2 on error).
 */
static int getaddrinfo_lua(lua_State *L)
{
    static const net_socket_option_spec_t OPTS_GETADDRINFO_SPECS[] = {
        {"family",    check_family   },
        {"socktype",  check_socktype },
        {"protocol",  check_protocol },
        {"flags",     check_flags    },
        {"passive",   check_passive  },
        {"canonname", check_canonname},
    };
    const char *host      = NULL;
    const char *serv      = NULL;
    char servbuf[32]      = {0};
    struct addrinfo hints = {
        .ai_family    = AF_UNSPEC,
        .ai_addrlen   = 0,
        .ai_addr      = NULL,
        .ai_canonname = NULL,
        .ai_next      = NULL,
    };

    if (parse_host_port(L, &host, &serv, servbuf, sizeof(servbuf)) != 0) {
        lua_pushnil(L);
        lua_errno_eai_new(L, EAI_SERVICE, "getaddrinfo");
        return 2;
    }
    NET_SOCKET_CHECK_OPTIONS(L, 3, OPTS_GETADDRINFO_SPECS, &hints);
    return do_getaddrinfo(L, host, serv, &hints);
}

// ---------------------------------------------------------------------------
// AF_INET6 family
// ---------------------------------------------------------------------------

/**
 * @brief Lua function: addrinfo.inet6(addr?, port?, opts?)
 *
 * Build a single AF_INET6 addrinfo from a numeric IPv6 literal.  `opts`
 * accepts `socktype`, `protocol`, and `flags`.
 *
 * @param L Lua state.
 * @return Number of Lua return values (1 on success, 2 on error).
 */
static int inet6_lua(lua_State *L)
{
    size_t len                = 0;
    const char *addr          = lauxh_optlstring(L, 1, NULL, &len);
    uint16_t port             = lauxh_optuint16(L, 2, 0);
    struct sockaddr_in6 saddr = {
        .sin6_family = AF_INET6,
        .sin6_port   = htons(port),
        .sin6_addr   = in6addr_any,
    };
    struct addrinfo ai = {
        .ai_family    = AF_INET6,
        .ai_socktype  = 0,
        .ai_protocol  = 0,
        .ai_flags     = 0,
        .ai_addrlen   = sizeof(saddr),
        .ai_addr      = (struct sockaddr *)&saddr,
        .ai_canonname = NULL,
        .ai_next      = NULL,
    };

    NET_SOCKET_CHECK_OPTIONS(L, 3, OPTS_ADDRINFO_SPECS, &ai);

#ifdef HAVE_STRUCT_SOCKADDR_SA_LEN
    saddr.sin6_len = sizeof(saddr);
#endif

    if (len) {
        switch (inet_pton(AF_INET6, addr, (void *)&saddr.sin6_addr)) {
        case -1:
            lua_pushnil(L);
            lua_errno_new(L, errno, "inet_pton");
            return 2;
        case 0:
            // addr cannot be parsed as ipv6 address
            lua_pushnil(L);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "inet_pton");
            return 2;
        }
    }

    // create addrinfo
    net_addrinfo_new(L, &ai);
    return 1;
}

// ---------------------------------------------------------------------------
// AF_INET family
// ---------------------------------------------------------------------------

/**
 * @brief Lua function: addrinfo.inet(addr?, port?, opts?)
 *
 * Build a single AF_INET addrinfo from a numeric IPv4 literal.  `opts`
 * accepts `socktype`, `protocol`, and `flags`.
 *
 * @param L Lua state.
 * @return Number of Lua return values (1 on success, 2 on error).
 */
static int inet_lua(lua_State *L)
{
    size_t len               = 0;
    const char *addr         = lauxh_optlstring(L, 1, NULL, &len);
    uint16_t port            = lauxh_optuint16(L, 2, 0);
    struct sockaddr_in saddr = {
        .sin_family = AF_INET,
        .sin_port   = htons(port),
        .sin_addr   = {.s_addr = INADDR_ANY},
    };
    struct addrinfo ai = {
        .ai_family    = AF_INET,
        .ai_socktype  = 0,
        .ai_protocol  = 0,
        .ai_flags     = 0,
        .ai_addrlen   = sizeof(saddr),
        .ai_addr      = (struct sockaddr *)&saddr,
        .ai_canonname = NULL,
        .ai_next      = NULL,
    };

    NET_SOCKET_CHECK_OPTIONS(L, 3, OPTS_ADDRINFO_SPECS, &ai);

#ifdef HAVE_STRUCT_SOCKADDR_SA_LEN
    saddr.sin_len = sizeof(saddr);
#endif

    if (len) {
        switch (inet_pton(AF_INET, addr, (void *)&saddr.sin_addr)) {
        case -1:
            lua_pushnil(L);
            lua_errno_new(L, errno, "inet_pton");
            return 2;
        case 0:
            // addr cannot be parsed as ipv4 address
            lua_pushnil(L);
            errno = EAFNOSUPPORT;
            lua_errno_new(L, errno, "inet_pton");
            return 2;
        }
    }

    // create addrinfo
    net_addrinfo_new(L, &ai);
    return 1;
}

// ---------------------------------------------------------------------------
// AF_UNIX family
// ---------------------------------------------------------------------------

/**
 * @brief Lua function: addrinfo.unix(pathname, opts?)
 *
 * Build an AF_UNIX addrinfo from a filesystem pathname.  `opts` accepts
 * `socktype`, `protocol`, and `flags`.
 *
 * @param L Lua state.
 * @return Number of Lua return values (1 on success, 2 on error).
 */
static int unix_lua(lua_State *L)
{
    size_t len               = 0;
    const char *pathname     = lauxh_checklstring(L, 1, &len);
    struct sockaddr_un saddr = {.sun_family = AF_UNIX, .sun_path = {0}};
    struct addrinfo ai       = {.ai_family    = AF_UNIX,
                                .ai_socktype  = 0,
                                .ai_protocol  = 0,
                                .ai_flags     = 0,
                                .ai_addrlen   = sizeof(saddr),
                                .ai_addr      = (struct sockaddr *)&saddr,
                                .ai_canonname = NULL,
                                .ai_next      = NULL};

    NET_SOCKET_CHECK_OPTIONS(L, 2, OPTS_ADDRINFO_SPECS, &ai);

    // length too large
    if (len >= UNIXPATH_MAX) {
        lua_pushnil(L);
        errno = ENAMETOOLONG;
        lua_errno_new(L, errno, "unix");
        return 2;
    }
    memcpy((void *)&saddr.sun_path, (void *)pathname, len);
    saddr.sun_path[len] = 0;

    // create addrinfo
    net_addrinfo_new(L, &ai);
    return 1;
}

/**
 * @brief luaopen entry point: install the net.addrinfo metatable and return
 * the module table exposing every constructor.
 *
 * @param L Lua state.
 * @return Number of Lua return values (always 1: the module table).
 */
LUALIB_API int luaopen_net_addrinfo(lua_State *L)
{
    struct luaL_Reg mmethod[] = {
        {"__gc",       gc_lua      },
        {"__tostring", tostring_lua},
        {NULL,         NULL        }
    };
    struct luaL_Reg method[] = {
        {"family",      family_lua     },
        {"socktype",    socktype_lua   },
        {"protocol",    protocol_lua   },
        {"canonname",   canonname_lua  },
        {"port",        port_lua       },
        {"addr",        addr_lua       },
        {"getnameinfo", getnameinfo_lua},
        {NULL,          NULL           }
    };
    struct luaL_Reg *ptr = NULL;

    lua_errno_loadlib(L);

    // create metatable
    if (luaL_newmetatable(L, NET_ADDRINFO_MT)) {
        // metamethods
        for (ptr = mmethod; ptr->name; ptr++) {
            lauxh_pushfn2tbl(L, ptr->name, ptr->func);
        }
        // methods
        lua_pushstring(L, "__index");
        lua_newtable(L);
        for (ptr = method; ptr->name; ptr++) {
            lauxh_pushfn2tbl(L, ptr->name, ptr->func);
        }
        lua_rawset(L, -3);
    }
    lua_pop(L, 1);

    // create module table
    lua_newtable(L);
    // low-level constructors
    lauxh_pushfn2tbl(L, "unix", unix_lua);
    lauxh_pushfn2tbl(L, "inet", inet_lua);
    lauxh_pushfn2tbl(L, "inet6", inet6_lua);
    // getaddrinfo family
    lauxh_pushfn2tbl(L, "getaddrinfo", getaddrinfo_lua);

    return 1;
}
