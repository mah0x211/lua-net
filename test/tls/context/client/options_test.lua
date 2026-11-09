local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local assert = require('assert')
local tls_client = require('net.tls.client')
local new_tls_client = support.new_tls_client
local get_server_config = support.get_server_config
local get_crl_fixture_pem = support.get_crl_fixture_pem

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.new_client_option_matrix()
    -- Exercise constructor branches skipped by plain new_tls_client():
    -- non-default protocol and ALPN configuration.
    local ctx = assert(new_tls_client('tlsv1.2', 'default', {
        'h2',
        'http/1.1',
    }))
    assert.match(tostring(ctx), '^net.tls.client: ', false)
end

function testcase.new_client_accepts_complete_option_table()
    local client = assert(tls_client({
        protocol = 'tlsv1.2',
        cipher = 'default',
        alpn = {
            'h2',
            'http/1.1',
        },
        verify_depth = 2,
        cafile = get_server_config().cert,
        capath = '.',
        crls = get_crl_fixture_pem(),
    }))
    assert.match(tostring(client), '^net.tls.client: ', false)
end

function testcase.new_client_rejects_wrong_option_types()
    for _, case in ipairs({
        {
            'protocol',
            true,
            'string',
        },
        {
            'cipher',
            true,
            'string',
        },
        {
            'alpn',
            true,
            'table',
        },
        {
            'verify_depth',
            true,
            'integer',
        },
        {
            'cafile',
            true,
            'string',
        },
        {
            'capath',
            true,
            'string',
        },
        {
            'crls',
            true,
            'string',
        },
    }) do
        local field, value, expected = case[1], case[2], case[3]
        local err = assert.throws(function()
            tls_client({
                [field] = value,
            })
        end)
        assert.match(err, 'opts.' .. field .. ' must be ' .. expected)
    end
end

function testcase.new_client_requires_option_table()
    local err = assert.throws(function()
        tls_client()
    end)
    assert.match(err, 'table expected')

    err = assert.throws(function()
        tls_client({
            [1] = 'invalid key',
        })
    end)
    assert.match(err, 'opts keys must be strings')

    assert(tls_client({
        unknown_option = true,
    }))
end

function testcase.new_client_invalid_protocol()
    -- luaL_checkoption rejects unknown protocol/cipher option strings; the
    -- resulting error surfaces from new_tls_client itself.
    local err = assert.throws(function()
        new_tls_client('not-a-protocol')
    end)
    assert.match(err, 'not recognized', false)

    err = assert.throws(function()
        new_tls_client('default', 'not-a-cipher')
    end)
    assert.match(err, 'not recognized', false)
end
