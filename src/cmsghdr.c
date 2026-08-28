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
// system
#include <fcntl.h>
#include <limits.h>

// Push an lstring holding a single, self-contained cmsg block (header +
// payload + CMSG_ALIGN trailing padding) onto the top of L.  On Lua 5.2+ the
// bytes are assembled directly inside a luaL_Buffer reservation, so only a
// single Lua string allocation is performed.  On Lua 5.1 (no
// `luaL_buffinitsize`) we fall back to a transient lua_newuserdata scratch
// that is discarded once its bytes have been copied into the immutable Lua
// string on top of the stack.
static void push_cmsg_block(lua_State *L, int level, int type,
                            const void *payload, size_t datalen)
{
    size_t space        = CMSG_SPACE(datalen);
    unsigned char *dst  = NULL;
    struct cmsghdr *cmh = NULL;

#if LUA_VERSION_NUM >= 502
    luaL_Buffer B;
    dst = (unsigned char *)luaL_buffinitsize(L, &B, space);
#else
    dst = (unsigned char *)lua_newuserdata(L, space);
#endif

    memset(dst, 0, space);
    cmh             = (struct cmsghdr *)dst;
    cmh->cmsg_len   = CMSG_LEN(datalen);
    cmh->cmsg_level = level;
    cmh->cmsg_type  = type;
    if (datalen > 0) {
        memcpy(CMSG_DATA(cmh), payload, datalen);
    }

#if LUA_VERSION_NUM >= 502
    luaL_pushresultsize(&B, space);
#else
    lua_pushlstring(L, (const char *)dst, space);
    // Discard the scratch userdata now that its bytes have been copied into
    // the immutable Lua string on top of the stack.
    lua_replace(L, -2);
#endif
}

// Maximum number of file descriptors that can be sent in a single SCM_RIGHTS
// cmsg.  Linux caps this at SCM_MAX_FD (253); the value used here is
// deliberately generous so the fd array fits on the stack for typical use.
#define NET_CMSG_MAX_FD 256

// Read the SCM_RIGHTS payload at Lua stack index `dataidx` (an integer fd or
// an integer[] table of fds) and push a serialized cmsg block onto L.  Every
// fd must be an integral value in 0..INT_MAX; narrowing an out-of-range
// lua_Integer to int would wrap onto an unrelated descriptor number inside
// the SCM_RIGHTS payload.  Raises via luaL_error on malformed data.
static void push_scm_rights_entry(lua_State *L, int i, int level, int type,
                                  int dataidx)
{
    int fds[NET_CMSG_MAX_FD];
    size_t nfd = 0;

    switch (lua_type(L, dataidx)) {
    case LUA_TNUMBER: {
        lua_Integer fd = 0;
        if (!lauxh_isinteger(L, dataidx)) {
            luaL_error(L, "cmsg[%d].data must be integer fd", i);
        }
        fd = lua_tointeger(L, dataidx);
        if (fd < 0 || fd > INT_MAX) {
            luaL_error(L, "cmsg[%d].data: fd must be in the range 0..%d", i,
                       INT_MAX);
        }
        fds[0] = (int)fd;
        nfd    = 1;
        break;
    }

    case LUA_TTABLE: {
        lua_Integer tlen = (lua_Integer)lauxh_rawlen(L, dataidx);
        if (tlen < 0 || (size_t)tlen > NET_CMSG_MAX_FD) {
            luaL_error(L, "cmsg[%d].data: too many fds (max %d)", i,
                       (int)NET_CMSG_MAX_FD);
        }
        for (lua_Integer j = 1; j <= tlen; j++) {
            lua_Integer fd = 0;
            lua_rawgeti(L, dataidx, (int)j);
            if (!lauxh_isinteger(L, -1)) {
                luaL_error(L, "cmsg[%d].data[%d] must be integer fd", i,
                           (int)j);
            }
            fd = lua_tointeger(L, -1);
            if (fd < 0 || fd > INT_MAX) {
                luaL_error(L,
                           "cmsg[%d].data[%d]: fd must be in the range 0..%d",
                           i, (int)j, INT_MAX);
            }
            fds[j - 1] = (int)fd;
            lua_pop(L, 1);
        }
        nfd = (size_t)tlen;
    } break;

    default:
        luaL_error(L,
                   "cmsg[%d].data: SCM_RIGHTS requires integer fd or "
                   "table of integer fds",
                   i);
    }

    push_cmsg_block(L, level, type, fds, sizeof(int) * nfd);
}

// Read a raw (non-SCM_RIGHTS) cmsg payload string at Lua stack index
// `dataidx` and push a serialized cmsg block onto L.  Raises via luaL_error
// when the data field is not a string.
static void push_raw_cmsg_entry(lua_State *L, int i, int level, int type,
                                int dataidx)
{
    size_t datalen   = 0;
    const char *dbuf = NULL;

    if (lua_type(L, dataidx) != LUA_TSTRING) {
        luaL_error(L, "cmsg[%d].data: string expected for level=%d type=%d", i,
                   level, type);
    }
    dbuf = lua_tolstring(L, dataidx, &datalen);
    push_cmsg_block(L, level, type, dbuf, datalen);
}

// Serialize one cmsg entry into a fresh Lua string and leave that string on
// top of the Lua stack, replacing the input cmsg descriptor table at
// `cmsg_idx`.  Level, type and data fields are read from the table and any
// transient stack slots are cleaned up before returning.  On error, this
// function raises via luaL_error and does not return.
static void push_cmsg_entry(lua_State *L, int cmsg_idx, int i)
{
    int level             = 0;
    int type              = 0;
    int dataidx           = 0;
    size_t level_len      = 0;
    size_t type_len       = 0;
    const char *level_str = NULL;
    const char *type_str  = NULL;

    if (!lua_istable(L, cmsg_idx)) {
        luaL_error(L, "cmsg[%d] must be a table", i);
    }

    // level
    lua_getfield(L, cmsg_idx, "level");
    if (lua_type(L, -1) != LUA_TSTRING) {
        luaL_error(L, "cmsg[%d].level must be a string", i);
    }
    level_str = lua_tolstring(L, -1, &level_len);
    if (!net_cmsg_level_value(level_str, level_len, &level)) {
        luaL_error(L, "cmsg[%d].level: unknown level '%s'", i, level_str);
    }
    lua_pop(L, 1);

    // type
    lua_getfield(L, cmsg_idx, "type");
    if (lua_type(L, -1) != LUA_TSTRING) {
        luaL_error(L, "cmsg[%d].type must be a string", i);
    }
    type_str = lua_tolstring(L, -1, &type_len);
    if (!net_cmsg_type_value(level, type_str, type_len, &type)) {
        luaL_error(L, "cmsg[%d].type: unknown type '%s' for level '%s'", i,
                   type_str, level_str);
    }
    lua_pop(L, 1);

    // data
    lua_getfield(L, cmsg_idx, "data");
    dataidx = lua_gettop(L);

    if (level == SOL_SOCKET && type == SCM_RIGHTS) {
        push_scm_rights_entry(L, i, level, type, dataidx);
    } else {
        push_raw_cmsg_entry(L, i, level, type, dataidx);
    }

    // Stack now: [..., cmsg_table (cmsg_idx), data, cmsg_lstring]
    // Replace the cmsg descriptor table with the assembled lstring so that
    // after cleanup only the lstring remains at cmsg_idx.
    lua_replace(L, cmsg_idx);
    // Pop the data field slot.
    // Stack now: [..., cmsg_lstring (cmsg_idx)]
    lua_pop(L, 1);
}

int net_cmsg_build_buffer(lua_State *L, int idx)
{
    lua_Integer n = (lua_Integer)lauxh_rawlen(L, idx);

    if (n <= 0) {
        return 0;
    }
    // LCOV_EXCL_START - defensive cap for pathologically large cmsg tables.
    // In practice sendmsg(2) cmsg counts are single digits and luaL_checkstack
    // below would fail long before INT_MAX / 2 is reached; the check exists
    // only to make the subsequent (int) casts well-defined.
    if (n > INT_MAX / 2) {
        luaL_error(L, "cmsg table too large: %d entries", (int)INT_MAX);
    }
    // LCOV_EXCL_STOP

    // Reserve stack room for n accumulated lstrings plus per-iteration
    // temporaries (cmsg table, data value, scratch userdata, lstring).
    luaL_checkstack(L, (int)n + 4, "cmsg buffer build");

    for (lua_Integer i = 1; i <= n; i++) {
        lua_rawgeti(L, idx, (int)i);
        push_cmsg_entry(L, lua_gettop(L), (int)i);
    }

    if (n > 1) {
        lua_concat(L, (int)n);
    }
    return 1;
}

/**
 * @brief Push the data field of a non-SCM_RIGHTS cmsghdr onto the Lua stack.
 * If the cmsg level/type is known and has a special representation (e.g.,
 * SCM_TIMESTAMP), it will be pushed as a Lua table.  Otherwise, it will be
 * pushed as a Lua string containing the raw data.  SCM_RIGHTS is handled by
 * push_rights_data(), which also records the fds for failure cleanup.
 *
 * @param L The Lua state.
 * @param cmh The cmsghdr whose data field is to be pushed onto the Lua stack.
 */
static void push_data(lua_State *L, const struct cmsghdr *cmh)
{
    size_t hdrlen  = (size_t)((const char *)CMSG_DATA(cmh) - (const char *)cmh);
    size_t datalen = 0;

    // Guard against malformed cmsghdrs whose cmsg_len is smaller than the
    // header itself; treat them as carrying no payload so the branches below
    // do not read past the caller buffer.
    if (cmh->cmsg_len < hdrlen) {
        lua_pushliteral(L, "");
        return;
    }
    datalen = cmh->cmsg_len - hdrlen;

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
    // SCM_RIGHTS never reaches here; the caller dispatches it to
    // push_rights_data() instead.
    switch (cmh->cmsg_type) {
#ifdef SCM_TIMESTAMP
    case SCM_TIMESTAMP: {
        // SCM_TIMESTAMP delivers a struct timeval.  Expose it as a table
        // { sec = <integer>, usec = <integer> } so that callers can access
        // the receive timestamp without decoding the raw bytes themselves.
        struct timeval tv;
        if (datalen < sizeof(tv)) {
            // Truncated ancillary data may leave SCM_TIMESTAMP shorter than
            // struct timeval; return nil rather than reading past CMSG_DATA.
            lua_pushnil(L);
            return;
        }
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
    // type other than SCM_TIMESTAMP.  Such types (e.g.
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

// Maximum number of file descriptors a single net_cmsg_push_table() call can
// keep in its failure-cleanup ledger.  The kernel limits one cmsg to
// SCM_MAX_FD (253 on Linux); the total cap is a fail-safe against a runaway
// fd storm, not an expected operating range.
#define NET_CMSG_MAX_FD_TOTAL 1024

// Working state shared between net_cmsg_push_table() and the protected
// push_table_impl(): every SCM_RIGHTS fd is recorded in fds so that a Lua
// allocation failure cannot longjmp past a descriptor nobody else owns.
// err stays 0 while the batch is usable; once a fd cannot be recorded it
// holds the errno explaining why (the actual fcntl errno, or EMFILE when
// the ledger is full).
typedef struct {
    struct msghdr *msg;
    int fds[NET_CMSG_MAX_FD_TOTAL];
    size_t nfd;
    int err;
} net_cmsg_ctx_t;

// Record a received SCM_RIGHTS fd in the ledger.  On platforms without
// MSG_CMSG_CLOEXEC the FD_CLOEXEC fallback runs here.  A fd that cannot be
// recorded, CLOEXEC failure or a full ledger, is closed on the spot and its
// cause is stored in ctx->err; push_table_impl() discards the batch with
// that errno once the walk over the control buffer completes.
static void check_fd(net_cmsg_ctx_t *ctx, int fd)
{
    // the batch is already doomed: nobody will own this fd, so close it
    // right away instead of recording it
    if (ctx->err) {
        close(fd);
        return;
    }
#ifndef MSG_CMSG_CLOEXEC
    // Portable fallback: apply FD_CLOEXEC out-of-band on platforms where
    // recvmsg cannot deliver the fd already CLOEXEC.  A fd without the flag
    // leaks into every future exec.
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) == -1) {
        close(fd);
        ctx->err = errno;
        return;
    }
#endif
    if (ctx->nfd >= NET_CMSG_MAX_FD_TOTAL) {
        close(fd);
        ctx->err = EMFILE;
        return;
    }
    ctx->fds[ctx->nfd++] = fd;
}

// Push the data field of an SCM_RIGHTS cmsghdr: a Lua integer for a single
// fd, or a table of integers otherwise.  Every fd is routed through
// check_fd() first so it is either in the cleanup ledger or already closed.
static void push_rights_data(lua_State *L, net_cmsg_ctx_t *ctx,
                             const struct cmsghdr *cmh)
{
    size_t hdrlen  = (size_t)((const char *)CMSG_DATA(cmh) - (const char *)cmh);
    size_t datalen = 0;
    size_t nfd     = 0;

    // Guard against malformed cmsghdrs whose cmsg_len is smaller than the
    // header itself; there is no readable payload, so carry no data.
    if (cmh->cmsg_len < hdrlen) {
        lua_pushnil(L);
        return;
    }
    // Round down to whole fds; the kernel may deliver a partial payload when
    // the caller's control buffer was too small (MSG_CTRUNC), in which case
    // datalen is not necessarily a multiple of sizeof(int).
    datalen = (size_t)cmh->cmsg_len - hdrlen;
    nfd     = datalen / sizeof(int);

    if (nfd == 1) {
        int fd;
        memcpy(&fd, CMSG_DATA(cmh), sizeof(int));
        check_fd(ctx, fd);
        lua_pushinteger(L, fd);
    } else {
        lua_createtable(L, (int)nfd, 0);
        for (size_t j = 0; j < nfd; j++) {
            int fd;
            memcpy(&fd, (const unsigned char *)CMSG_DATA(cmh) + j * sizeof(int),
                   sizeof(int));
            check_fd(ctx, fd);
            lua_pushinteger(L, fd);
            lua_rawseti(L, -2, (int)(j + 1));
        }
    }
}

// lua_pcall() body of net_cmsg_push_table(): builds the cmsg table from the
// context passed as a light userdata while recording every SCM_RIGHTS fd in
// the ledger.  Runs protected so that an allocation failure cannot longjmp
// past the recorded fds.
static int push_cmsg_table(lua_State *L)
{
    net_cmsg_ctx_t *ctx = (net_cmsg_ctx_t *)lua_touserdata(L, 1);
    // the msghdr belongs to the caller's C frame, which stays alive for the
    // duration of the lua_pcall() that invoked this function
    struct msghdr *m    = ctx->msg;
    struct cmsghdr *cmh = (m->msg_controllen == 0) ? NULL : CMSG_FIRSTHDR(m);

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

        // Push the data field of the cmsg table on the Lua stack (string,
        // table of fds, or timestamp table).  SCM_RIGHTS must always go
        // through push_rights_data() so its fds are recorded (or closed)
        // even once the batch is rejected; for the remaining cmsgs the data
        // value is pointless once the batch is doomed, so stop building it.
        if (cmh->cmsg_level == SOL_SOCKET && cmh->cmsg_type == SCM_RIGHTS) {
            push_rights_data(L, ctx, cmh);
        } else if (ctx->err) {
            lua_pushnil(L);
        } else {
            push_data(L, cmh);
        }
        lua_setfield(L, -2, "data");

        count++;
        lua_rawseti(L, -2, count);
    }

    if (ctx->err) {
        // Some fd could not be recorded: the batch is unusable, so close
        // every fd the ledger holds (the unrecordable ones are already
        // closed) and fail the call with the recorded cause.
        for (size_t k = 0; k < ctx->nfd; k++) {
            close(ctx->fds[k]);
        }
        // keep the ledger empty so net_cmsg_push_table() will not close the
        // same fds again while propagating this error
        ctx->nfd = 0;
        lua_errno_new(L, ctx->err, "recvmsg");
        lua_error(L);
    }
    return 1;
}

int net_cmsg_push_table(lua_State *L, const struct msghdr *msg)
{
    // CMSG_FIRSTHDR/CMSG_NXTHDR take a non-const struct msghdr* pointer on
    // some systems, so cast away const locally.
    struct msghdr *m    = (struct msghdr *)msg;
    struct cmsghdr *cmh = (m->msg_controllen == 0) ? NULL : CMSG_FIRSTHDR(m);
    net_cmsg_ctx_t ctx  = {
        .msg = m,
        .nfd = 0,
        .err = 0,
    };

    if (cmh == NULL) {
        return 0;
    }

    // The construction below allocates on the Lua stack while installing
    // every SCM_RIGHTS fd as a plain integer in the table; an allocation
    // failure would longjmp past descriptors nobody else owns.  Run it
    // under lua_pcall() so the failure path can close the fds recorded in
    // ctx before propagating the error.
    lua_pushcfunction(L, push_cmsg_table);
    lua_pushlightuserdata(L, &ctx);
    if (lua_pcall(L, 1, 1, 0) != 0) {
        for (size_t k = 0; k < ctx.nfd; k++) {
            close(ctx.fds[k]);
        }
        // re-raise with the error object lua_pcall() left on the stack
        lua_error(L);
    }
    return 1;
}
