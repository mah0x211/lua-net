local testcase = require('testcase')
local assert = require('assert')
local newstate = require('newstate')
local cert_fixtures = require('test.tls.cert_fixtures')

local CERT = os.tmpname()
local KEY = os.tmpname()
local HEADROOMS = {}
for headroom = 0, 1024, 16 do
    HEADROOMS[#HEADROOMS + 1] = headroom
end
-- Include a successful construction even on runtimes with larger allocations.
HEADROOMS[#HEADROOMS + 1] = 65536

function testcase.before_all()
    cert_fixtures.server_certificate(CERT, KEY)
end

function testcase.after_all()
    os.remove(CERT)
    os.remove(KEY)
end

local SCRIPT = [[
    local server, cached, cert, key, headroom = ...
    local new = require(server and 'net.tls.server' or 'net.tls.client')
    local cache = require('net.tls.cache')({ctx_capacity = 8})
    local registry = debug.getregistry()
    -- Warm persistent CTX references separately from the ALPN allocation.
    local contexts = {}
    for i = 1, 16 do
        contexts[i] = assert(new({cert = cert, key = key}))
    end
    contexts = nil
    collectgarbage('collect')
    collectgarbage('collect')
    local opts = {
        cert = cert,
        key = key,
        alpn = {'oom-registry-protocol'},
        cache = cached and cache or nil,
    }
    local memlimit = require('memlimit')
    -- Retain enough live memory to stay above memlimit.minsize() after
    -- collecting module-loader garbage, including emergency-GC candidates.
    local padding = string.rep('a', 65536)
    collectgarbage('collect')
    collectgarbage('collect')
    collectgarbage('stop')
    local _, limited = memlimit.maxsize(memlimit.used() + headroom)
    assert(limited)
    local success, result = pcall(new, opts)
    memlimit.maxsize(0)
    collectgarbage('restart')
    local err = not success and result or nil
    result = nil
    cache:clear()
    -- Do not intern the wire string before injecting the allocation failure.
    local wire = string.char(21) .. 'oom-registry-protocol'
    collectgarbage('collect')
    collectgarbage('collect')
    local leaked = 0
    for _, value in pairs(registry) do
        if value == wire then
            leaked = leaked + 1
        end
    end
    return success, err, leaked, #padding
]]

function testcase.new_client_alpn_oom_releases_references()
    local failures = 0
    local successes = 0
    for _, headroom in ipairs(HEADROOMS) do
        do
            local L = assert(newstate.new())
            local ok, success, err, leaked =
                L:dostring(SCRIPT, false, false, CERT, KEY, headroom)
            assert.is_true(ok)
            assert.equal(leaked, 0)
            if success then
                successes = successes + 1
            else
                assert.equal(err, 'not enough memory')
                failures = failures + 1
            end
        end
        collectgarbage('collect')
    end
    assert.greater(failures, 0)
    assert.greater(successes, 0)
end

function testcase.new_client_cached_alpn_oom_releases_references()
    local failures = 0
    local successes = 0
    for _, headroom in ipairs(HEADROOMS) do
        do
            local L = assert(newstate.new())
            local ok, success, err, leaked =
                L:dostring(SCRIPT, false, true, CERT, KEY, headroom)
            assert.is_true(ok)
            assert.equal(leaked, 0)
            if success then
                successes = successes + 1
            else
                assert.equal(err, 'not enough memory')
                failures = failures + 1
            end
        end
        collectgarbage('collect')
    end
    assert.greater(failures, 0)
    assert.greater(successes, 0)
end

function testcase.new_server_alpn_oom_releases_references()
    local failures = 0
    local successes = 0
    for _, headroom in ipairs(HEADROOMS) do
        do
            local L = assert(newstate.new())
            local ok, success, err, leaked =
                L:dostring(SCRIPT, true, false, CERT, KEY, headroom)
            assert.is_true(ok)
            assert.equal(leaked, 0)
            if success then
                successes = successes + 1
            else
                assert.equal(err, 'not enough memory')
                failures = failures + 1
            end
        end
        collectgarbage('collect')
    end
    assert.greater(failures, 0)
    assert.greater(successes, 0)
end

function testcase.new_server_cached_alpn_oom_releases_references()
    local failures = 0
    local successes = 0
    for _, headroom in ipairs(HEADROOMS) do
        do
            local L = assert(newstate.new())
            local ok, success, err, leaked =
                L:dostring(SCRIPT, true, true, CERT, KEY, headroom)
            assert.is_true(ok)
            assert.equal(leaked, 0)
            if success then
                successes = successes + 1
            else
                assert.equal(err, 'not enough memory')
                failures = failures + 1
            end
        end
        collectgarbage('collect')
    end
    assert.greater(failures, 0)
    assert.greater(successes, 0)
end
