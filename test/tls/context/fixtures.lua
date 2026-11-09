local assert = require('assert')
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local cert_fixtures = require('test.tls.cert_fixtures')

-- Each test file owns its lazily generated certificates and temporary paths.
local function new(exec)
    local FIXTURE_DIRS = {}
    local SERVER_CONFIG
    local CRL_FIXTURE_PEM
    local CHAIN_FIXTURE_DIR
    local CLIENT_CERT_FIXTURE_DIR
    local VERIFY_FIXTURE_DIR

    local function new_fixture_dir()
        local dir = os.tmpname()
        os.remove(dir)
        assert(mkdir(dir, '0700', true))
        FIXTURE_DIRS[#FIXTURE_DIRS + 1] = dir
        return dir
    end

    local function get_server_config()
        if not SERVER_CONFIG then
            local dir = new_fixture_dir()
            local config = {
                cert = dir .. '/cert.pem',
                key = dir .. '/cert.key',
            }
            cert_fixtures.server_certificate(config.cert, config.key)
            SERVER_CONFIG = config
        end
        return SERVER_CONFIG
    end

    local function get_crl_fixture_pem()
        if CRL_FIXTURE_PEM then
            return CRL_FIXTURE_PEM
        end

        -- CRL fixture: build a throwaway openssl CA + empty CRL in a temp dir.
        local dir = new_fixture_dir()

        local cnf_path = dir .. '/ca.cnf'
        local cnf = assert(io.open(cnf_path, 'w'))
        cnf:write(([[
[ ca ]
default_ca = CA_default
[ CA_default ]
database = %s/index.txt
serial = %s/serial
crlnumber = %s/crlnumber
certificate = %s/ca.crt
private_key = %s/ca.key
default_md = sha256
default_crl_days = 30
policy = policy_any
[ policy_any ]
commonName = supplied
]]):format(dir, dir, dir, dir, dir))
        cnf:close()

        assert(io.open(dir .. '/index.txt', 'w')):close()
        local serial = assert(io.open(dir .. '/serial', 'w'))
        serial:write('1000\n')
        serial:close()
        local crlnum = assert(io.open(dir .. '/crlnumber', 'w'))
        crlnum:write('1000\n')
        crlnum:close()

        local ca = assert(exec('openssl', {
            'req',
            '-x509',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-days',
            '1',
            '-keyout',
            dir .. '/ca.key',
            '-out',
            dir .. '/ca.crt',
            '-config',
            cnf_path,
            '-subj',
            '/CN=TestCRL',
        }))
        for _ in ca.stderr:lines() do
        end
        local ca_res = assert(ca:close())
        if ca_res.exit ~= 0 then
            error('failed to generate CA cert for CRL fixture')
        end

        local gencrl = assert(exec('openssl', {
            'ca',
            '-config',
            cnf_path,
            '-gencrl',
            '-out',
            dir .. '/ca.crl',
        }))
        for _ in gencrl.stderr:lines() do
        end
        local gencrl_res = assert(gencrl:close())
        if gencrl_res.exit ~= 0 then
            error('failed to generate CRL for CRL fixture')
        end

        local crl = assert(io.open(dir .. '/ca.crl', 'r'))
        local pem = crl:read('*a')
        crl:close()

        CRL_FIXTURE_PEM = pem
        return pem
    end

    local function get_chain_fixture_dir()
        if CHAIN_FIXTURE_DIR then
            return CHAIN_FIXTURE_DIR
        end

        -- Chain fixture: root CA -> intermediate CA -> leaf server cert, plus a
        -- fullchain PEM (leaf + intermediate). accept_s_client_fullchain serves
        -- the fullchain to a client that only trusts the root, so the server
        -- must actually send the intermediate for the handshake to verify.
        local dir = new_fixture_dir()

        -- self-signed root CA
        local root = assert(exec('openssl', {
            'req',
            '-x509',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-days',
            '1',
            '-keyout',
            dir .. '/root.key',
            '-out',
            dir .. '/root.crt',
            '-subj',
            '/CN=ChainTestRootCA',
        }))
        for _ in root.stderr:lines() do
        end
        assert.equal(assert(root:close()).exit, 0)

        -- intermediate CA signed by the root
        local int_ext = assert(io.open(dir .. '/int_ext.cnf', 'w'))
        int_ext:write('basicConstraints=critical,CA:TRUE,pathlen:0\n',
                      'keyUsage=critical,keyCertSign,cRLSign\n')
        int_ext:close()

        local icsr = assert(exec('openssl', {
            'req',
            '-new',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-keyout',
            dir .. '/int.key',
            '-out',
            dir .. '/int.csr',
            '-subj',
            '/CN=ChainTestIntermediateCA',
        }))
        for _ in icsr.stderr:lines() do
        end
        assert.equal(assert(icsr:close()).exit, 0)

        local icrt = assert(exec('openssl', {
            'x509',
            '-req',
            '-in',
            dir .. '/int.csr',
            '-CA',
            dir .. '/root.crt',
            '-CAkey',
            dir .. '/root.key',
            '-CAcreateserial',
            '-days',
            '1',
            '-extfile',
            dir .. '/int_ext.cnf',
            '-out',
            dir .. '/int.crt',
        }))
        for _ in icrt.stderr:lines() do
        end
        assert.equal(assert(icrt:close()).exit, 0)

        -- leaf server certificate signed by the intermediate
        local leaf_ext = assert(io.open(dir .. '/leaf_ext.cnf', 'w'))
        leaf_ext:write('basicConstraints=critical,CA:FALSE\n')
        leaf_ext:close()

        local lcsr = assert(exec('openssl', {
            'req',
            '-new',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-keyout',
            dir .. '/leaf.key',
            '-out',
            dir .. '/leaf.csr',
            '-subj',
            '/CN=www.example.com',
        }))
        for _ in lcsr.stderr:lines() do
        end
        assert.equal(assert(lcsr:close()).exit, 0)

        local lcrt = assert(exec('openssl', {
            'x509',
            '-req',
            '-in',
            dir .. '/leaf.csr',
            '-CA',
            dir .. '/int.crt',
            '-CAkey',
            dir .. '/int.key',
            '-CAcreateserial',
            '-days',
            '1',
            '-extfile',
            dir .. '/leaf_ext.cnf',
            '-out',
            dir .. '/leaf.crt',
        }))
        for _ in lcrt.stderr:lines() do
        end
        assert.equal(assert(lcrt:close()).exit, 0)

        -- fullchain = leaf + intermediate
        local leaf_fh = assert(io.open(dir .. '/leaf.crt', 'r'))
        local leaf_pem = leaf_fh:read('*a')
        leaf_fh:close()
        local int_fh = assert(io.open(dir .. '/int.crt', 'r'))
        local int_pem = int_fh:read('*a')
        int_fh:close()
        local fullchain = assert(io.open(dir .. '/fullchain.pem', 'w'))
        fullchain:write(leaf_pem, int_pem)
        fullchain:close()

        -- sanity: the chain must verify against the root CA alone
        local verify = assert(exec('openssl', {
            'verify',
            '-CAfile',
            dir .. '/root.crt',
            '-untrusted',
            dir .. '/int.crt',
            dir .. '/leaf.crt',
        }))
        for _ in verify.stderr:lines() do
        end
        assert.equal(assert(verify:close()).exit, 0)

        CHAIN_FIXTURE_DIR = dir
        return dir
    end

    local function get_client_cert_fixture_dir()
        if CLIENT_CERT_FIXTURE_DIR then
            return CLIENT_CERT_FIXTURE_DIR
        end

        -- Client-certificate fixture: an independent CA that signs a client
        -- certificate.  The server-side verify tests trust this CA and have
        -- openssl s_client present the leaf.
        local dir = new_fixture_dir()

        cert_fixtures.client_certificate(dir)

        CLIENT_CERT_FIXTURE_DIR = dir
        return dir
    end

    local function get_verify_fixture_dir()
        if VERIFY_FIXTURE_DIR then
            return VERIFY_FIXTURE_DIR
        end

        -- Client-verification fixture set: a trusted CA, a good server
        -- certificate chaining to it, and three certificates each breaking
        -- exactly one verification aspect (trust, hostname, validity period).
        local dir = new_fixture_dir()
        local function openssl_ok(args)
            local proc = assert(exec('openssl', args))
            for _ in proc.stderr:lines() do
            end
            local closed = assert(proc:close())
            if closed.exit ~= 0 then
                error('openssl ' .. args[1] ..
                          ' failed for the client-verification fixtures')
            end
        end
        local ca_crt = dir .. '/trusted-ca.crt'
        local ca_key = dir .. '/trusted-ca.key'
        local function sign(name, cn)
            openssl_ok({
                'req',
                '-new',
                '-newkey',
                'rsa:2048',
                '-nodes',
                '-keyout',
                dir .. '/' .. name .. '.key',
                '-out',
                dir .. '/' .. name .. '.csr',
                '-subj',
                '/C=US/CN=' .. cn,
            })
            openssl_ok({
                'x509',
                '-req',
                '-in',
                dir .. '/' .. name .. '.csr',
                '-CA',
                ca_crt,
                '-CAkey',
                ca_key,
                '-CAcreateserial',
                '-days',
                '36500',
                '-out',
                dir .. '/' .. name .. '.crt',
            })
        end

        -- the only CA the verifying client trusts
        openssl_ok({
            'req',
            '-x509',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-keyout',
            ca_key,
            '-out',
            ca_crt,
            '-days',
            '36500',
            '-subj',
            '/C=US/CN=lua-net Test Trusted CA',
        })
        -- good-server: valid chain, matching CN
        sign('good-server', 'www.example.com')
        -- untrusted-server: self-signed, unknown to the client trust store
        openssl_ok({
            'req',
            '-x509',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-keyout',
            dir .. '/untrusted-server.key',
            '-out',
            dir .. '/untrusted-server.crt',
            '-days',
            '36500',
            '-subj',
            '/C=US/CN=www.example.com',
        })
        -- wrongname-server: valid chain but a different CN
        sign('wrongname-server', 'other.example.net')
        -- expired-server: valid chain but notAfter in 2021.  req/x509 cannot
        -- emit past dates, so sign it with openssl ca and explicit dates
        -- (same machinery as the CRL fixture above)
        local vcnf_path = dir .. '/ca.cnf'
        local vcnf = assert(io.open(vcnf_path, 'w'))
        vcnf:write(([[
[ ca ]
default_ca = CA_default
[ CA_default ]
database = %s/index.txt
serial = %s/serial
new_certs_dir = %s
certificate = %s
private_key = %s
default_md = sha256
default_days = 30
policy = policy_any
[ policy_any ]
commonName = supplied
]]):format(dir, dir, dir, ca_crt, ca_key))
        vcnf:close()
        assert(io.open(dir .. '/index.txt', 'w')):close()
        local vserial = assert(io.open(dir .. '/serial', 'w'))
        vserial:write('1000\n')
        vserial:close()
        openssl_ok({
            'req',
            '-new',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-keyout',
            dir .. '/expired-server.key',
            '-out',
            dir .. '/expired-server.csr',
            '-subj',
            '/C=US/CN=www.example.com',
        })
        openssl_ok({
            'ca',
            '-config',
            vcnf_path,
            '-batch',
            '-notext',
            '-startdate',
            '20200101000000Z',
            '-enddate',
            '20210101000000Z',
            '-in',
            dir .. '/expired-server.csr',
            '-out',
            dir .. '/expired-server.crt',
        })
        os.remove(dir .. '/good-server.csr')
        os.remove(dir .. '/wrongname-server.csr')
        os.remove(dir .. '/expired-server.csr')
        os.remove(dir .. '/trusted-ca.srl')

        VERIFY_FIXTURE_DIR = dir
        return dir
    end

    local function close()
        for i = #FIXTURE_DIRS, 1, -1 do
            assert(rmdir(FIXTURE_DIRS[i], true))
            FIXTURE_DIRS[i] = nil
        end
        SERVER_CONFIG = nil
        CRL_FIXTURE_PEM = nil
        CHAIN_FIXTURE_DIR = nil
        CLIENT_CERT_FIXTURE_DIR = nil
        VERIFY_FIXTURE_DIR = nil
    end

    return {
        get_server_config = get_server_config,
        get_crl_fixture_pem = get_crl_fixture_pem,
        get_chain_fixture_dir = get_chain_fixture_dir,
        get_client_cert_fixture_dir = get_client_cert_fixture_dir,
        get_verify_fixture_dir = get_verify_fixture_dir,
        close = close,
    }

end

return { new = new }
