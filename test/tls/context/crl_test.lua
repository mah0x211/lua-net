local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local assert = require('assert')
local tls_cache = require('net.tls.cache')
local tls_client = require('net.tls.client')
local get_server_config = support.get_server_config
local get_crl_fixture_pem = support.get_crl_fixture_pem

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.new_client_with_crls()
    -- valid PEM CRL is accepted (regression against luaL_checkstring's
    -- zero-length bug) and non-string arguments raise a Lua error.
    assert(get_crl_fixture_pem() and #get_crl_fixture_pem() > 0,
           'CRL fixture must contain PEM data')
    local client = assert(tls_client({
        crls = get_crl_fixture_pem(),
    }))
    assert.match(tostring(client), '^net.tls.client: ', false)

    -- Non-string arguments raise a Lua type error.
    for _, bad in ipairs({
        {},
        true,
    }) do
        local terr = assert.throws(function()
            tls_client({
                crls = bad,
            })
        end)
        assert.match(terr, 'must be string', false)
    end
    local nerr = assert.throws(function()
        tls_client({
            crls = function()
            end,
        })
    end)
    assert.match(nerr, 'must be string', false)
end

function testcase.new_client_rejects_invalid_crl_pem()
    -- The PEM envelope identifies a CRL, but its payload is not valid ASN.1.
    local client, err = tls_client({
        crls = '-----BEGIN X509 CRL-----\nAAAA\n-----END X509 CRL-----\n',
    })
    assert.is_nil(client)
    assert.not_nil(err)
    assert.match(err, 'PEM_X509_INFO_read_bio', true)
end

function testcase.new_client_rejects_crls_without_crl()
    local pem = assert(io.open(get_server_config().cert, 'r'))
    local body = pem:read('*a')
    pem:close()

    local cache = tls_cache({
        ctx_capacity = 4,
    })
    for _, value in ipairs({
        '',
        'not a PEM document',
        body,
    }) do
        -- Retry each input to ensure a failed context is never cached.
        for _ = 1, 2 do
            local client, err = tls_client({
                crls = value,
                cache = cache,
            })
            assert.is_nil(client)
            assert.not_nil(err)
            assert.match(tostring(err), 'no CRL loaded', true)
            assert.equal(cache:size(), 0)
        end
    end
    assert(tls_client({
        cache = cache,
    }))
    assert.equal(cache:size(), 1)
end

function testcase.new_client_crls_accepts_mixed_pem()
    local file = assert(io.open(get_server_config().cert, 'r'))
    local cert = file:read('*a')
    file:close()
    -- The fixture is a signed CRL with no revoked certificate entries.
    local crl = get_crl_fixture_pem()
    assert(tls_client({
        crls = cert .. crl .. crl,
    }))
end
