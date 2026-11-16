local testcase = require('testcase')
local assert = require('assert')
local newstate = require('newstate')
-- Keep native code loaded while the isolated states are collected.
require('net.tls.cache')

function testcase.luaopen_net_tls_cache_completes_existing_owner_metatables()
    local L = assert(newstate.new())
    local ok, err = L:dostring([[
        local loaders = package.searchers or package.loaders
        local open = assert(loaders[3]('net.tls.cache'))
        local registry = debug.getregistry()
        -- Both owners need finalizers even when their registered tables
        -- survived an interrupted initializer. No owner exists yet.
        local ctx_mt, session_mt = {}, {}
        registry['net.tls.ssl_ctx'] = ctx_mt
        registry['net.tls.ssl_session'] = session_mt

        local new_cache = open()
        assert(registry['net.tls.ssl_ctx'] == ctx_mt)
        assert(registry['net.tls.ssl_session'] == session_mt)
        assert(type(ctx_mt.__gc) == 'function')
        assert(type(session_mt.__gc) == 'function')
        local cache = assert(new_cache())
        assert(cache:clear())
        local nctx, nsessions = cache:size()
        assert(nctx == 0 and nsessions == 0)
        cache = nil
        collectgarbage('collect')
        collectgarbage('collect')
    ]])
    assert(ok, err)
end
