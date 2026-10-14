/*
 * Copyright (C) 2026 Masatoshi Fukunaga
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */
#ifndef _GNU_SOURCE
# define _GNU_SOURCE
#endif
#include "pcall.h"
#include <assert.h>
#include <lauxlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    size_t blocks;
    size_t allocations;
    size_t fail_after;
} allocator_t;

static void *allocate(void *ud, void *ptr, size_t oldsize, size_t size)
{
    allocator_t *a = ud;
    void *result;
    int is_new = ptr == NULL;

    if (!size) {
        if (ptr) {
            a->blocks--;
        }
        free(ptr);
        return NULL;
    }
    if (!ptr || size > oldsize) {
        a->allocations++;
        // Keep failing so Lua's emergency GC cannot mask the fault.
        if (a->fail_after && a->allocations >= a->fail_after) {
            return NULL;
        }
    }
    result = realloc(ptr, size);
    if (result && is_new) {
        a->blocks++;
    }
    return result;
}

static int allocate_lua(lua_State *L)
{
    int *completed = lua_touserdata(L, 1);
    char text[512];
    memset(text, 'x', sizeof(text));
    lua_newuserdata(L, sizeof(text));
    lua_createtable(L, 0, 8);
    lua_pushlstring(L, text, sizeof(text));
    lua_setfield(L, -2, "text");
    *completed = 1;
    return 2; // Results must not leak into the caller's stack.
}

static int error_lua(lua_State *L)
{
    lua_pushlightuserdata(L, lua_touserdata(L, 1));
    return lua_error(L);
}

static int object_error_lua(lua_State *L)
{
    lua_newtable(L);
    lua_newtable(L);
    lua_pushcfunction(L, error_lua);
    lua_setfield(L, -2, "__tostring");
    lua_setmetatable(L, -2);
    return lua_error(L);
}

static void assert_error_string(lua_State *L, int idx)
{
    assert(lua_type(L, idx) == LUA_TSTRING);
    assert(strncmp(lua_tostring(L, idx), "userdata: ", 10) == 0);
}

static int nested_lua(lua_State *L)
{
    void *arg = lua_touserdata(L, 1);
    assert(net_pcall(L, error_lua, arg) == LUA_ERRRUN);
    assert(lua_gettop(L) == 2);
    assert_error_string(L, 2);
    lua_pop(L, 1);
    assert(lua_touserdata(L, 1) == arg);
    return 0;
}

static size_t allocation_test(size_t fail_after)
{
    allocator_t a = {0};
    lua_State *L  = lua_newstate(allocate, &a);
    int completed = 0;
    int status;
    size_t allocations;
    assert(L);
    lua_pushinteger(L, 42);
    a.allocations = 0;
    a.fail_after  = fail_after;
    status        = net_pcall(L, allocate_lua, &completed);
    allocations   = a.allocations;
    a.fail_after  = 0;
    assert(lua_tointeger(L, 1) == 42);
    if (fail_after) {
        assert(status == LUA_ERRMEM);
        assert(lua_gettop(L) == 2);
        assert(strcmp(lua_tostring(L, 2), "not enough memory") == 0);
        assert(!completed);
    } else {
        assert(status == 0);
        assert(lua_gettop(L) == 1);
        assert(completed);
        assert(net_pcall(L, error_lua, &completed) == LUA_ERRRUN);
        assert(lua_gettop(L) == 2);
        assert_error_string(L, 2);
        lua_pop(L, 1);
        assert(net_pcall(L, nested_lua, &completed) == 0);
        assert(lua_gettop(L) == 1);
        assert(lua_tointeger(L, 1) == 42);
    }
    lua_close(L);
    assert(a.blocks == 0);
    return allocations;
}

static size_t thread_refs(lua_State *L)
{
    size_t n = 0;
    lua_pushnil(L);
    while (lua_next(L, LUA_REGISTRYINDEX)) {
        n += lua_isthread(L, -1) != 0;
        lua_pop(L, 1);
    }
    return n;
}

static void prime_refs(lua_State *L)
{
    lua_pushboolean(L, 1);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    luaL_unref(L, LUA_REGISTRYINDEX, ref);
}

static size_t stringify_allocation_test(size_t fail_after)
{
    allocator_t a = {0};
    lua_State *L  = lua_newstate(allocate, &a);
    int arg;
    assert(L);
    prime_refs(L);
    lua_pushinteger(L, 42);
    size_t refs        = thread_refs(L);
    a.allocations      = 0;
    a.fail_after       = fail_after;
    int status         = net_pcall(L, error_lua, &arg);
    size_t allocations = a.allocations;
    a.fail_after       = 0;
    assert(status == LUA_ERRRUN || status == LUA_ERRMEM);
    assert(lua_gettop(L) == 2);
    assert(lua_tointeger(L, 1) == 42);
    assert(lua_type(L, 2) == LUA_TSTRING);
    if (fail_after) {
        assert(strcmp(lua_tostring(L, 2), "not enough memory") == 0);
    } else {
        assert(status == LUA_ERRRUN);
        assert_error_string(L, 2);
    }
    lua_settop(L, 1);
    assert(thread_refs(L) == refs);
    lua_close(L);
    assert(a.blocks == 0);
    return allocations;
}

static int values_lua(lua_State *L)
{
    void *arg = lua_touserdata(L, 1);
    lua_pushinteger(L, 17);
    lua_pushnil(L);
    lua_pushlightuserdata(L, arg);
    return 3;
}

static int many_values_lua(lua_State *L)
{
    for (int i = 1; i <= LUA_MINSTACK; i++) {
        lua_pushinteger(L, i);
    }
    return LUA_MINSTACK;
}

static int nested_results_lua(lua_State *L)
{
    void *arg = lua_touserdata(L, 1);
    assert(net_pcall_ex(L, values_lua, arg, 3) == 0);
    assert(lua_gettop(L) == 4);
    assert(lua_tointeger(L, 2) == 17);
    assert(lua_isnil(L, 3));
    assert(lua_touserdata(L, 4) == arg);
    return 3;
}

static void result_test(void)
{
    allocator_t a = {0};
    lua_State *L  = lua_newstate(allocate, &a);
    int arg;
    assert(L);
    prime_refs(L);
    lua_pushinteger(L, 42);
    size_t refs = thread_refs(L);
    for (int wanted = 1; wanted <= 5; wanted++) {
        assert(net_pcall_ex(L, values_lua, &arg, wanted) == 0);
        assert(lua_gettop(L) == 1 + wanted);
        assert(lua_tointeger(L, 1) == 42);
        assert(lua_tointeger(L, 2) == 17);
        if (wanted >= 2) {
            assert(lua_isnil(L, 3));
        }
        if (wanted >= 3) {
            assert(lua_touserdata(L, 4) == &arg);
        }
        for (int i = 4; i <= wanted; i++) {
            assert(lua_isnil(L, 1 + i));
        }
        lua_settop(L, 1);
        assert(thread_refs(L) == refs);
    }
    assert(net_pcall_ex(L, many_values_lua, &arg, LUA_MINSTACK) == 0);
    assert(lua_gettop(L) == 1 + LUA_MINSTACK);
    for (int i = 1; i <= LUA_MINSTACK; i++) {
        assert(lua_tointeger(L, i + 1) == i);
    }
    lua_settop(L, 1);
    assert(net_pcall_ex(L, nested_results_lua, &arg, 3) == 0);
    assert(lua_gettop(L) == 4);
    assert(lua_tointeger(L, 2) == 17);
    assert(lua_isnil(L, 3));
    assert(lua_touserdata(L, 4) == &arg);
    lua_settop(L, 1);
    assert(net_pcall_ex(L, error_lua, &arg, 1) == LUA_ERRRUN);
    assert(lua_gettop(L) == 2);
    assert_error_string(L, 2);
    lua_settop(L, 1);
    assert(net_pcall_ex(L, values_lua, &arg, 0) == LUA_OK);
    assert(lua_gettop(L) == 1);
    assert(net_pcall_ex(L, error_lua, &arg, 0) == LUA_ERRRUN);
    assert(lua_gettop(L) == 2);
    assert_error_string(L, 2);
    assert(lua_tointeger(L, 1) == 42);
    lua_settop(L, 1);
    assert(net_pcall(L, object_error_lua, &arg) == LUA_ERRRUN);
    assert(lua_gettop(L) == 2);
    // A failing __tostring is not retried or converted a second time.
    assert(lua_type(L, 2) == LUA_TLIGHTUSERDATA);
    assert(lua_touserdata(L, 2) == NULL);
    assert(thread_refs(L) == refs);
    lua_close(L);
    assert(a.blocks == 0);
}

static size_t result_allocation_test(size_t fail_after)
{
    allocator_t a = {0};
    lua_State *L  = lua_newstate(allocate, &a);
    int completed = 0;
    assert(L);
    prime_refs(L);
    lua_pushinteger(L, 42);
    size_t refs        = thread_refs(L);
    a.allocations      = 0;
    a.fail_after       = fail_after;
    int status         = net_pcall_ex(L, allocate_lua, &completed, 2);
    size_t allocations = a.allocations;
    a.fail_after       = 0;
    assert(lua_tointeger(L, 1) == 42);
    if (fail_after) {
        assert(status == LUA_ERRMEM);
        assert(lua_gettop(L) == 2);
        assert(strcmp(lua_tostring(L, 2), "not enough memory") == 0);
    } else {
        assert(status == 0);
        assert(completed);
        assert(lua_gettop(L) == 3);
        assert(lua_isuserdata(L, 2));
        assert(lua_istable(L, 3));
    }
    lua_settop(L, 1);
    assert(thread_refs(L) == refs);
    lua_close(L);
    assert(a.blocks == 0);
    return allocations;
}

static void result_stack_limit_test(void)
{
    allocator_t a = {0};
    lua_State *L  = lua_newstate(allocate, &a);
    int arg;
    assert(L);
    prime_refs(L);
    size_t refs = thread_refs(L);
#if LUA_VERSION_NUM == 501
    int count = LUAI_MAXCSTACK - 2;
#else
    int count = LUAI_MAXSTACK - 17;
#endif
    assert(lua_checkstack(L, count + 2));
    for (int i = 0; i < count; i++) {
        lua_pushinteger(L, 42);
    }
    assert(net_pcall_ex(L, values_lua, &arg, LUA_MINSTACK) == LUA_ERRMEM);
    assert(lua_gettop(L) == count + 1);
    assert(strcmp(lua_tostring(L, -1), "not enough memory") == 0);
    lua_settop(L, 0);
    assert(thread_refs(L) == refs);
    lua_close(L);
    assert(a.blocks == 0);
}

#if LUA_VERSION_NUM >= 502
static void setup_allocation_test(int nresults)
{
    allocator_t a = {0};
    lua_State *L  = lua_newstate(allocate, &a);
    int arg;
    assert(L);
    a.allocations = 0;
    a.fail_after  = 1;
    // Fill the physical stack until growth fails, then leave one error slot.
    while (lua_checkstack(L, 1)) {
        lua_pushinteger(L, 42);
    }
    lua_pop(L, 1);
    int top      = lua_gettop(L);
    int status   = net_pcall_ex(L, values_lua, &arg, nresults);
    a.fail_after = 0;
    assert(status == LUA_ERRMEM);
    assert(lua_gettop(L) == top + 1);
    assert(strcmp(lua_tostring(L, -1), "not enough memory") == 0);
    lua_close(L);
    assert(a.blocks == 0);
}
#endif

int main(void)
{
    size_t allocations = allocation_test(0);
    assert(allocations > 0);
    for (size_t n = 1; n <= allocations; n++) {
        allocation_test(n);
    }
    printf("%s: protected calls passed (%zu allocation failure points)\n",
           LUA_VERSION, allocations);
    result_test();
    result_stack_limit_test();
#if LUA_VERSION_NUM >= 502
    setup_allocation_test(0);
    setup_allocation_test(2);
#endif
    allocations = result_allocation_test(0);
    assert(allocations > 0);
    for (size_t n = 1; n <= allocations; n++) {
        result_allocation_test(n);
    }
    printf("%s: protected results passed (%zu allocation failure points)\n",
           LUA_VERSION, allocations);
    allocations = stringify_allocation_test(0);
    assert(allocations > 0);
    for (size_t n = 1; n <= allocations; n++) {
        stringify_allocation_test(n);
    }
    printf("%s: protected error stringification passed (%zu allocation failure "
           "points)\n",
           LUA_VERSION, allocations);
    return 0;
}
