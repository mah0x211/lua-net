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

// project
#include "constants.h"
#include "net_socket.h"

// Maximum number of file descriptors that can be sent in a single SCM_RIGHTS
// cmsg.  Linux caps this at SCM_MAX_FD (253); the value used here is
// deliberately generous so the fd array fits on the stack for typical use.
#define NET_CMSG_MAX_FD 256

// Serialize a single cmsg entry (already parsed level/type) whose payload is
// held at Lua stack index dataidx into the destination buffer.  On error, this
// function raises via luaL_error and does not return.
static size_t write_cmsg_entry(lua_State *L, int cmsg_index_for_error,
                               int level, int type, int dataidx,
                               unsigned char *buf, size_t used, size_t bufsize)
{
    struct cmsghdr *cmh = (struct cmsghdr *)(buf + used);
    size_t space        = 0;

    if (level == SOL_SOCKET && type == SCM_RIGHTS) {
        int fds[NET_CMSG_MAX_FD];
        size_t nfd = 0;
        int dtype  = lua_type(L, dataidx);
        if (dtype == LUA_TNUMBER) {
            fds[0] = (int)lua_tointeger(L, dataidx);
            nfd    = 1;
        } else if (dtype == LUA_TTABLE) {
            lua_Integer tlen = (lua_Integer)lauxh_rawlen(L, dataidx);
            if (tlen < 0 || (size_t)tlen > NET_CMSG_MAX_FD) {
                luaL_error(L, "cmsg[%d].data: too many fds (max %d)",
                           cmsg_index_for_error, (int)NET_CMSG_MAX_FD);
            }
            for (lua_Integer j = 1; j <= tlen; j++) {
                lua_rawgeti(L, dataidx, (int)j);
                if (lua_type(L, -1) != LUA_TNUMBER) {
                    luaL_error(L, "cmsg[%d].data[%d] must be integer fd",
                               cmsg_index_for_error, (int)j);
                }
                fds[j - 1] = (int)lua_tointeger(L, -1);
                lua_pop(L, 1);
            }
            nfd = (size_t)tlen;
        } else {
            luaL_error(L,
                       "cmsg[%d].data: SCM_RIGHTS requires integer fd or "
                       "table of integer fds",
                       cmsg_index_for_error);
        }
        // Reserve space for the cmsg header and its file descriptor payload.
        // Note that SCM_MAX_FD (253 on Linux) fds fit within a few hundred
        // bytes even after CMSG_SPACE alignment, well below sendmsg_lua's
        // 4 KiB control buffer, so we do not need an explicit overflow
        // guard here (the fd count check above is the effective bound).
        space           = CMSG_SPACE(sizeof(int) * nfd);
        cmh->cmsg_len   = CMSG_LEN(sizeof(int) * nfd);
        cmh->cmsg_level = level;
        cmh->cmsg_type  = type;
        memcpy(CMSG_DATA(cmh), fds, sizeof(int) * nfd);
    } else {
        size_t datalen   = 0;
        const char *dbuf = NULL;
        if (lua_type(L, dataidx) != LUA_TSTRING) {
            luaL_error(L, "cmsg[%d].data: string expected for level=%d type=%d",
                       cmsg_index_for_error, level, type);
        }
        dbuf  = lua_tolstring(L, dataidx, &datalen);
        space = CMSG_SPACE(datalen);
        if (used + space > bufsize) {
            luaL_error(L, "cmsg buffer overflow at cmsg[%d]",
                       cmsg_index_for_error);
        }
        cmh->cmsg_len   = CMSG_LEN(datalen);
        cmh->cmsg_level = level;
        cmh->cmsg_type  = type;
        memcpy(CMSG_DATA(cmh), dbuf, datalen);
    }
    return space;
}

size_t net_cmsg_build_buffer(lua_State *L, int idx, unsigned char *buf,
                             size_t bufsize)
{
    lua_Integer n = (lua_Integer)lauxh_rawlen(L, idx);
    size_t used   = 0;

    if (n <= 0) {
        return 0;
    }
    memset(buf, 0, bufsize);

    for (lua_Integer i = 1; i <= n; i++) {
        lua_rawgeti(L, idx, (int)i);
        int cmsg_idx = lua_gettop(L);
        if (!lua_istable(L, cmsg_idx)) {
            luaL_error(L, "cmsg[%d] must be a table", (int)i);
        }

        // level
        lua_getfield(L, cmsg_idx, "level");
        if (lua_type(L, -1) != LUA_TSTRING) {
            luaL_error(L, "cmsg[%d].level must be a string", (int)i);
        }
        const char *level_str = lua_tostring(L, -1);
        int level             = 0;
        if (!net_cmsg_level_value(level_str, &level)) {
            luaL_error(L, "cmsg[%d].level: unknown level '%s'", (int)i,
                       level_str);
        }
        lua_pop(L, 1);

        // type
        lua_getfield(L, cmsg_idx, "type");
        if (lua_type(L, -1) != LUA_TSTRING) {
            luaL_error(L, "cmsg[%d].type must be a string", (int)i);
        }
        const char *type_str = lua_tostring(L, -1);
        int type             = 0;
        if (!net_cmsg_type_value(level, type_str, &type)) {
            luaL_error(L, "cmsg[%d].type: unknown type '%s' for level '%s'",
                       (int)i, type_str, level_str);
        }
        lua_pop(L, 1);

        // data
        lua_getfield(L, cmsg_idx, "data");
        int dataidx = lua_gettop(L);
        size_t adv  = write_cmsg_entry(L, (int)i, level, type, dataidx, buf,
                                       used, bufsize);
        used += adv;
        lua_pop(L, 1); // data
        lua_pop(L, 1); // cmsg_idx table
    }
    return used;
}

/**
 * @brief Push the data field of a cmsghdr onto the Lua stack.  If the cmsg
 * level/type is known and has a special representation (e.g., SCM_RIGHTS), it
 * will be pushed as a Lua integer or table of integers.  Otherwise, it will be
 * pushed as a Lua string containing the raw data.
 *
 * @param L The Lua state.
 * @param cmh The cmsghdr whose data field is to be pushed onto the Lua stack.
 */
static void push_data(lua_State *L, const struct cmsghdr *cmh)
{
    size_t datalen = cmh->cmsg_len -
                     (size_t)((const char *)CMSG_DATA(cmh) - (const char *)cmh);

    switch (cmh->cmsg_level) {
    case SOL_SOCKET:
        goto PUSH_SOL_SOCKET;

        // TODO: Handle other levels (IPPROTO_IP, IPPROTO_IPV6, etc.) if needed.

    default:
PUSH_RAWDATA:
        lua_pushlstring(L, (const char *)CMSG_DATA(cmh), datalen);
        return;
    }

PUSH_SOL_SOCKET:
    // Handle known SOL_SOCKET types with special representations.
    switch (cmh->cmsg_type) {
    case SCM_RIGHTS: {
        size_t nfd = datalen / sizeof(int);
        if (nfd == 1) {
            int fd;
            memcpy(&fd, CMSG_DATA(cmh), sizeof(int));
            lua_pushinteger(L, fd);
        } else {
            lua_createtable(L, (int)nfd, 0);
            for (size_t j = 0; j < nfd; j++) {
                int fd;
                memcpy(&fd,
                       (const unsigned char *)CMSG_DATA(cmh) + j * sizeof(int),
                       sizeof(int));
                lua_pushinteger(L, fd);
                lua_rawseti(L, -2, (int)(j + 1));
            }
        }
        return;
    }

#ifdef SCM_TIMESTAMP
    case SCM_TIMESTAMP: {
        // SCM_TIMESTAMP delivers a struct timeval.  Expose it as a table
        // { sec = <integer>, usec = <integer> } so that callers can access
        // the receive timestamp without decoding the raw bytes themselves.
        struct timeval tv;
        memcpy(&tv, CMSG_DATA(cmh), sizeof(tv));
        lua_createtable(L, 0, 2);
        lua_pushinteger(L, (lua_Integer)tv.tv_sec);
        lua_setfield(L, -2, "sec");
        lua_pushinteger(L, (lua_Integer)tv.tv_usec);
        lua_setfield(L, -2, "usec");
        return;
    }
#endif

        // TODO: Handle other SOL_SOCKET types (e.g., SCM_CREDENTIALS) if
        // needed.
    }

    // TODO: Handle other levels (IPPROTO_IP, IPPROTO_IPV6, etc.) if needed.

    // LCOV_EXCL_START - reached only when the cmsg is SOL_SOCKET but has a
    // type other than SCM_RIGHTS or SCM_TIMESTAMP.  Such types (e.g.
    // SCM_SECURITY / SCM_PIDFD on Linux) are not currently produced by any
    // of our tests on the target platform.
    goto PUSH_RAWDATA;
    // LCOV_EXCL_STOP
}

/**
 * @brief Push the cmsg type field onto the Lua stack as a string if known, or
 * as an integer if unknown.  This function performs a reverse lookup of the
 * cmsg type integer to its corresponding lowercase short name for a given
 * level. If the (level, type) pair is not found in the mapping tables, it
 * pushes the integer value instead.
 *
 * @param L The Lua state.
 * @param level The cmsg level (e.g., SOL_SOCKET, IPPROTO_IP).
 * @param type The cmsg type integer to look up.
 */
static void push_type2name(lua_State *L, int level, int type)
{
    const char *s = net_cmsg_type_name(level, type);

    if (s) {
        lua_pushstring(L, s);
    } else {
        lua_pushinteger(L, type);
    }
}

/**
 * @brief Push the cmsg level field onto the Lua stack as a string if known, or
 * as an integer if unknown.  This function performs a reverse lookup of the
 * cmsg level integer to its corresponding lowercase short name. If the level
 * is not found in the mapping table, it pushes the integer value instead.
 *
 * @param L The Lua state.
 * @param level The cmsg level integer to look up.
 */
static void push_level2name(lua_State *L, int level)
{
    // Reverse lookup: cmsg level integer -> lowercase short name, or NULL.
    const char *s = net_cmsg_level_name(level);
    // Push the level field of the cmsg table on the Lua stack (string if
    // known, integer otherwise).
    if (s) {
        lua_pushstring(L, s);
    } else {
        // LCOV_EXCL_START - defensive fallback: every level we currently
        // enable (SOL_SOCKET, IPPROTO_IP, IPPROTO_IPV6, IPPROTO_TCP,
        // IPPROTO_UDP) is present in the shared constants map, so callers only
        // reach this branch when receiving a cmsg carrying a level that we
        // have not yet mapped.
        lua_pushinteger(L, level);
        // LCOV_EXCL_STOP
    }
}

int net_cmsg_push_table(lua_State *L, const struct msghdr *msg)
{
    // CMSG_FIRSTHDR/CMSG_NXTHDR take a non-const struct msghdr* pointer on
    // some systems, so cast away const locally.
    struct msghdr *m    = (struct msghdr *)msg;
    struct cmsghdr *cmh = (m->msg_controllen == 0) ? NULL : CMSG_FIRSTHDR(m);

    if (cmh == NULL) {
        return 0;
    }

    lua_createtable(L, 0, 1);
    for (int count = 0; cmh != NULL; cmh = CMSG_NXTHDR(m, cmh)) {
        // cmsg table with 3 fields: level, type, data
        lua_createtable(L, 0, 3);

        // Push the level field of the cmsg table on the Lua stack (string
        // if known, integer otherwise).
        push_level2name(L, cmh->cmsg_level);
        lua_setfield(L, -2, "level");
        // Push the type field of the cmsg table on the Lua stack (string if
        // known, integer otherwise).
        push_type2name(L, cmh->cmsg_level, cmh->cmsg_type);
        lua_setfield(L, -2, "type");

        // Push the data field of the cmsg table on the Lua stack (string or
        // table of fds).
        push_data(L, cmh);
        lua_setfield(L, -2, "data");

        count++;
        lua_rawseti(L, -2, count);
    }
    return 1;
}
