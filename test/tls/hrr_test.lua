require('luacov')
local testcase = require('testcase')

-- With test/openssl.cnf, the first ffdhe2048 key share must trigger HRR.
if os.getenv('OPENSSL_CONF') then
    local assert = require('assert')
    local mkdir = require('mkdir')
    local rmdir = require('rmdir')
    local socket = require('net.socket')
    local tls_server = require('net.tls.server')
    local cert_fixtures = require('test.tls.cert_fixtures')
    local context_helpers = require('test.tls.context_helpers')

    local SERVER_CONFIG = {
        cert = os.tmpname(),
        key = os.tmpname(),
    }
    local CLIENT_CERT_FIXTURE_DIR = os.tmpname()
    local TICKET_TRACE = os.tmpname()
    local ticket_connection =
        context_helpers.new_ticket_connection(TICKET_TRACE)

    function testcase.before_all()
        cert_fixtures.server_certificate(SERVER_CONFIG.cert, SERVER_CONFIG.key)
        os.remove(CLIENT_CERT_FIXTURE_DIR)
        assert(mkdir(CLIENT_CERT_FIXTURE_DIR, '0700', true))
        cert_fixtures.client_certificate(CLIENT_CERT_FIXTURE_DIR)
    end

    function testcase.after_all()
        os.remove(SERVER_CONFIG.cert)
        os.remove(SERVER_CONFIG.key)
        os.remove(TICKET_TRACE)
        assert(rmdir(CLIENT_CERT_FIXTURE_DIR, true))
    end

    function testcase.new_server_sni_survives_hello_retry_request()
        local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
            reuseaddr = true,
        }))
        assert(lsock:listen())
        local target = assert(tls_server(SERVER_CONFIG))
        local root = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            sni_callback = function(name)
                assert.equal(name, 'www.example.com')
                return target
            end,
        }))
        local reused, _, trace = ticket_connection(lsock, root, '-tls1_3', nil,
                                                   false, {
            servername = 'www.example.com',
            groups = 'ffdhe2048:P-256',
        })
        assert.is_false(reused)
        -- RFC 8446's fixed ServerHello.random identifies HelloRetryRequest.
        assert.is_true(trace:gsub('%s+', ''):find(
                           'cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c',
                           1, true) ~= nil)

        -- Keep the initial selection and its verification policy even if the
        -- selected server also registers an SNI callback.
        target = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            verify_mode = 'require',
            cafile = CLIENT_CERT_FIXTURE_DIR .. '/ca.crt',
            sni_callback = function()
                error(
                    'the selected server callback must not reselect the server')
            end,
        }))
        local calls = 0
        root = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            sni_callback = function()
                calls = calls + 1
                if calls == 1 then
                    return target
                end
            end,
        }))
        reused, _, trace = ticket_connection(lsock, root, '-tls1_3', nil, false,
                                             {
            servername = 'www.example.com',
            groups = 'ffdhe2048:P-256',
            cert = CLIENT_CERT_FIXTURE_DIR .. '/client.crt',
            key = CLIENT_CERT_FIXTURE_DIR .. '/client.key',
        })
        assert.is_false(reused)
        assert.is_true(trace:gsub('%s+', ''):find(
                           'cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c',
                           1, true) ~= nil)
        assert.equal(calls, 1)

        calls = 0
        local err = assert.throws(ticket_connection, lsock, root, '-tls1_3',
                                  nil, false, {
            servername = 'www.example.com',
            groups = 'ffdhe2048:P-256',
        })
        assert.match(err, 'certificate')
        assert.equal(calls, 1)
        lsock:close()
    end

    function testcase.new_server_sni_default_selected_once_on_hello_retry_request()
        local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
            reuseaddr = true,
        }))
        assert(lsock:listen())
        local calls = 0
        local root = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            sni_callback = function(name)
                assert.equal(name, 'unknown.example.com')
                calls = calls + 1
            end,
        }))
        local reused, _, trace = ticket_connection(lsock, root, '-tls1_3', nil,
                                                   false, {
            servername = 'unknown.example.com',
            groups = 'ffdhe2048:P-256',
        })
        assert.is_false(reused)
        assert.is_true(trace:gsub('%s+', ''):find(
                           'cf21ad74e59a6111be1d8c021e65b891c2a211167abb8c5e079e09e2c8a8339c',
                           1, true) ~= nil)
        assert.equal(calls, 1)
        lsock:close()
    end

else
    print('OPENSSL_CONF environment variable not defined')
    print('skip: new_server_sni_survives_hello_retry_request')
    print('skip: new_server_sni_default_selected_once_on_hello_retry_request')
end
