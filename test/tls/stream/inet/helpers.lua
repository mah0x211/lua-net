local rlimit = require('testcase.rlimit')
local assert = require('assert')
local cert_fixtures = require('test.tls.cert_fixtures')
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')

-- Resource state is owned by one test file.
local function new()
    local function new_tls_server(cert, key, protocol, cipher, alpn,
                                  session_timeout, prefer_client_ciphers)
        return tls_server({
            cert = cert,
            key = key,
            protocol = protocol,
            cipher = cipher,
            alpn = alpn,
            session_timeout = session_timeout,
            prefer_client_ciphers = prefer_client_ciphers,
        })
    end
    local function new_tls_client(protocol, cipher, alpn)
        return tls_client({
            protocol = protocol,
            cipher = cipher,
            alpn = alpn,
        })
    end

    local SERVER_CONFIG
    local CERT_DIR
    local CLIENT_CONFIG
    local TESTFILE

    local RLIMIT_NOFILE

    local function revert_rlimit_nofile()
        if RLIMIT_NOFILE then
            assert(rlimit('nofile', RLIMIT_NOFILE.cur, RLIMIT_NOFILE.max))
            RLIMIT_NOFILE = nil
        end
    end

    local function stash_rlimit_nofile()
        revert_rlimit_nofile()
        RLIMIT_NOFILE = assert(rlimit('nofile'))
    end

    local TMPPATHS = {}

    --- Tracked tmpname(): the path is removed by after_each even when a
    --- test fails midway, so no unix socket or temp file is left behind.
    --- @return string path
    local function tmpname()
        local path = os.tmpname()
        TMPPATHS[#TMPPATHS + 1] = path
        return path
    end

    local function get_server_config()
        if not SERVER_CONFIG then
            if not CERT_DIR then
                CERT_DIR = os.tmpname()
                os.remove(CERT_DIR)
                assert(mkdir(CERT_DIR, '0700', true))
            end
            local config = {
                cert = CERT_DIR .. '/cert.pem',
                key = CERT_DIR .. '/cert.key',
            }
            cert_fixtures.server_certificate(config.cert, config.key)
            SERVER_CONFIG = config
        end
        return SERVER_CONFIG
    end

    local function before_all()
        TESTFILE = tmpname()
        os.remove(TESTFILE)

        CLIENT_CONFIG = {
            verify_name = false,
            verify_time = false,
            verify_cert = false,
        }
        return TESTFILE, CLIENT_CONFIG
    end

    local function after_all()
        os.remove(TESTFILE)
        if CERT_DIR then
            assert(rmdir(CERT_DIR, true))
            CERT_DIR = nil
            SERVER_CONFIG = nil
        end
        revert_rlimit_nofile()
    end

    local function after_each()
        for i = #TMPPATHS, 1, -1 do
            os.remove(TMPPATHS[i])
            TMPPATHS[i] = nil
        end

        revert_rlimit_nofile()
    end

    return {
        new_tls_server = new_tls_server,
        new_tls_client = new_tls_client,
        tmpname = tmpname,
        get_server_config = get_server_config,
        stash_rlimit_nofile = stash_rlimit_nofile,
        revert_rlimit_nofile = revert_rlimit_nofile,
        before_all = before_all,
        after_all = after_all,
        after_each = after_each,
    }
end

return { new = new }
