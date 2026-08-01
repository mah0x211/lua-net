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
 */

#ifndef net_optcheck_h
#define net_optcheck_h

#include <lauxlib.h>
#include <string.h>

/**
 * @brief Callback for net_socket_option_spec_t that handles a single key/value
 * pair in an opts table.
 *
 * Handles a single key/value pair in an opts table. key is the string key, and
 * the value is at stack index -1. the value is consumed(popped) from the stack
 * by the callback, but the key is not.
 *
 * @param L Lua state.
 * @param name Key name.
 * @param ctx Caller-defined pointer passed through to the callback.
 * @return 0 on success; a Lua error is raised on any failure.
 */
typedef int (*net_socket_option_spec_cb)(lua_State *L, const char *name,
                                         void *ctx);

/**
 * @brief Single opts table entry declaration.
 *
 * `net_socket_option_spec_t` binds a Lua string key to a C callback that
 * consumes the corresponding value.  Modules describe their accepted opts as a
 * compile-time array of these entries.
 */
typedef struct {
    // Lua-visible key name in the opts table.
    const char *name;
    // Consume the value at stack index -1 and update `ctx` accordingly.
    // Returns 0 on success; a Lua error is raised on any failure.
    net_socket_option_spec_cb callback;
} net_socket_option_spec_t;

/**
 * @brief Iterate the opts table at `idx` and dispatch each key to its spec's
 * callback.  A missing, nil, or none value at `idx` skips iteration.  A
 * non-table value, non-string keys raise a Lua error.  Unknown keys are
 * ignored.  The `ctx` pointer is passed through to every callback.
 *
 * @param L Lua state.
 * @param idx Stack index of the opts value.
 * @param specs Array describing every accepted key.
 * @param nspecs Number of entries in `specs`.
 * @param ctx Caller-defined pointer passed through to every callback.
 */
static inline void
net_socket_check_options(lua_State *L, int idx,
                         const net_socket_option_spec_t specs[], size_t nspecs,
                         void *ctx)
{
#define OPTCHECK_MAX_SPECS 32

    char seen[OPTCHECK_MAX_SPECS] = {0};
    const char *key               = NULL;
    size_t i                      = 0;

    // check that opts is a table and that the specs array is not too large
    if (lua_isnoneornil(L, idx)) {
        // no opts table, skip iteration
        return;
    } else if (lua_type(L, idx) != LUA_TTABLE) {
        luaL_error(L, "opts must be table, got %s", luaL_typename(L, idx));
    } else if (nspecs > OPTCHECK_MAX_SPECS) {
        luaL_error(L, "opts spec array too large: %d > %d", (int)nspecs,
                   (int)OPTCHECK_MAX_SPECS);
    }

#undef OPTCHECK_MAX_SPECS

    lua_pushnil(L);
CHECK_NEXT:
    if (lua_next(L, idx) != 0) {
        if (lua_type(L, -2) != LUA_TSTRING) {
            luaL_error(L, "opts keys must be strings");
        }
        key = lua_tostring(L, -2);

        // dispatch to the matching spec callback
        for (i = 0; i < nspecs; i++) {
            if (!seen[i] && strcmp(key, specs[i].name) == 0) {
                seen[i] = 1;
                specs[i].callback(L, key, ctx);
                lua_pop(L, 1);
                goto CHECK_NEXT;
            }
        }
        // ignore unknown keys, but pop the value from the stack
        lua_pop(L, 1);
        goto CHECK_NEXT;
    }
}

// Convenience macro that derives the spec count from a compile-time array.
#define NET_SOCKET_CHECK_OPTIONS(L, idx, specs, ctx)                           \
    net_socket_check_options((L), (idx), (specs),                              \
                             sizeof(specs) / sizeof((specs)[0]), (ctx))

#endif // net_optcheck_h
