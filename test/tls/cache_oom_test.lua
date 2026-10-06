local testcase = require('testcase')
local assert = require('assert')
local newstate = require('newstate')
local fork = require('testcase.fork')
local exit = require('testcase.exit').exit

function testcase.clear_oom_preserves_cache_and_reference_slots()
    local proc = assert(fork())
    if proc:is_child() then
        local success, err = pcall(function()
            local failures = 0
            local successes = 0
            local headrooms = {}
            for headroom = 0, 1024, 16 do
                headrooms[#headrooms + 1] = headroom
            end
            headrooms[#headrooms + 1] = 65536
            for _, session_capacity in ipairs({
                0,
                8,
            }) do
                for _, headroom in ipairs(headrooms) do
                    do
                        local L = assert(newstate.new())
                        local ok, cleared, result = L:dostring([[
                            local session_capacity, headroom = ...
                            -- newstate transfers numbers as lua_Number.
                            session_capacity = math.floor(session_capacity)
                            headroom = math.floor(headroom)
                            local new = require('net.tls.client')
                            local cache = require('net.tls.cache')({
                                ctx_capacity = 8,
                                session_capacity = session_capacity,
                            })
                            local client = assert(new({cache = cache}))
                            local registry = debug.getregistry()
                            local function count_tables()
                                local count = 0
                                local seen = {}
                                local slots = {}
                                for key, value in pairs(registry) do
                                    assert(not seen[key], 'registry iteration repeated a key')
                                    seen[key] = true
                                    if type(key) == 'number' and type(value) == 'table' then
                                        count = count + 1
                                        slots[key] = true
                                    end
                                end
                                return count, slots
                            end
                            local memlimit = require('memlimit')
                            local padding = string.rep('a', memlimit.minsize())
                            local before, before_slots = count_tables()
                            collectgarbage('collect')
                            collectgarbage('collect')
                            collectgarbage('stop')
                            local _, limited = memlimit.maxsize(memlimit.used() + headroom)
                            assert(limited)
                            local cleared, result = pcall(cache.clear, cache)
                            memlimit.maxsize(0)
                            collectgarbage('restart')
                            collectgarbage('collect')
                            collectgarbage('collect')
                            local after, after_slots = count_tables()
                            assert(after == before, string.format(
                                'registry tables: before=%d after=%d cleared=%s capacity=%d headroom=%d',
                                before, after, tostring(cleared), session_capacity, headroom))
                            for ref in pairs(before_slots) do
                                assert(after_slots[ref], 'cache reference slot was removed')
                            end
                            local nctx, nsess = cache:size()
                            assert(nctx == (cleared and 0 or 1))
                            assert(nsess == 0)
                            assert(new({cache = cache}))
                            assert(cache:clear())
                            nctx, nsess = cache:size()
                            assert(nctx == 0 and nsess == 0)
                            assert(type(tostring(client)) == 'string')
                            return cleared, result, #padding
                        ]], session_capacity, headroom)
                        assert(ok, cleared)
                        if cleared then
                            assert.is_true(result)
                            successes = successes + 1
                        else
                            assert.equal(result, 'not enough memory')
                            failures = failures + 1
                        end
                    end
                    collectgarbage('collect')
                end
            end
            assert.greater(failures, 0)
            assert.greater(successes, 0)
        end)
        if not success then
            io.stderr:write(tostring(err), '\n')
        end
        exit(success and 0 or 1)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end
