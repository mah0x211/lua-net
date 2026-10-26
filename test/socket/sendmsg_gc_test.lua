local testcase = require('testcase')
local assert = require('assert')
local newstate = require('newstate')

function testcase.sendmsg_keeps_computed_level_alive_during_type_lookup()
    local L = assert(newstate.new())
    assert(L:loadstring([[
        local native = require('net.socket')
        local socks = assert(native.pair({socktype = 'stream'}))
        local type_looked_up = false
        local descriptor = setmetatable({}, {
            __index = function(_, key)
                if key == 'level' then
                    -- Do not retain the accepted name in a Lua constant
                    -- or table field in this isolated state.
                    return string.char(115, 111, 99, 107, 101, 116)
                elseif key == 'type' then
                    type_looked_up = true
                    collectgarbage('collect')
                    return 'unknown-type'
                end
            end,
        })
        local ok, err = pcall(socks[1].sendmsg, socks[1], 'x', nil,
                              {descriptor})
        socks[1]:close()
        socks[2]:close()
        assert(type_looked_up)
        assert(not ok)
        local expected = "unknown type 'unknown-type' for level '" ..
                         string.char(115, 111, 99, 107, 101, 116) .. "'"
        assert(type(err) == 'string' and string.find(err, expected, 1, true),
               tostring(err))
        return true
    ]]))
    local ok, result = L:run()
    assert(ok, result)
    assert.is_true(result)
end
