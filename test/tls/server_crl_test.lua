local testcase = require('testcase')
local assert = require('assert')
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local socket = require('net.socket')
local client = require('net.tls.client')
local server = require('net.tls.server')
local context = require('net.tls.context')
local new_cache = require('net.tls.cache')
local fixtures = require('test.tls.cert_fixtures')
local helpers = require('test.tls.context_helpers')

local DIR
local CRLS

local function readfile(path)
    local file = assert(io.open(path))
    local value = assert(file:read('*a'))
    file:close()
    return value
end

function testcase.before_all()
    DIR = os.tmpname()
    os.remove(DIR)
    assert(mkdir(DIR, '0700'))
    CRLS = fixtures.crl_certificates(DIR)
    assert(mkdir(DIR .. '/other', '0700'))
    fixtures.crl_certificates(DIR .. '/other', 'OtherCRLTestCA')
    local file = assert(io.open(DIR .. '/trusted-ca.pem', 'w'))
    file:write(readfile(DIR .. '/ca.crt'), readfile(DIR .. '/other/ca.crt'))
    file:close()
end

function testcase.after_all()
    if DIR then
        assert(rmdir(DIR, true))
    end
end

local function config(crls)
    return {
        cert = DIR .. '/server.crt',
        key = DIR .. '/server.key',
        cafile = DIR .. '/ca.crt',
        verify_mode = 'require',
        crls = crls,
    }
end

function testcase.server_rejects_invalid_crls_before_handshake()
    local cache = new_cache({
        ctx_capacity = 4,
    })
    for _, value in ipairs({
        '',
        'not a PEM document',
        readfile(DIR .. '/ca.crt'),
        '-----BEGIN X509 CRL-----\nAAAA\n-----END X509 CRL-----\n',
    }) do
        local opts = config(value)
        opts.cache = cache
        local ctx, err = server(opts)
        assert.is_nil(ctx)
        assert.not_nil(err)
        assert.equal(cache:size(), 0)
    end
    for _, value in ipairs({
        true,
        1,
        {},
        function()
        end,
    }) do
        assert.match(assert.throws(function()
            server(config(value))
        end), 'opts.crls must be string', true)
    end
    assert(server(config(CRLS.empty_crl)))
    assert(server(config(readfile(DIR .. '/ca.crt') .. CRLS.empty_crl ..
                             CRLS.empty_crl)))
end

local function exchange(opts, client_opts)
    client_opts = client_opts or {
        cert = DIR .. '/server.crt',
        key = DIR .. '/server.key',
    }
    client_opts.cafile = DIR .. '/ca.crt'
    local pair = assert(socket.pair({
        socktype = 'stream',
    }))
    local cctx
    local sctx
    local failure
    local verify_error
    local ok, err = pcall(function()
        cctx = assert(context.connect(assert(client(client_opts)), pair[1]:fd(),
                                      {
            servername = 'localhost',
        }))
        sctx = assert(context.accept(assert(server(opts)), pair[2]:fd()))
        local cep = helpers.new_ep(cctx, 'client', pair[1]:fd())
        local sep = helpers.new_ep(sctx, 'server', pair[2]:fd())
        local cd, sd
        for _ = 1, 64 do
            if not cd then
                local want
                cd, failure, want = cctx:handshake()
                if failure then
                    break
                end
                assert(cd or helpers.WANT[want])
            end
            helpers.pump(cep)
            helpers.pump(sep)
            if not sd then
                local want
                sd, failure, want = sctx:handshake()
                if failure then
                    break
                end
                assert(sd or helpers.WANT[want])
            end
            helpers.pump(sep)
            helpers.pump(cep)
            if cd and sd then
                break
            end
        end
        assert(failure or (cd and sd), 'handshake did not complete')
        local verified
        verified, verify_error = sctx:get_verify_result()
        if not failure then
            assert.is_true(verified)
        end
    end)
    if cctx then
        assert(cctx:close())
    end
    if sctx then
        assert(sctx:close())
    end
    assert(pair[1]:close())
    assert(pair[2]:close())
    assert(ok, err)
    return failure, verify_error
end

function testcase.server_crls_rejects_revoked_client_certificate()
    assert.is_nil(exchange(config(CRLS.empty_crl)))
    local err, verify_error = exchange(config(CRLS.revoked_crl))
    assert.not_nil(err)
    assert.match(verify_error, 'certificate revoked', true)
    assert.is_nil(exchange(config(nil)))
end

function testcase.server_crls_requires_the_client_issuer_crl()
    local opts = config(CRLS.empty_crl)
    opts.cafile = DIR .. '/trusted-ca.pem'
    local err, verify_error = exchange(opts, {
        cert = DIR .. '/other/server.crt',
        key = DIR .. '/other/server.key',
    })
    assert.not_nil(err)
    assert.match(verify_error, 'unable to get certificate CRL', true)
end

function testcase.server_crls_preserves_verification_modes()
    local opts = config(CRLS.revoked_crl)
    opts.verify_mode = nil
    assert.is_nil(exchange(opts))
    opts.verify_mode = 'request'
    assert.is_nil(exchange(opts, {}))
    opts.verify_mode = 'require'
    assert.not_nil(exchange(opts, {}))
end

function testcase.server_crls_cache_separates_crl_contents_and_absence()
    local cache = new_cache({
        ctx_capacity = 4,
    })
    for _, value in ipairs({
        CRLS.empty_crl,
        CRLS.revoked_crl,
        false,
        CRLS.empty_crl,
    }) do
        local opts = config(value or nil)
        opts.cache = cache
        local err = exchange(opts)
        if value == CRLS.revoked_crl then
            assert.not_nil(err)
        else
            assert.is_nil(err)
        end
    end
    assert.equal(cache:size(), 3)
    local opts = config('')
    opts.cache = cache
    local ctx, err = server(opts)
    assert.is_nil(ctx)
    assert.not_nil(err)
    assert.equal(cache:size(), 3)
end

function testcase.server_crls_uses_sni_target_policy()
    for _, case in ipairs({
        {
            false,
            CRLS.revoked_crl,
            true,
        },
        {
            CRLS.revoked_crl,
            CRLS.empty_crl,
            false,
        },
        {
            CRLS.revoked_crl,
            false,
            false,
        },
        {
            CRLS.empty_crl,
            CRLS.revoked_crl,
            true,
        },
    }) do
        local target = assert(server(config(case[2] or nil)))
        local opts = config(case[1] or nil)
        local called = 0
        opts.sni_callback = function(name)
            assert.equal(name, 'localhost')
            called = called + 1
            return target
        end
        local err = exchange(opts)
        assert.equal(called, 1)
        assert.equal(err ~= nil, case[3])
    end
end

function testcase.server_keeps_crls_alive_during_option_callbacks()
    local opts = config(CRLS.revoked_crl .. '\n')
    setmetatable(opts, {
        __index = function(_, field)
            assert(field == 'sni_callback' or field == 'alpn')
            opts.crls = nil
            collectgarbage('collect')
        end,
    })
    assert.not_nil(exchange(opts))
end
