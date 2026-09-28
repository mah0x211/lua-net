require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local exec = require('exec').execvp
local cache = require('net.tls.cache')
local client = require('net.tls.client')
local server = require('net.tls.server')

local CERT = os.tmpname()
local KEY = os.tmpname()

function testcase.before_all()
    os.remove(CERT)
    os.remove(KEY)
    local proc = assert(exec('openssl', {
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-x509',
        '-days',
        '1',
        '-keyout',
        KEY,
        '-out',
        CERT,
        '-subj',
        '/CN=localhost',
    }))
    for _ in proc.stderr:lines() do
    end
    assert.equal(assert(proc:close()).exit, 0)
end

function testcase.after_all()
    os.remove(CERT)
    os.remove(KEY)
end

function testcase.new()
    assert.is_function(cache)
    assert.is_function(client)
    assert.is_function(server)

    local c = cache({
        ctx_capacity = 2,
        session_capacity = 3,
    })

    assert.match(tostring(c), '^net.tls.cache: ', false)
    assert.is_function(c.clear)
    assert.is_function(c.size)
    assert.is_nil(c.get)
    assert.is_nil(c.put)

    local nctx, nsessions = c:size()
    assert.equal(nctx, 0)
    assert.equal(nsessions, 0)
    assert.is_true(c:clear())
end

function testcase.client_and_server_load_cache_without_cache_option()
    local loaded = package.loaded
    local previous_cache = loaded['net.tls.cache']
    local previous_client = loaded['net.tls.client']
    local previous_server = loaded['net.tls.server']

    local ok, err = pcall(function()
        loaded['net.tls.cache'] = nil
        loaded['net.tls.client'] = nil
        local new_client = require('net.tls.client')
        assert.is_function(loaded['net.tls.cache'])
        assert(new_client({}))

        loaded['net.tls.cache'] = nil
        loaded['net.tls.server'] = nil
        local new_server = require('net.tls.server')
        assert.is_function(loaded['net.tls.cache'])
        assert(new_server({cert = CERT, key = KEY}))
    end)

    loaded['net.tls.cache'] = previous_cache
    loaded['net.tls.client'] = previous_client
    loaded['net.tls.server'] = previous_server
    if not ok then
        error(err)
    end
end

function testcase.new_defaults_and_zero_capacities()
    local c = cache()
    local nctx, nsessions = c:size()
    assert.equal(nctx, 0)
    assert.equal(nsessions, 0)

    c = cache({
        ctx_capacity = 0,
        session_capacity = 0,
        unknown = 'ignored',
    })
    nctx, nsessions = c:size()
    assert.equal(nctx, 0)
    assert.equal(nsessions, 0)
end

function testcase.new_rejects_invalid_options()
    for _, opts in ipairs({
        false,
        {
            ctx_capacity = -1,
        },
        {
            ctx_capacity = 1.5,
        },
        {
            ctx_capacity = '1',
        },
        {
            session_capacity = -1,
        },
        {
            session_capacity = 1.5,
        },
        {
            session_capacity = '1',
        },
    }) do
        assert.throws(function()
            cache(opts)
        end)
    end
end

function testcase.gc()
    local weak = setmetatable({}, {
        __mode = 'v',
    })

    weak[1] = cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    collectgarbage('collect')
    collectgarbage('collect')
    assert.is_nil(weak[1])
end

function testcase.client_context_cache_sharing_and_isolation()
    local c = cache({
        ctx_capacity = 4,
        session_capacity = 2,
    })
    local client1 = assert(client({
        cache = c,
    }))
    local client2 = assert(client({
        cache = c,
    }))

    assert.equal(c:size(), 1)
    assert.not_equal(client1, client2)

    local client3 = assert(client({
        cache = c,
        protocol = 'tlsv1.2',
    }))
    assert.equal(c:size(), 2)

    local other = cache({
        ctx_capacity = 4,
    })
    assert(client({
        cache = other,
    }))
    assert.equal(other:size(), 1)

    assert.is_nil(client1.set_verify_depth)
    assert.is_nil(client1.load_verify_locations)
    assert.is_nil(client1.set_crls)
    assert.match(tostring(client3), '^net.tls.client: ', false)
end

function testcase.client_context_cache_distinguishes_absent_and_empty_crls()
    local c = cache({
        ctx_capacity = 2,
    })

    assert(client({
        cache = c,
    }))
    assert(client({
        cache = c,
        crls = '',
    }))
    assert.equal(c:size(), 2)
end

function testcase.client_context_cache_separates_session_settings()
    local c = cache({ctx_capacity = 4})

    assert(client({cache = c}))
    assert(client({cache = c, session_cache_timeout = 60}))
    assert(client({
        cache = c,
        session_cache_timeout = 60,
        session_cache_size = 64,
    }))
    assert.equal(c:size(), 3)
end

function testcase.client_context_cache_clear_and_zero_capacity()
    local c = cache({
        ctx_capacity = 1,
    })
    local client1 = assert(client({
        cache = c,
    }))
    assert.equal(c:size(), 1)
    assert.is_true(c:clear())
    assert.equal(c:size(), 0)

    -- client1 keeps its CTX alive independently from the cleared cache.
    collectgarbage('collect')
    assert.match(tostring(client1), '^net.tls.client: ', false)
    assert(client({
        cache = c,
    }))
    assert.equal(c:size(), 1)

    local disabled = cache({
        ctx_capacity = 0,
    })
    assert(client({
        cache = disabled,
    }))
    assert.equal(disabled:size(), 0)
end

function testcase.client_context_cache_capacity_is_bounded()
    local c = cache({
        ctx_capacity = 1,
    })
    local clients = {}

    for i, protocol in ipairs({
        'default',
        'tlsv1.2',
        'tlsv1.3',
    }) do
        clients[i] = assert(client({
            cache = c,
            protocol = protocol,
        }))
        assert.equal(c:size(), 1)
    end

    -- Evicted CTX userdata remain valid while their clients own them.
    collectgarbage('collect')
    for _, item in ipairs(clients) do
        assert.match(tostring(item), '^net.tls.client: ', false)
    end
end

function testcase.client_context_failure_is_not_cached()
    local c = cache({
        ctx_capacity = 2,
    })
    local ctx, err = client({
        cache = c,
        cafile = '__net_no_such_ca__.crt',
    })

    assert.is_nil(ctx)
    assert.not_nil(err)
    assert.equal(c:size(), 0)
end

function testcase.server_context_cache_sharing_and_callback_isolation()
    local c = cache({
        ctx_capacity = 8,
    })
    local function select_vhost()
        return nil
    end
    local opts = {
        cert = CERT,
        key = KEY,
        cache = c,
        sni_callback = select_vhost,
    }
    local server1 = assert(server(opts))
    local server2 = assert(server(opts))

    assert.equal(c:size(), 1)
    assert.not_equal(server1, server2)
    assert.is_nil(server1.set_verify)
    assert.is_nil(server1.set_sni_callback)

    assert(server({
        cert = CERT,
        key = KEY,
        cache = c,
        sni_callback = function()
            return nil
        end,
    }))
    assert.equal(c:size(), 2)

    -- A client key can never alias a server key in the same cache.
    assert(client({
        cache = c,
    }))
    assert.equal(c:size(), 3)
end

function testcase.server_context_failure_is_not_cached()
    local c = cache({
        ctx_capacity = 2,
    })
    local ctx, err = server({
        cert = CERT,
        key = '__net_no_such_key__.pem',
        cache = c,
    })

    assert.is_nil(ctx)
    assert.not_nil(err)
    assert.equal(c:size(), 0)

    assert.throws(function()
        server({
            cert = CERT,
            key = KEY,
            cache = c,
            sni_callback = true,
        })
    end)
    assert.equal(c:size(), 0)
end

function testcase.server_context_cache_separates_session_settings()
    local c = cache({ctx_capacity = 4})

    assert(server({cert = CERT, key = KEY, cache = c}))
    assert(server({
        cert = CERT,
        key = KEY,
        cache = c,
        session_timeout = 60,
    }))
    assert(server({
        cert = CERT,
        key = KEY,
        cache = c,
        session_timeout = 60,
        session_cache_size = 64,
    }))
    assert.equal(c:size(), 3)
end
