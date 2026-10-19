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

function testcase.server_gc_releases_alpn_reference()
    -- Isolate registry observations from other TLS tests.
    local L = assert(newstate.new())
    local ok, retained, released = L:dostring([[
        local cert, key = ...
        local new = require('net.tls.server')
        local registry = debug.getregistry()
        local protocol = 'gc-registry-protocol'
        local wire = string.char(#protocol) .. protocol
        local function count_refs()
            local count = 0
            for _, value in pairs(registry) do
                if value == wire then count = count + 1 end
            end
            return count
        end
        assert(count_refs() == 0)
        local server = assert(new({cert = cert, key = key, alpn = {protocol}}))
        assert(type(server) == 'userdata')
        local retained = count_refs()
        server = nil
        -- The server releases its CTX reference, then the CTX releases ALPN.
        collectgarbage('collect')
        collectgarbage('collect')
        return retained, count_refs()
    ]], CERT, KEY)
    assert(ok, retained)
    assert.equal(retained, 1)
    assert.equal(released, 0)
end

function testcase.cache_clear_releases_alpn_reference()
    local L = assert(newstate.new())
    local ok, retained, cached, released = L:dostring([[
        local cert, key = ...
        local new = require('net.tls.server')
        local cache = require('net.tls.cache')({ctx_capacity = 1})
        local registry = debug.getregistry()
        local protocol = 'gc-registry-protocol'
        local wire = string.char(#protocol) .. protocol
        local function count_refs()
            local count = 0
            for _, value in pairs(registry) do
                if value == wire then count = count + 1 end
            end
            return count
        end
        assert(count_refs() == 0)
        local server = assert(new({
            cert = cert, key = key, alpn = {protocol}, cache = cache,
        }))
        assert(type(server) == 'userdata')
        local retained = count_refs()
        server = nil
        collectgarbage('collect')
        collectgarbage('collect')
        local cached = count_refs()
        assert(cache:clear())
        collectgarbage('collect')
        collectgarbage('collect')
        return retained, cached, count_refs()
    ]], CERT, KEY)
    assert(ok, retained)
    assert.equal(retained, 1)
    assert.equal(cached, 1)
    assert.equal(released, 0)
end
