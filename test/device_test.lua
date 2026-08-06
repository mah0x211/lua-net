local testcase = require('testcase')
local assert = require('assert')
local device = require('net.device')

local FLAG_FIELDS = {
    'up',
    'broadcast',
    'debug',
    'loopback',
    'pointtopoint',
    'notrailers',
    'running',
    'noarp',
    'promisc',
    'allmulti',
    'multicast',
    'oactive',
    'simplex',
    'master',
    'slave',
    'portsel',
    'automedia',
    'dynamic',
    'lower_up',
    'dormant',
    'echo',
}
local ADDRESS_FIELDS = {
    'address',
    'netmask',
    'broadcast',
    'point2point',
}

local function assert_address_list(list)
    assert.is_table(list)

    for _, addr in ipairs(list) do
        assert.is_table(addr)
        for _, name in ipairs(ADDRESS_FIELDS) do
            if addr[name] ~= nil then
                assert.is_string(addr[name])
            end
        end
    end
end

function testcase.getifaddrs()
    local interfaces = assert(device.getifaddrs())
    local has_loopback = false

    assert.is_table(interfaces)
    assert.not_empty(interfaces)

    for name, interface in pairs(interfaces) do
        assert.is_string(name)
        assert.is_table(interface)

        for _, field in ipairs(FLAG_FIELDS) do
            if interface[field] ~= nil then
                assert.is_boolean(interface[field])
            end
        end

        has_loopback = has_loopback or interface.loopback == true

        if interface.index ~= nil then
            assert.is_number(interface.index)
        end
        if interface.mtu ~= nil then
            assert.is_number(interface.mtu)
        end
        if interface.ether ~= nil then
            assert.is_string(interface.ether)
        end
        if interface.inet ~= nil then
            assert_address_list(interface.inet)
        end
        if interface.inet6 ~= nil then
            assert_address_list(interface.inet6)
        end
    end

    assert.is_true(has_loopback)
end
