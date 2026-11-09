local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local assert = require('assert')
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')
local new_tls_server = support.new_tls_server
local get_server_config = support.get_server_config
local get_chain_fixture_dir = support.get_chain_fixture_dir

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.server_new_rejects_key_mismatch()
    -- net.tls.server must refuse a private key that does not match the
    -- certificate instead of failing later at handshake time.
    local server, err = new_tls_server(get_chain_fixture_dir() .. '/leaf.crt',
                                       get_server_config().key)
    assert.is_nil(server)
    assert(err, 'key/cert mismatch must return an error')
end

function testcase.new_server_accepts_complete_option_table()
    local server = assert(tls_server({
        cert = get_server_config().cert,
        key = get_server_config().key,
        protocol = 'tlsv1.2',
        cipher = 'default',
        alpn = {
            'h2',
            'http/1.1',
        },
        session_timeout = 60,
        prefer_client_ciphers = true,
        verify_mode = 'request',
        verify_depth = 2,
        cafile = get_server_config().cert,
        capath = '.',
        sni_callback = function()
        end,
    }))
    assert.match(tostring(server), '^net.tls.server: ', false)
end

function testcase.new_server_rejects_wrong_option_types()
    for _, case in ipairs({
        {
            'cert',
            true,
            'string',
        },
        {
            'key',
            true,
            'string',
        },
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
            'session_timeout',
            true,
            'integer',
        },
        {
            'prefer_client_ciphers',
            1,
            'boolean',
        },
        {
            'verify_mode',
            true,
            'string',
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
            'sni_callback',
            true,
            'function',
        },
    }) do
        local field, value, expected = case[1], case[2], case[3]
        local opts = {
            cert = get_server_config().cert,
            key = get_server_config().key,
        }
        opts[field] = value
        local err = assert.throws(function()
            tls_server(opts)
        end)
        assert.match(err, 'opts.' .. field .. ' must be ' .. expected)
    end
end

function testcase.new_server_requires_option_table_and_credentials()
    local config = get_server_config()
    local err = assert.throws(function()
        tls_server()
    end)
    assert.match(err, 'table expected')

    err = assert.throws(function()
        tls_server({})
    end)
    assert.match(err, 'opts.cert is required')

    err = assert.throws(function()
        tls_server({
            cert = config.cert,
        })
    end)
    assert.match(err, 'opts.key is required')

    err = assert.throws(function()
        tls_server({
            cert = config.cert,
            key = config.key,
            [1] = 'invalid key',
        })
    end)
    assert.match(err, 'opts keys must be strings')

    assert(tls_server({
        cert = config.cert,
        key = config.key,
        unknown_option = true,
    }))
end

function testcase.new_server_rejects_unknown_protocol_and_cipher()
    local config = get_server_config()
    for _, field in ipairs({
        'protocol',
        'cipher',
    }) do
        local err = assert.throws(function()
            tls_server({
                cert = config.cert,
                key = config.key,
                [field] = 'not-a-' .. field,
            })
        end)
        assert.match(err, 'opts.' .. field .. '=')
        assert.match(err, 'is not recognized')
    end
end

function testcase.new_rejects_nul_paths()
    local config = get_server_config()
    for _, field in ipairs({
        'cafile',
        'capath',
    }) do
        local err = assert.throws(function()
            tls_client({
                [field] = 'cert.pem\0ignored',
            })
        end)
        assert.match(err, 'must not contain NUL', false)
    end

    for _, field in ipairs({
        'cert',
        'key',
        'cafile',
        'capath',
    }) do
        local opts = {
            cert = config.cert,
            key = config.key,
        }
        opts[field] = 'cert.pem\0ignored'
        local err = assert.throws(function()
            tls_server(opts)
        end)
        assert.match(err, 'must not contain NUL', false)
    end

end
