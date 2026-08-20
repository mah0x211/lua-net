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
#include "net_socket.h"

// String prefix used for handle values returned by net_gcthread_add.  The
// full handle looks like "net.socket.gcfn: 0x7fa1b2c3d4e0".
#define GCFN_HANDLE_PREFIX     "net.socket.gcfn: "
#define GCFN_HANDLE_PREFIX_LEN (sizeof(GCFN_HANDLE_PREFIX) - 1)

// When to report gc callback errors to stderr instead of silently
// discarding them.
//
// gcfn_closure() itself always propagates a failing callback via
// lua_error(), which net_gcthread_close() catches through its own
// pcall.  What differs between builds is what happens after the catch:
//
//   - Release builds (NET_GCTHREAD_OUTPUT_STDERR undefined) write the
//     captured error message to stderr so operators can see it.
//   - Test/debug builds (NET_GCTHREAD_OUTPUT_STDERR defined via
//     NET_COVERAGE or !NDEBUG) silently discard the message so unit
//     tests can drive the failure paths without cluttering test output.
//
// The reason for the split is LuaJIT's lua_close(): its finalization GC
// phase forbids allocating new Lua objects.  Raising a Lua error via
// lua_error() / lua_error_format() allocates an error object and can
// therefore crash LuaJIT when driven during the close/gc path.  By
// funnelling the diagnostic through stderr or discarding it entirely,
// net_gcthread_close() never allocates on the close/gc path itself.
#if defined(NET_COVERAGE) || !defined(NDEBUG)
# define NET_GCTHREAD_OUTPUT_STDERR 1
#endif

// C closure invoked when a socket is closed / garbage-collected.  It calls
// the user-registered gc callback with the recorded arguments; if the
// callback fails, the user-supplied errfn (if any) is used as pcall's error
// handler so it can transform the error before it is captured on the Lua
// stack.  Regardless of whether errfn transformed the error successfully,
// the failure is re-raised via lua_error() so that net_gcthread_close() can
// decide what to do with the accumulated diagnostic.
//
// Upvalues layout:
//   1 = nargs   : integer (number of extra arguments)
//   2 = errfn   : function or nil
//   3 = fn      : function (the gc callback itself)
//   4..3+nargs  : the extra arguments
static int gcfn_closure(lua_State *L)
{
    int nargs     = (int)lua_tointeger(L, lua_upvalueindex(1));
    int has_errfn = !lua_isnil(L, lua_upvalueindex(2));
    int errfunc   = 0;

    // this closure runs on the gc thread via pcall, which guarantees only
    // LUA_MINSTACK slots; the argument copies can exceed that, so grow the
    // stack explicitly.  The raised error is caught by the pcall in
    // net_gcthread_close().
    luaL_checkstack(L, nargs + 2, "too many gc callback arguments");
    if (has_errfn) {
        lua_pushvalue(L, lua_upvalueindex(2));
        errfunc = lua_gettop(L);
    }
    lua_pushvalue(L, lua_upvalueindex(3));
    for (int i = 0; i < nargs; i++) {
        lua_pushvalue(L, lua_upvalueindex(4 + i));
    }
    if (lua_pcall(L, nargs, 0, errfunc) != 0) {
        // Propagate the error to the caller (net_gcthread_close) so that it
        // can decide what to do with it (log to stderr or discard).  We do
        // not write to stderr here; that responsibility belongs to the
        // enclosing net_gcthread_close so that libraries embedding this code
        // can control that behaviour with a single knob.
        return lua_error(L);
    }
    if (has_errfn) {
        lua_pop(L, 1); // remove errfunc slot
    }
    return 0;
}

int net_gcthread_add(lua_State *L, net_socket_t *s, int argidx)
{
    int top   = lua_gettop(L);
    int nargs = top - (argidx + 1);

    if (!s->gc_thread) {
        // socket has already been closed and its gc thread released
        lua_pushnil(L);
        lua_errno_new(L, EBADF, "addgcfn");
        return 2;
    }

    // arg argidx     : errfn (function or nil)
    // arg argidx + 1 : fn    (function)
    // args argidx+2+ : extra arguments to pass to fn
    if (!lua_isnoneornil(L, argidx)) {
        luaL_checktype(L, argidx, LUA_TFUNCTION);
    }
    luaL_checktype(L, argidx + 1, LUA_TFUNCTION);

    // Push upvalues onto the socket's gc thread stack in the order the
    // closure expects:
    //   [1] nargs, [2] errfn (or nil), [3] fn, [4..3+nargs] extra args
    // The gc thread is not the running state, so its stack must be grown
    // explicitly; luaL_checkstack() would try to raise the error on the
    // non-running state and panic.  Raise the Lua error on the caller's
    // (running) state instead, like every other allocation failure in the
    // library.
    if (!lua_checkstack(s->gc_thread, nargs + 4)) {
        return luaL_error(L, "too many arguments to addgcfn");
    }
    lua_pushinteger(s->gc_thread, nargs);
    if (lua_isnoneornil(L, argidx)) {
        lua_pushnil(s->gc_thread);
    } else {
        lua_pushvalue(L, argidx);
        lua_xmove(L, s->gc_thread, 1);
    }
    lua_pushvalue(L, argidx + 1);
    lua_xmove(L, s->gc_thread, 1);
    for (int i = argidx + 2; i <= top; i++) {
        lua_pushvalue(L, i);
        lua_xmove(L, s->gc_thread, 1);
    }
    // Wrap them into a C closure that lives on the thread's stack until it
    // is popped by net_gcthread_del or invoked during close/gc.
    lua_pushcclosure(s->gc_thread, gcfn_closure, 1 + 1 + 1 + nargs);

    // The handle is a hex-formatted pointer to the closure so that
    // net_gcthread_del can locate the exact slot on the thread stack.  Lua
    // uses a non-moving GC, so this pointer stays valid for the lifetime of
    // the closure.
    lua_pushfstring(L, GCFN_HANDLE_PREFIX "%p",
                    lua_topointer(s->gc_thread, -1));
    return 1;
}

int net_gcthread_del(lua_State *L, net_socket_t *s, int handle_idx)
{
    size_t handle_len  = 0;
    const char *handle = luaL_checklstring(L, handle_idx, &handle_len);
    void *ptr          = NULL;

    if (s->gc_thread == NULL) {
        // socket has already been closed and its gc thread released; no
        // registered callback remains that could match the handle.
        lua_pushboolean(L, 0);
        return 1;
    }

    // The handle is expected to be a string of the form "net.socket.gcfn:
    // 0x7fa1b2c3d4e0".  The prefix is used to identify the handle type, and the
    // hex-formatted pointer is used to locate the closure on the thread stack.
    if (handle_len < GCFN_HANDLE_PREFIX_LEN ||
        strncmp(handle, GCFN_HANDLE_PREFIX, GCFN_HANDLE_PREFIX_LEN) != 0) {
        return luaL_argerror(
            L, handle_idx,
            "not a net.socket.gcfn handle (expected 'net.socket.gcfn: 0x...')");
    } else if (sscanf(handle + GCFN_HANDLE_PREFIX_LEN, "%p", &ptr) != 1 ||
               ptr == NULL) {
        return luaL_argerror(L, handle_idx, "invalid net.socket.gcfn handle");
    }

    for (int i = 1, top = lua_gettop(s->gc_thread); i <= top; i++) {
        if (lua_topointer(s->gc_thread, i) == ptr) {
            // Remove the closure in place.  lua_remove() shifts the upper
            // elements down within the existing stack, so unlike the
            // pushvalue+replace dance it never needs a spare slot above
            // the stack high-water mark.
            lua_remove(s->gc_thread, i);
            lua_pushboolean(L, 1);
            return 1;
        }
    }

    // handle was well-formed but not found on the thread stack
    lua_pushboolean(L, 0);
    return 1;
}

void net_gcthread_close(lua_State *L, net_socket_t *s)
{
    if (s->gc_thread == NULL) {
        return;
    }

    // invoke gc callbacks in LIFO order.  Each closure sits on the top of
    // the thread stack; pcall pops it and executes it.
    while (lua_gettop(s->gc_thread) > 0) {
        if (lua_pcall(s->gc_thread, 0, 0, 0) != 0) {
#ifndef NET_GCTHREAD_OUTPUT_STDERR
            // Release build: report to stderr; raising here would allocate new
            // Lua objects and can crash LuaJIT during lua_close finalization.
            // the error value may be a non-string, in which case
            // lua_tostring() returns NULL and must not reach fprintf("%s").
            const char *err = lua_tostring(s->gc_thread, -1);
            fprintf(stderr, "net.socket: gc callback error: %s\n",
                    err ? err : "(non-string error value)");
#endif
            lua_pop(s->gc_thread, 1);
        }
    }

    // release the thread reference and reset the slot to LUA_NOREF so that
    // subsequent close/gc paths are no-ops.
    s->gc_thread     = NULL;
    s->gc_thread_ref = lauxh_unref(L, s->gc_thread_ref);
}
