std = 'max'
include_files = {
    'net.lua',
    'lib/*.lua',
    'lib/*/*.lua',
    'test/*_test.lua',
}
ignore = {
    -- unused argument
    '212',
    --    -- unused loop variable
    --    '213',
    --    -- redefining a local variable
    --    '411',
    --    -- shadowing a local variable
    --    '421',
}

