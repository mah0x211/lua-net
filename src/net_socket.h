/**
 *  Copyright (C) 2014 Masatoshi Teruya
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
 *  net_socket.h
 *  lua-net
 *
 *  Created by Masatoshi Fukunaga on 14/03/29.
 */

#ifndef net_socket_h
#define net_socket_h

#define _GNU_SOURCE

// Expose RFC 3542 IPv6 advanced sockets API (IPV6_PKTINFO, IPV6_HOPLIMIT,
// IPV6_TCLASS, IPV6_HOPOPTS, IPV6_DSTOPTS, IPV6_RTHDR, ...) on macOS.  On
// Linux these constants are available by default via _GNU_SOURCE + the
// standard headers.
#if defined(__APPLE__) && !defined(__APPLE_USE_RFC_3542)
# define __APPLE_USE_RFC_3542
#endif

// project
#include "config.h"
// depend
#include "lauxhlib.h"
#include "lua_errno.h"
// lua
#include <lauxlib.h>
// system
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
// use net.addrinfo module for addrinfo userdata (metatable + net_addrinfo_t)
#include "addrinfo.h"

#define SOCKET_MT "net.socket"

#if defined(__linux__)
# include <linux/if.h>
# include <linux/if_packet.h>
#else
# include <net/if_dl.h>
#endif

typedef struct {
    int fd;
    int family;
    int socktype;
    int protocol;
    // Registry reference to (gc_thread_ref) and pointer to (gc_thread) a
    // Lua thread whose stack holds a LIFO of gc-callback closures added via
    // addgcfn().  The thread is allocated at socket construction time.
    // After the socket is closed and the thread is released, gc_thread is
    // NULL and gc_thread_ref is LUA_NOREF.
    int gc_thread_ref;
    lua_State *gc_thread;
} net_socket_t;

LUALIB_API int luaopen_net_socket(lua_State *L);

// cmsg helpers (implemented in src/cmsghdr.c)

/**
 * @brief Build a struct cmsghdr[] control buffer from a Lua table of cmsg
 * descriptors and push it onto the Lua stack as a single string.
 *
 * The table at Lua stack index `idx` is expected to be an array of tables of
 * the form `{ level = <string>, type = <string>, data =
 * <integer|string|integer[]> }`.
 *
 * `level` and `type` are short lowercase names (e.g. `"socket"` /
 * `"rights"`) that are mapped to their POSIX integer constants.  The
 * `data` field is interpreted according to the (level, type) pair:
 *
 *   - `("socket", "rights")` -> integer fd or table of fds (SCM_RIGHTS)
 *   - otherwise               -> raw string bytes copied into the cmsg
 *
 * Each cmsg entry is serialized into an exact CMSG_SPACE-sized Lua string,
 * and the strings are concatenated (via `lua_concat`) into a single string
 * whose bytes can be used directly as `msg_control` / `msg_controllen`.
 * Lua string content is aligned to `L_Umaxalign` (>= sizeof(long)), which
 * satisfies `struct cmsghdr` alignment on all supported platforms.
 *
 * @param L   Lua state.
 * @param idx Absolute Lua stack index of the cmsg table.
 * @return 1 if a control-buffer string was pushed onto L (the caller must
 *         obtain the pointer/length via `lua_tolstring(L, -1, &len)` and pop
 *         the string with `lua_pop(L, 1)` after sendmsg(2) returns), or 0 if
 *         the input table is empty (nothing pushed).  On invalid input this
 *         function raises via `luaL_error` and does not return.
 */
int net_cmsg_build_buffer(lua_State *L, int idx);

/**
 * @brief Convert the ancillary data recorded in a struct msghdr into a Lua
 * table array, and push it onto the Lua stack.
 *
 * Each cmsg is pushed as a table `{ level = <string|int>, type =
 * <string|int>, data = <special> }`.  When the (level, type) pair is
 * known, `level` and `type` use short lowercase names; otherwise the raw
 * integer values are used.  The `data` field is special-cased as follows:
 *
 *   - `SCM_RIGHTS`   -> integer fd (single fd) or integer[] table (multiple
 *                       fds)
 *   - `SCM_TIMESTAMP`-> table `{ sec = <integer>, usec = <integer> }`
 *   - otherwise      -> string (raw payload)
 *
 * If the msghdr contains no ancillary data, this function pushes nothing
 * and returns 0.
 *
 * @param L   Lua state.
 * @param msg Populated msghdr from a successful recvmsg(2) call.
 * @return 1 if a table was pushed, 0 otherwise.
 */
int net_cmsg_push_table(lua_State *L, const struct msghdr *msg);

// gc-callback thread helpers (implemented in src/gcthread.c)

/**
 * @brief Register a new gc callback.  Reads (errfn, fn, args...) from L
 * starting at stack index `argidx` and pushes a "net.socket.gcfn: %p" handle
 * string onto L.
 *
 * The socket's gc thread must already exist (it is allocated at
 * construction time).  If the socket has been closed and the thread
 * released, this function pushes nil + an EBADF error and returns 2.
 *
 * @param L      Lua state.
 * @param s      The socket userdata whose gc_thread is used to store the
 *               registered callback.
 * @param argidx Absolute stack index of the errfn argument.
 * @return Number of values pushed onto L (1 for the handle on success,
 *         2 for nil + error on EBADF).
 */
int net_gcthread_add(lua_State *L, net_socket_t *s, int argidx);

/**
 * @brief Remove a previously registered gc callback identified by its handle
 * string.  Pushes a boolean result onto L (true when removed, false when the
 * handle is well-formed but no longer registered).  Raises via luaL_argerror
 * when the handle string does not match the expected format.
 *
 * @param L          Lua state.
 * @param s          The socket userdata whose gc_thread is searched.
 * @param handle_idx Absolute stack index of the handle string.
 * @return Number of values pushed onto L (always 1: the boolean).
 */
int net_gcthread_del(lua_State *L, net_socket_t *s, int handle_idx);

/**
 * @brief Invoke every gc callback registered against the socket's gc
 * thread in LIFO order and release the thread.
 *
 * Errors raised by the registered callbacks are caught and either logged
 * to stderr (in release builds where NET_GCTHREAD_OUTPUT_STDERR is not
 * defined) or silently discarded (in test/debug builds).  This function
 * does not raise Lua errors, which makes it safe to call from close/gc
 * paths where allocating new Lua objects would crash LuaJIT during
 * lua_close finalization.
 *
 * @param L Lua state.
 * @param s The socket userdata whose gc thread is drained and released.
 */
void net_gcthread_close(lua_State *L, net_socket_t *s);

#endif // net_socket_h
