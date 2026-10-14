local fs = require('luarocks.fs')
local resolve = require('luarocks.build.hooks.lib.resvars')
local unpack = unpack or table.unpack
local rockspec = ...
local variables = rockspec.variables
local libdir = 'src/shared'
local libname = 'net_shared'
local incdirs = assert(resolve({
    '$(LUA_INCDIR)',
    '$(DEP_LAUXHLIB_INCDIR)',
}, variables))
local objects = {}

local function run(command, ...)
    print(fs.quote_args(command, ...))
    assert(fs.execute(command, ...), 'command failed: ' .. command)
end

for _, name in ipairs({
    'gcctx',
    'pcall',
}) do
    local source = libdir .. '/' .. name .. '.c'
    local object = libdir .. '/' .. name .. '.o'
    local args = {
        '-c', source, '-o', object,
    }
    for _, dir in ipairs(incdirs) do
        args[#args + 1] = '-I' .. dir
    end
    run(variables.CC .. ' ' .. variables.CFLAGS, unpack(args))
    objects[#objects + 1] = object
end

run(variables.AR, 'rcs', libdir .. '/lib' .. libname .. '.a', unpack(objects))
variables.NET_SHARED_LIB = libname
variables.NET_SHARED_LIBDIR = libdir
