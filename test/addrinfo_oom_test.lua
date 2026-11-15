local testcase = require('testcase')
local assert = require('assert')
local newstate = require('newstate')
-- Keep native code loaded while the isolated state's userdata are finalized.
require('net.addrinfo')

function testcase.luaopen_net_addrinfo_completes_existing_metatable()
    local L = assert(newstate.new())
    local ok, err = L:dostring([[
        require('error')
        require('errno')
        require('errno.eai')
        local loaders = package.searchers or package.loaders
        local open = assert(loaders[3]('net.addrinfo'))
        local registry = debug.getregistry()
        -- Model an interrupted registration without depending on the
        -- runtime's allocation boundaries during metatable population.
        local partial = {}
        registry['net.addrinfo'] = partial

        local module = open()
        local mt = registry['net.addrinfo']
        assert(mt == partial)
        assert(type(mt.__gc) == 'function')
        assert(type(mt.__tostring) == 'function')
        local refs = {}
        for key, value in pairs(registry) do
            if type(key) == 'number' and type(value) == 'userdata' then
                refs[key] = value
            end
        end
        local ai = assert(module.inet('127.0.0.1', 80))
        for _, name in ipairs({'family', 'socktype', 'protocol', 'canonname',
                              'port', 'addr', 'getnameinfo'}) do
            assert(type(ai[name]) == 'function', name)
        end
        assert(ai:family() == 'inet')
        assert(ai:addr() == '127.0.0.1')
        assert(ai:port() == 80)
        local name = assert(ai:getnameinfo('numerichost', 'numericserv'))
        assert(name.host == '127.0.0.1' and name.service == '80')
        ai = nil
        collectgarbage('collect')
        collectgarbage('collect')
        -- The copied sockaddr must not remain rooted after its owner dies.
        for key, value in pairs(registry) do
            if type(key) == 'number' and type(value) == 'userdata' then
                assert(refs[key] == value, 'addrinfo storage reference leaked')
            end
        end
    ]])
    assert(ok, err)
end
