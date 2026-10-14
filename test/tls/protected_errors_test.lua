local testcase = require('testcase')
local assert = require('assert')
local newstate = require('newstate')
local cert_fixtures = require('test.tls.cert_fixtures')

local CERT = os.tmpname()
local KEY = os.tmpname()

function testcase.before_all()
    cert_fixtures.server_certificate(CERT, KEY)
end

function testcase.after_all()
    os.remove(CERT)
    os.remove(KEY)
end

function testcase.get_peer_cert_preserves_allocation_error()
    local failures = 0
    local successes = 0
    for _, headroom in ipairs({
        0,
        128,
        256,
        512,
        2048,
        65536,
    }) do
        do
            local L = assert(newstate.new())
            local ok, success, result = L:dostring([[
                local cert, key, headroom = ...
                local socket = require('net.socket')
                local context = require('net.tls.context')
                local client = require('net.tls.client')({})
                local server = assert(require('net.tls.server')({cert = cert, key = key}))
                local memlimit = require('memlimit')
                local pair = assert(socket.pair({socktype = 'stream'}))
                local cctx = assert(context.connect(client, pair[1]:fd(), {
                    verify_cert = false,
                    verify_name = false,
                }))
                local sctx = assert(context.accept(server, pair[2]:fd()))
                local endpoints = {cctx, sctx}
                local done = {}
                for _ = 1, 64 do
                    for i, ctx in ipairs(endpoints) do
                        if not done[i] then
                            local success, err, want = ctx:handshake()
                            assert(not err, tostring(err))
                            assert(success or want == context.WANT_READ or
                                   want == context.WANT_WRITE)
                            done[i] = success
                        end
                        local bio = ctx:get_bio()
                        local _, err = bio:drain()
                        assert(not err, tostring(err))
                        _, err = bio:fill()
                        assert(not err, tostring(err))
                    end
                    if done[1] and done[2] then break end
                end
                assert(done[1] and done[2], 'handshake did not complete')
                local padding = string.rep('a', memlimit.minsize())
                collectgarbage('collect')
                collectgarbage('collect')
                collectgarbage('stop')
                local _, limited = memlimit.maxsize(memlimit.used() + headroom)
                assert(limited)
                local success, result = pcall(cctx.get_peer_cert, cctx)
                memlimit.maxsize(0)
                collectgarbage('restart')
                collectgarbage('collect')
                collectgarbage('collect')
                assert(cctx:get_peer_cert():match('^%-%-%-%-%-BEGIN CERTIFICATE'))
                assert(cctx:close())
                assert(sctx:close())
                assert(pair[1]:close())
                assert(pair[2]:close())
                return success, result, #padding
            ]], CERT, KEY, headroom)
            assert(ok, success)
            if success then
                assert.match(result, '^-----BEGIN CERTIFICATE', false)
                successes = successes + 1
            else
                if result ~= 'not enough memory' then
                    assert.match(result,
                                 '^src/tls_context%.c:%d+: get_peer_cert_lua: not enough memory$',
                                 false)
                end
                failures = failures + 1
            end
        end
        collectgarbage('collect')
    end
    assert.greater(failures, 0)
    assert.greater(successes, 0)
end

function testcase.clear_preserves_table_allocation_error()
    local L = assert(newstate.new())
    local ok, success, result, before, after = L:dostring([[
        local cache = require('net.tls.cache')({ctx_capacity = 1})
        local client = assert(require('net.tls.client')({cache = cache}))
        local memlimit = require('memlimit')
        local padding = string.rep('a', memlimit.minsize())
        collectgarbage('collect')
        collectgarbage('collect')
        collectgarbage('stop')
        local _, limited = memlimit.maxsize(memlimit.used())
        assert(limited)
        local success, result = pcall(cache.clear, cache)
        memlimit.maxsize(0)
        collectgarbage('restart')
        local before = cache:size()
        assert(cache:clear())
        return success, result, before, cache:size(), client ~= nil, #padding
    ]])
    assert(ok, success)
    assert.is_false(success)
    if result ~= 'not enough memory' then
        assert.match(result,
                     '^src/tls_cache_store%.h:%d+: tls_cache_store_clear: not enough memory$',
                     false)
    end
    assert.equal(before, 1)
    assert.equal(after, 0)
end
