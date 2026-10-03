#!/bin/sh
set -eu

# Use the same interpreter headers and library as the extension build.
lua_incdir=$(luarocks config variables.LUA_INCDIR)
lua_libdir=$(luarocks config variables.LUA_LIBDIR)
lua_lib=$(luarocks config variables.LUALIB)
lua_cc=$(luarocks config variables.CC)
test_dir=$(mktemp -d)
trap 'rm -f "$test_dir/pcall_test"; rmdir "$test_dir"' EXIT HUP INT TERM

# CC may include an environment assignment or compiler flags.
$lua_cc -std=c99 -Wall -Wextra -Werror -Isrc -I"$lua_incdir" \
    test/native/pcall_test.c "$lua_libdir/$lua_lib" -lm -ldl \
    -o "$test_dir/pcall_test"
"$test_dir/pcall_test"
