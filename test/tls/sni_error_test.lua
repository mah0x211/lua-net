local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local context = require('net.tls.context')
local client = require('net.tls.client')
local server = require('net.tls.server')
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

local function exchange(protocol, callback)
    local pair = assert(socket.pair({
        socktype = 'stream',
    }))
    local cctx = assert(context.connect(assert(client({
        protocol = protocol,
    })), pair[1]:fd(), {
        servername = 'www.example.com',
        verify_cert = false,
        verify_name = false,
    }))
    local sctx = assert(context.accept(assert(server({
        cert = CERT,
        key = KEY,
        protocol = protocol,
        sni_callback = callback,
    })), pair[2]:fd()))
    local cbio = cctx:get_bio()
    local sbio = sctx:get_bio()
    local client_done = false
    local server_done = false
    local failure

    local function pump(bio)
        local _, err = bio:drain()
        assert.is_nil(err)
        _, err = bio:fill()
        assert.is_nil(err)
    end

    local ok, err = pcall(function()
        for _ = 1, 64 do
            if not client_done then
                local done, err = cctx:handshake()
                assert.is_nil(err)
                client_done = done
            end
            pump(cbio)
            pump(sbio)
            if not server_done then
                local result, err, want = sctx:handshake()
                server_done = result == true
                if err then
                    failure = err
                    break
                end
                assert(server_done or want == context.WANT_READ or want ==
                           context.WANT_WRITE)
            end
            pump(sbio)
            pump(cbio)
            if server_done and client_done then
                break
            end
        end
        assert(failure or (server_done and client_done),
               'handshake did not complete')
    end)
    assert(cctx:close())
    assert(sctx:close())
    assert(pair[1]:close())
    assert(pair[2]:close())
    assert(ok, err)
    return failure
end

function testcase.sni_error_reaches_handshake()
    for _, protocol in ipairs({
        'tlsv1.2',
        'tlsv1.3',
    }) do
        local calls = 0
        local err = exchange(protocol, function(name)
            calls = calls + 1
            assert.equal(name, 'www.example.com')
            error('SNI queue diagnostic', 0)
        end)
        assert(err)
        assert.equal(calls, 1)
        assert.match(tostring(err), 'src/tls_server%.c:%d+: client_hello_cb:', false)
        assert.match(tostring(err), 'SNI queue diagnostic', true)

        err = exchange(protocol, function()
            error({})
        end)
        assert(err)
        assert.match(tostring(err), 'client_hello_cb: table: 0x%x+', false)
    end
end

function testcase.sni_error_uses_tostring_metamethod()
    for _, protocol in ipairs({
        'tlsv1.2',
        'tlsv1.3',
    }) do
        local calls = 0
        local err = exchange(protocol, function()
            error(setmetatable({}, {
                __tostring = function()
                    calls = calls + 1
                    return 'custom SNI diagnostic'
                end,
            }))
        end)
        assert.equal(calls, 1)
        assert.match(tostring(err), 'client_hello_cb: custom SNI diagnostic', true)
    end
end

function testcase.sni_error_tostring_failure_aborts_handshake()
    for _, protocol in ipairs({
        'tlsv1.2',
        'tlsv1.3',
    }) do
        for _, case in ipairs({
            {
                metamethod = function()
                    error('tostring failed')
                end,
                message = 'tostring failed',
            },
            {
                metamethod = function()
                    return {}
                end,
                message = '"__tostring" metamethod must return a string',
            },
            {
                metamethod = function()
                    error({})
                end,
                message = '(failed to stringify error)',
            },
        }) do
            local err = exchange(protocol, function()
                error(setmetatable({}, {
                    __tostring = case.metamethod,
                }))
            end)
            assert(err)
            assert.match(tostring(err), 'src/tls_server%.c:%d+: client_hello_cb:',
                         false)
            assert.match(tostring(err), case.message, true)
        end
    end
end

function testcase.sni_error_stringifies_scalar_values()
    for _, protocol in ipairs({
        'tlsv1.2',
        'tlsv1.3',
    }) do
        for _, case in ipairs({
            { '42', 42 },
            { 'false', false },
            { 'nil', nil },
        }) do
            local err = exchange(protocol, function()
                error(case[2], 0)
            end)
            assert(err)
            assert.match(tostring(err), 'client_hello_cb: ' .. case[1], true)
        end
    end
end

function testcase.sni_errors_do_not_leak_into_next_connection()
    local err = exchange('tlsv1.3', function()
        error('previous SNI diagnostic', 0)
    end)
    assert(err)
    err = exchange('tlsv1.3', function()
        error('current SNI diagnostic', 0)
    end)
    assert(err)
    assert.match(tostring(err), 'current SNI diagnostic', true)
    assert.not_match(tostring(err), 'previous SNI diagnostic', true)
end
