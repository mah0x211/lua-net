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
local helpers = require('test.tls.context.helpers')

local DIR
local A
local B

local function readfile(path)
    local file = assert(io.open(path))
    local value = assert(file:read('*a'))
    file:close()
    return value
end

function testcase.before_all()
    DIR = os.tmpname()
    os.remove(DIR)
    A, B = DIR .. '/a', DIR .. '/b'
    assert(mkdir(A, '0700', true))
    assert(mkdir(B, '0700', true))
    fixtures.client_certificate_chain(A)
    fixtures.client_certificate(B)
    fixtures.server_certificate(DIR .. '/server.crt', DIR .. '/server.key')
    local file = assert(io.open(DIR .. '/trusted-ca.pem', 'w'))
    file:write(readfile(A .. '/ca.crt'), readfile(B .. '/ca.crt'))
    file:close()
end

function testcase.after_all()
    if DIR then
        assert(rmdir(DIR, true))
    end
end

function testcase.client_certificate_options()
    for _, field in ipairs({
        'cert',
        'key',
    }) do
        for _, value in ipairs({
            true,
            1,
            {},
            function()
            end,
        }) do
            local opts = {
                cert = A .. '/client-chain.pem',
                key = A .. '/client.key',
            }
            opts[field] = value
            assert.match(assert.throws(function()
                client(opts)
            end), 'opts.' .. field .. ' must be string', true)
        end
        local opts = {
            cert = A .. '/client-chain.pem',
            key = A .. '/client.key',
        }
        opts[field] = opts[field] .. '\0ignored'
        assert.match(assert.throws(function()
            client(opts)
        end), 'opts.' .. field .. ' must not contain NUL', true)
        opts[field] = nil
        assert.match(assert.throws(function()
            client(opts)
        end), 'must be specified together', true)
    end
end

function testcase.client_certificate_load_errors_do_not_enter_cache()
    local cache = new_cache({
        ctx_capacity = 4,
    })
    for _, pair in ipairs({
        {
            DIR .. '/missing.crt',
            A .. '/client.key',
        },
        {
            A .. '/client-chain.pem',
            DIR .. '/missing.key',
        },
        {
            A .. '/client-chain.pem',
            B .. '/client.key',
        },
    }) do
        local ctx, err = client({
            cert = pair[1],
            key = pair[2],
            cache = cache,
        })
        assert.is_nil(ctx)
        assert.not_nil(err)
        assert.equal(cache:size(), 0)
    end
    assert(client({
        cert = A .. '/client-chain.pem',
        key = A .. '/client.key',
        cache = cache,
    }))
    assert.equal(cache:size(), 1)
end

local function verified_client(opts)
    opts.cafile = DIR .. '/server.crt'
    return assert(client(opts))
end

local function exchange(c, s)
    local pair = assert(socket.pair({
        socktype = 'stream',
    }))
    local cctx
    local sctx
    local failure
    local peer
    local ok, err = pcall(function()
        cctx = assert(context.connect(c, pair[1]:fd(), {
            host = 'localhost',
            port = '443',
            servername = 'www.example.com',
        }))
        sctx = assert(context.accept(s, pair[2]:fd()))
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
                -- Process TLS 1.3 NewSessionTicket messages for the client cache.
                local _, rerr, want = cctx:read()
                assert.is_nil(rerr)
                assert.equal(want, context.WANT_READ)
                peer = sctx:get_peer_cert()
                assert.is_true(sctx:get_verify_result())
                break
            end
        end
        assert(failure or (cd and sd), 'handshake did not complete')
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
    return failure, peer
end

local function new_server(protocol, cafile, mode)
    return assert(server({
        cert = DIR .. '/server.crt',
        key = DIR .. '/server.key',
        protocol = protocol,
        cafile = cafile,
        verify_mode = mode or 'require',
    }))
end

function testcase.client_sends_certificate_chain()
    local c = verified_client({
        cert = A .. '/client-chain.pem',
        key = A .. '/client.key',
    })
    local err, peer = exchange(c, new_server(nil, A .. '/ca.crt'))
    assert.is_nil(err)
    assert.equal(peer, readfile(A .. '/client.crt'))
    -- Without the intermediate, the root alone cannot verify the leaf.
    c = verified_client({
        cert = A .. '/client.crt',
        key = A .. '/client.key',
    })
    assert.not_nil(exchange(c, new_server(nil, A .. '/ca.crt')))
end

function testcase.server_rejects_absent_or_untrusted_client_certificate()
    local s = new_server(nil, A .. '/ca.crt')
    assert.not_nil(exchange(verified_client({}), s))
    local c = verified_client({
        cert = B .. '/client.crt',
        key = B .. '/client.key',
    })
    assert.not_nil(exchange(c, s))
end

function testcase.client_certificate_cache_isolates_identities()
    for _, protocol in ipairs({
        'tlsv1.2',
        'tlsv1.3',
    }) do
        local cache = new_cache({
            ctx_capacity = 4,
            session_capacity = 2,
        })
        local s = new_server(protocol, DIR .. '/trusted-ca.pem', 'request')
        for _, dir in ipairs({
            A,
            A,
            B,
            B,
            false,
        }) do
            local opts = {
                protocol = protocol,
                cache = cache,
            }
            if dir then
                opts.cert = dir ..
                                (dir == A and '/client-chain.pem' or
                                    '/client.crt')
                opts.key = dir .. '/client.key'
            end
            local err, peer = exchange(verified_client(opts), s)
            assert.is_nil(err)
            if dir then
                assert.equal(peer, readfile(dir .. '/client.crt'))
            else
                assert.is_nil(peer)
            end
        end
        local nctx, nsessions = cache:size()
        assert.equal(nctx, 3)
        assert.greater(nsessions, 0)
    end
end

function testcase.client_certificate_cache_distinguishes_cert_and_key_paths()
    local cert = A .. '/client-chain.pem'
    local key = A .. '/client.key'
    for _, path in ipairs({
        cert,
        key,
    }) do
        local file = assert(io.open(path .. '.copy', 'w'))
        file:write(readfile(path))
        file:close()
    end
    local cache = new_cache({
        ctx_capacity = 4,
    })
    for _, pair in ipairs({
        {
            cert,
            key,
        },
        {
            cert .. '.copy',
            key,
        },
        {
            cert,
            key .. '.copy',
        },
        {
            cert,
            key,
        },
    }) do
        assert(client({
            cert = pair[1],
            key = pair[2],
            cache = cache,
        }))
    end
    assert.equal(cache:size(), 3)
end

function testcase.client_keeps_certificate_paths_alive_during_options_callback()
    local opts = {
        cert = A .. '/client-chain.pem',
        key = A .. '/client.key',
    }
    setmetatable(opts, {
        __index = function(_, field)
            assert.equal(field, 'alpn')
            opts.cert, opts.key = nil, nil
            collectgarbage('collect')
        end,
    })
    local c = verified_client(opts)
    local err, peer = exchange(c, new_server(nil, A .. '/ca.crt'))
    assert.is_nil(err)
    assert.equal(peer, readfile(A .. '/client.crt'))
end
