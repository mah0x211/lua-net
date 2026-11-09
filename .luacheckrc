std = 'max'
include_files = {
    'net.lua',
    'scripts/*.lua',
    'lib/*.lua',
    'lib/*/*.lua',
    'lib/*/*/*.lua',
    'test/*_test.lua',
    'test/*/*_test.lua',
    'test/*/*/*_test.lua',
    'test/*/*/*/*_test.lua',
    'test/fork_helpers.lua',
    'test/offset_payload.lua',
    'test/socket_helpers.lua',
    'test/tls/cert_fixtures.lua',
    'test/tls/context/helpers.lua',
    'test/tls/context/fixtures.lua',
    'test/tls/context/support.lua',
    'test/tls/stream/inet/helpers.lua',
    'test/stream/inet/helpers.lua',
}
ignore = {
    'assert',
    -- unused argument
    '212',
    --    -- unused loop variable
    --    '213',
    --    -- redefining a local variable
    --    '411',
    --    -- shadowing a local variable
    --    '421',
    -- Line is too long
    '631',
}

