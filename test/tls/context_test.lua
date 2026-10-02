require('luacov')
local testcase = require('testcase')
local fork = require('testcase.fork')
local signal = require('testcase.signal')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local exec = require('exec').execvp
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local socket = require('net.socket')
local gpoll = require('gpoll')
local sleep = require('testcase.timer').sleep
local tls_context = require('net.tls.context')
local tls_cache = require('net.tls.cache')
local tls_inet = require('net.tls.stream.inet')
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')
local cert_fixtures = require('test.tls.cert_fixtures')
local context_helpers = require('test.tls.context_helpers')

-- Keep connection-oriented cases compact while public constructors use
-- immutable option tables.
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

local UNVERIFIED = {
    verify_name = false,
    verify_cert = false,
}

local SERVER_CONFIG
local CRL_FIXTURE_DIR
local CRL_FIXTURE_PEM
local CHAIN_FIXTURE_DIR
local CLIENT_CERT_FIXTURE_DIR
local VERIFY_FIXTURE_DIR
local TICKET_SESSION = os.tmpname()
local TICKET_TRACE = os.tmpname()

-- per-operation I/O timeout (seconds); each WANT wait may take up to this long.
local DEADLINE = context_helpers.DEADLINE

function testcase.before_all()
    cert_fixtures.server_certificate('cert.pem', 'cert.key')

    SERVER_CONFIG = {
        cert = 'cert.pem',
        key = 'cert.key',
    }

    -- CRL fixture: build a throwaway openssl CA + empty CRL in a temp dir.
    -- CRL_FIXTURE_PEM feeds the constructor CRL testcase; after_all uses
    -- rmdir(2).
    CRL_FIXTURE_DIR = os.tmpname()
    os.remove(CRL_FIXTURE_DIR)
    assert(mkdir(CRL_FIXTURE_DIR, '0700', true))

    local cnf_path = CRL_FIXTURE_DIR .. '/ca.cnf'
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
]]):format(CRL_FIXTURE_DIR, CRL_FIXTURE_DIR, CRL_FIXTURE_DIR, CRL_FIXTURE_DIR,
           CRL_FIXTURE_DIR))
    cnf:close()

    assert(io.open(CRL_FIXTURE_DIR .. '/index.txt', 'w')):close()
    local serial = assert(io.open(CRL_FIXTURE_DIR .. '/serial', 'w'))
    serial:write('1000\n')
    serial:close()
    local crlnum = assert(io.open(CRL_FIXTURE_DIR .. '/crlnumber', 'w'))
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
        CRL_FIXTURE_DIR .. '/ca.key',
        '-out',
        CRL_FIXTURE_DIR .. '/ca.crt',
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
        CRL_FIXTURE_DIR .. '/ca.crl',
    }))
    for _ in gencrl.stderr:lines() do
    end
    local gencrl_res = assert(gencrl:close())
    if gencrl_res.exit ~= 0 then
        error('failed to generate CRL for CRL fixture')
    end

    local crl = assert(io.open(CRL_FIXTURE_DIR .. '/ca.crl', 'r'))
    CRL_FIXTURE_PEM = crl:read('*a')
    crl:close()

    -- Chain fixture: root CA -> intermediate CA -> leaf server cert, plus a
    -- fullchain PEM (leaf + intermediate). accept_s_client_fullchain serves
    -- the fullchain to a client that only trusts the root, so the server
    -- must actually send the intermediate for the handshake to verify.
    CHAIN_FIXTURE_DIR = os.tmpname()
    os.remove(CHAIN_FIXTURE_DIR)
    assert(mkdir(CHAIN_FIXTURE_DIR, '0700', true))

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
        CHAIN_FIXTURE_DIR .. '/root.key',
        '-out',
        CHAIN_FIXTURE_DIR .. '/root.crt',
        '-subj',
        '/CN=ChainTestRootCA',
    }))
    for _ in root.stderr:lines() do
    end
    assert.equal(assert(root:close()).exit, 0)

    -- intermediate CA signed by the root
    local int_ext = assert(io.open(CHAIN_FIXTURE_DIR .. '/int_ext.cnf', 'w'))
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
        CHAIN_FIXTURE_DIR .. '/int.key',
        '-out',
        CHAIN_FIXTURE_DIR .. '/int.csr',
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
        CHAIN_FIXTURE_DIR .. '/int.csr',
        '-CA',
        CHAIN_FIXTURE_DIR .. '/root.crt',
        '-CAkey',
        CHAIN_FIXTURE_DIR .. '/root.key',
        '-CAcreateserial',
        '-days',
        '1',
        '-extfile',
        CHAIN_FIXTURE_DIR .. '/int_ext.cnf',
        '-out',
        CHAIN_FIXTURE_DIR .. '/int.crt',
    }))
    for _ in icrt.stderr:lines() do
    end
    assert.equal(assert(icrt:close()).exit, 0)

    -- leaf server certificate signed by the intermediate
    local leaf_ext = assert(io.open(CHAIN_FIXTURE_DIR .. '/leaf_ext.cnf', 'w'))
    leaf_ext:write('basicConstraints=critical,CA:FALSE\n')
    leaf_ext:close()

    local lcsr = assert(exec('openssl', {
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        CHAIN_FIXTURE_DIR .. '/leaf.key',
        '-out',
        CHAIN_FIXTURE_DIR .. '/leaf.csr',
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
        CHAIN_FIXTURE_DIR .. '/leaf.csr',
        '-CA',
        CHAIN_FIXTURE_DIR .. '/int.crt',
        '-CAkey',
        CHAIN_FIXTURE_DIR .. '/int.key',
        '-CAcreateserial',
        '-days',
        '1',
        '-extfile',
        CHAIN_FIXTURE_DIR .. '/leaf_ext.cnf',
        '-out',
        CHAIN_FIXTURE_DIR .. '/leaf.crt',
    }))
    for _ in lcrt.stderr:lines() do
    end
    assert.equal(assert(lcrt:close()).exit, 0)

    -- fullchain = leaf + intermediate
    local leaf_fh = assert(io.open(CHAIN_FIXTURE_DIR .. '/leaf.crt', 'r'))
    local leaf_pem = leaf_fh:read('*a')
    leaf_fh:close()
    local int_fh = assert(io.open(CHAIN_FIXTURE_DIR .. '/int.crt', 'r'))
    local int_pem = int_fh:read('*a')
    int_fh:close()
    local fullchain =
        assert(io.open(CHAIN_FIXTURE_DIR .. '/fullchain.pem', 'w'))
    fullchain:write(leaf_pem, int_pem)
    fullchain:close()

    -- Client-certificate fixture: an independent CA that signs a client
    -- certificate.  The server-side verify tests trust this CA and have
    -- openssl s_client present the leaf.
    CLIENT_CERT_FIXTURE_DIR = os.tmpname()
    os.remove(CLIENT_CERT_FIXTURE_DIR)
    assert(mkdir(CLIENT_CERT_FIXTURE_DIR, '0700', true))

    cert_fixtures.client_certificate(CLIENT_CERT_FIXTURE_DIR)

    -- sanity: the chain must verify against the root CA alone
    local verify = assert(exec('openssl', {
        'verify',
        '-CAfile',
        CHAIN_FIXTURE_DIR .. '/root.crt',
        '-untrusted',
        CHAIN_FIXTURE_DIR .. '/int.crt',
        CHAIN_FIXTURE_DIR .. '/leaf.crt',
    }))
    for _ in verify.stderr:lines() do
    end
    assert.equal(assert(verify:close()).exit, 0)

    -- Client-verification fixture set: a trusted CA, a good server
    -- certificate chaining to it, and three certificates each breaking
    -- exactly one verification aspect (trust, hostname, validity period).
    VERIFY_FIXTURE_DIR = os.tmpname()
    os.remove(VERIFY_FIXTURE_DIR)
    assert(mkdir(VERIFY_FIXTURE_DIR, '0700', true))
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
    local ca_crt = VERIFY_FIXTURE_DIR .. '/trusted-ca.crt'
    local ca_key = VERIFY_FIXTURE_DIR .. '/trusted-ca.key'
    local function sign(name, cn)
        openssl_ok({
            'req',
            '-new',
            '-newkey',
            'rsa:2048',
            '-nodes',
            '-keyout',
            VERIFY_FIXTURE_DIR .. '/' .. name .. '.key',
            '-out',
            VERIFY_FIXTURE_DIR .. '/' .. name .. '.csr',
            '-subj',
            '/C=US/CN=' .. cn,
        })
        openssl_ok({
            'x509',
            '-req',
            '-in',
            VERIFY_FIXTURE_DIR .. '/' .. name .. '.csr',
            '-CA',
            ca_crt,
            '-CAkey',
            ca_key,
            '-CAcreateserial',
            '-days',
            '36500',
            '-out',
            VERIFY_FIXTURE_DIR .. '/' .. name .. '.crt',
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
        VERIFY_FIXTURE_DIR .. '/untrusted-server.key',
        '-out',
        VERIFY_FIXTURE_DIR .. '/untrusted-server.crt',
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
    local vcnf_path = VERIFY_FIXTURE_DIR .. '/ca.cnf'
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
]]):format(VERIFY_FIXTURE_DIR, VERIFY_FIXTURE_DIR, VERIFY_FIXTURE_DIR, ca_crt,
           ca_key))
    vcnf:close()
    assert(io.open(VERIFY_FIXTURE_DIR .. '/index.txt', 'w')):close()
    local vserial = assert(io.open(VERIFY_FIXTURE_DIR .. '/serial', 'w'))
    vserial:write('1000\n')
    vserial:close()
    openssl_ok({
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        VERIFY_FIXTURE_DIR .. '/expired-server.key',
        '-out',
        VERIFY_FIXTURE_DIR .. '/expired-server.csr',
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
        VERIFY_FIXTURE_DIR .. '/expired-server.csr',
        '-out',
        VERIFY_FIXTURE_DIR .. '/expired-server.crt',
    })
    os.remove(VERIFY_FIXTURE_DIR .. '/good-server.csr')
    os.remove(VERIFY_FIXTURE_DIR .. '/wrongname-server.csr')
    os.remove(VERIFY_FIXTURE_DIR .. '/expired-server.csr')
    os.remove(VERIFY_FIXTURE_DIR .. '/trusted-ca.srl')
end

function testcase.after_all()
    os.remove(TICKET_SESSION)
    os.remove(TICKET_TRACE)
    os.remove('cert.pem')
    os.remove('cert.key')
    if CRL_FIXTURE_DIR then
        assert(rmdir(CRL_FIXTURE_DIR, true))
        CRL_FIXTURE_DIR = nil
        CRL_FIXTURE_PEM = nil
    end
    if CLIENT_CERT_FIXTURE_DIR then
        assert(rmdir(CLIENT_CERT_FIXTURE_DIR, true))
        CLIENT_CERT_FIXTURE_DIR = nil
    end
    if CHAIN_FIXTURE_DIR then
        assert(rmdir(CHAIN_FIXTURE_DIR, true))
        CHAIN_FIXTURE_DIR = nil
    end
    if VERIFY_FIXTURE_DIR then
        assert(rmdir(VERIFY_FIXTURE_DIR, true))
        VERIFY_FIXTURE_DIR = nil
    end
end

function testcase.encrypted_length()
    -- encrypted_length returns the maximum ciphertext size that may
    -- accompany a single record for the given protocol version.  Derive
    -- the expectations from the TLS record limits instead of magic
    -- numbers: a 5-byte header plus the 2^14 plaintext bound, with the
    -- per-version integrity overheads (1024 compression allowance,
    -- 16-byte explicit IV from TLS 1.1, MAC 20/64 bytes, 256 padding;
    -- TLS 1.3 uses a single 256-byte overhead budget).
    local header, plain = 5, 2 ^ 14
    local tls10 = header + plain + 1024 + 20 + 256
    local tls11 = tls10 + 16
    local tls12 = header + plain + 1024 + 16 + 64 + 256
    local tls13 = header + plain + 256

    assert.equal(tls_context.encrypted_length('tlsv1.0'), tls10)
    assert.equal(tls_context.encrypted_length('tlsv1.1'), tls11)
    assert.equal(tls_context.encrypted_length('tlsv1.2'), tls12)
    assert.equal(tls_context.encrypted_length('tlsv1.3'), tls13)
    -- 'default' and 'tlsv1' allow up to TLS 1.3; the largest ciphertext
    -- among the permitted versions is the TLS 1.2 bound
    assert.equal(tls_context.encrypted_length('default'), tls12)
    assert.equal(tls_context.encrypted_length('tlsv1'), tls12)
end

function testcase.accept_rejects_out_of_range_fd()
    -- accept() used to cast the lua_Integer fd straight to int, so an
    -- out-of-range value could wrap onto an unrelated fd number and be
    -- handed to OpenSSL.  It must fail with EINVAL instead.
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))

    local ctx, err = tls_context.accept(server, 2147483648)
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    ctx, err = tls_context.accept(server, -1)
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)
end

function testcase.connect_rejects_out_of_range_fd()
    -- connect() has the same lua_Integer-to-int truncation hazard as
    -- accept(); out-of-range fds must fail with EINVAL.
    local client = assert(new_tls_client())

    local ctx, err = tls_context.connect(client, 2147483648)
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    ctx, err = tls_context.connect(client, -1)
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)
end

function testcase.accept_rejects_invalid_options()
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    for _, opts in ipairs({
        1,
        {
            bufcap = 'invalid',
        },
        {
            bufcap = '1',
        },
        {
            [1] = 1,
        },
    }) do
        assert.throws(function()
            tls_context.accept(server, -1, opts)
        end)
    end
end

function testcase.connect_rejects_invalid_options()
    local client = assert(new_tls_client())
    for _, opts in ipairs({
        'server.example',
        {
            host = 123,
        },
        {
            port = {},
        },
        {
            port = -1,
        },
        {
            port = 1.5,
        },
        {
            port = 65536,
        },
        {
            servername = {},
        },
        {
            servername = 123,
        },
        {
            verify_name = 'false',
        },
        {
            verify_time = 'false',
        },
        {
            verify_cert = 'false',
        },
        {
            bufcap = 'invalid',
        },
        {
            bufcap = '1',
        },
        {
            [1] = 1,
        },
    }) do
        assert.throws(function()
            tls_context.connect(client, -1, opts)
        end)
    end
end

function testcase.connect_options_ignore_index_metamethod()
    local client = assert(new_tls_client())
    local opts = setmetatable({}, {
        __index = function()
            error('__index must not be called')
        end,
    })
    local ctx, err = tls_context.connect(client, -1, opts)
    assert.is_nil(ctx)
    assert.equal(err.type, errno.EINVAL)
end

function testcase.accept_options_ignore_index_metamethod()
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local opts = setmetatable({}, {
        __index = function()
            error('__index must not be called')
        end,
    })
    local ctx, err = tls_context.accept(server, -1, opts)
    assert.is_nil(ctx)
    assert.equal(err.type, errno.EINVAL)
end

-- WANT_READ / WANT_WRITE indicate a retryable SSL condition
local WANT = context_helpers.WANT

local new_ep = context_helpers.new_ep

--- Establish a raw (non-TLS) TCP loopback pair.  A small sleep after
--- connect(2) lets the kernel finish the three-way handshake so accept(2)
--- returns synchronously and the pair is ready for I/O without extra
--- polling.
--- @return net.socket client, net.socket server
local function make_loopback_pair()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()
    local csock = assert(socket.connect_inet('127.0.0.1', port, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    sleep(0.1)
    local ssock = assert(lsock:accept())
    lsock:close()
    return csock, ssock
end

local pump = context_helpers.pump
local handshake = context_helpers.handshake
local transfer_write = context_helpers.transfer_write
local transfer_read = context_helpers.transfer_read
local close_ep = context_helpers.close_ep

--- Find a free TCP port on 127.0.0.1 (probe socket is closed immediately).
--- @return integer port
local function free_port()
    local s = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local port = assert(s:getsockname()):port()
    s:close()
    return port
end

--- Start `openssl s_server` bound to 127.0.0.1:port; it exits after 1 client.
--- @param port integer
--- @param alpn string?
--- @param ciphersuites string? restrict TLS 1.3 to this ciphersuite list
--- @return exec.process proc
local function start_s_server(port, alpn, ciphersuites)
    local args = {
        's_server',
        '-accept',
        '127.0.0.1:' .. tostring(port),
        '-cert',
        'cert.pem',
        '-key',
        'cert.key',
        '-quiet',
        '-naccept',
        '1',
    }
    if alpn then
        args[#args + 1] = '-alpn'
        args[#args + 1] = alpn
    end
    if ciphersuites then
        args[#args + 1] = '-tls1_3'
        args[#args + 1] = '-ciphersuites'
        args[#args + 1] = ciphersuites
    end
    return exec('openssl', args)
end

local function start_ticket_s_server(port, protocol, extra_args)
    local args = {
        's_server',
        '-accept',
        '127.0.0.1:' .. tostring(port),
        '-cert',
        'cert.pem',
        '-key',
        'cert.key',
        '-quiet',
        '-state',
        '-naccept',
        '2',
        protocol == 'tlsv1.2' and '-tls1_2' or '-tls1_3',
    }
    for _, arg in ipairs(extra_args or {}) do
        args[#args + 1] = arg
    end
    return exec('openssl', args)
end

--- Start `openssl s_client` connecting to 127.0.0.1:port.
--- -quiet enables -ign_eof and -nocommands (arbitrary payload is safe).
--- @param port integer
--- @param alpn string?
--- @param ciphersuites string? restrict TLS 1.3 to this ciphersuite list
--- @return exec.process proc
local function start_s_client(port, alpn, ciphersuites)
    local args = {
        's_client',
        '-connect',
        '127.0.0.1:' .. tostring(port),
        '-quiet',
        '-noservername',
    }
    if alpn then
        args[#args + 1] = '-alpn'
        args[#args + 1] = alpn
    end
    if ciphersuites then
        args[#args + 1] = '-tls1_3'
        args[#args + 1] = '-ciphersuites'
        args[#args + 1] = ciphersuites
    end
    return exec('openssl', args)
end

--- Start `openssl s_client` pinned to TLS 1.2 with a restricted cipher
--- list, to probe which TLS 1.2 suites the server policy admits.
--- @param port integer
--- @param cipher string openssl cipher list for -cipher
--- @return exec.process proc
local function start_s_client_tls12_cipher(port, cipher)
    return exec('openssl', {
        's_client',
        '-connect',
        '127.0.0.1:' .. tostring(port),
        '-quiet',
        '-noservername',
        '-tls1_2',
        '-cipher',
        cipher,
    })
end

--- Start `openssl s_client` that verifies the server chain against cafile
--- only and aborts the handshake on a verify error.
--- @param port integer
--- @param cafile string
--- @return exec.process proc
local function start_s_client_with_ca(port, cafile)
    return exec('openssl', {
        's_client',
        '-connect',
        '127.0.0.1:' .. tostring(port),
        '-quiet',
        '-noservername',
        '-CAfile',
        cafile,
        '-verify_return_error',
    })
end

--- Start `openssl s_client` presenting a client certificate.
--- @param port integer
--- @param cert string path to the client certificate
--- @param key string path to the client private key
--- @return exec.process proc
local function start_s_client_with_cert(port, cert, key)
    return exec('openssl', {
        's_client',
        '-connect',
        '127.0.0.1:' .. tostring(port),
        '-quiet',
        '-noservername',
        '-cert',
        cert,
        '-key',
        key,
    })
end

--- Start `openssl s_client` sending the given SNI server name, optionally
--- presenting a client certificate.
--- @param port integer
--- @param servername string
--- @param cert string? path to the client certificate
--- @param key string? path to the client private key
--- @return exec.process proc
local function start_s_client_sni(port, servername, cert, key)
    local args = {
        's_client',
        '-connect',
        '127.0.0.1:' .. tostring(port),
        '-quiet',
        '-servername',
        servername,
    }
    if cert then
        args[#args + 1] = '-cert'
        args[#args + 1] = cert
        args[#args + 1] = '-key'
        args[#args + 1] = key
    end
    return exec('openssl', args)
end

--- Wait until a server is listening on 127.0.0.1:port.
--- @param port integer
--- @return net.socket? sock connected socket
--- @return any err
local function wait_listen(port)
    for _ = 1, 200 do
        local sock, err, again = socket.connect_inet('127.0.0.1', port, {
            socktype = 'stream',
            protocol = 'tcp',
        })
        if sock then
            if again then
                local ok = gpoll.wait_writable(sock:fd(), 0.05)
                if ok and not sock:error() then
                    return sock
                end
                sock:close()
            else
                return sock
            end
        end
        _ = err
        -- ECONNREFUSED: server not ready yet; back off and retry
        sleep(0.05)
    end
    return nil, 's_server did not start listening on port ' .. tostring(port)
end

function testcase.accept_s_client()
    -- socket-BIO server accept against openssl s_client: verify
    -- SSL_accept handshake plus bidirectional plaintext transfer.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client(port)
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    -- wrap() guarantees non-blocking on platforms where accept() does not
    -- inherit O_NONBLOCK from the listening socket. Keep the wrapper alive
    -- so its __gc does not close the fd while the TLS context still uses it.
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert(transfer_read(ep, proc, 'hello from client'))
    assert(transfer_write(ep, proc, 'hello from server'))
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.accept_s_client_bio()
    -- memory-BIO server accept against openssl s_client: same as
    -- accept_s_client but with a Lua-managed BIO pumping the fd.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client(port)
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    -- Keep the wrapper alive so its __gc does not close the fd while
    -- the TLS context still uses it.
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local ctx = assert(tls_context.accept(server, fd, {
        bufcap = 1,
    }))
    local ep = new_ep(ctx, 'server', fd)
    assert(ep.bio, 'BIO not set on server context')
    assert.match(tostring(ep.bio), '^net.tls.bio: ', false)

    assert(handshake(ep))
    -- 'A' avoids s_server/s_client connected-command characters
    assert(transfer_read(ep, proc, string.rep('A', 4096)))
    assert(transfer_write(ep, proc, string.rep('A', 4096)))
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.connect_s_server()
    -- socket-BIO client connect against openssl s_server: verify
    -- SSL_connect handshake plus bidirectional transfer.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local socks = {
        csock,
    }
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, UNVERIFIED))
    local ep = new_ep(ctx, 'client', fd)

    assert(handshake(ep))
    assert(transfer_write(ep, proc, 'hello from client'))
    assert(transfer_read(ep, proc, 'hello from server'))
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

local function ticket_connect_opts(host, port, servername, verify_time)
    return {
        host = host,
        port = port,
        servername = servername,
        verify_name = false,
        verify_time = verify_time == nil or verify_time,
        verify_cert = false,
    }
end

local function connect_ticket_client(port, proc, client, opts, cache)
    local sock = assert(wait_listen(port))
    local ctx = assert(tls_context.connect(client, sock:fd(), opts))
    local before
    local ep = new_ep(ctx, 'client', sock:fd())

    if cache then
        before = select(2, cache:size())
    end
    assert(handshake(ep))
    assert(transfer_read(ep, proc, 'A'))
    local after
    if cache then
        after = select(2, cache:size())
    end
    assert(close_ep(ep))
    sock:close()
    return before, after
end

local function count_full_handshakes(proc)
    local count = 0

    for line in proc.stderr:lines() do
        if line:find('write certificate', 1, true) then
            count = count + 1
        end
    end
    proc:close()
    return count
end

local function assert_client_ticket_cache(protocol)
    local port = free_port()
    local proc = start_ticket_s_server(port, protocol)
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local opts = ticket_connect_opts('127.0.0.1', port)

    for _ = 1, 2 do
        local client = assert(tls_client({
            protocol = protocol,
            cache = cache,
        }))
        local before, after = connect_ticket_client(port, proc, client, opts,
                                                    cache)
        assert.equal(before, 0)
        assert.equal(after, 1)
    end
    assert.equal(count_full_handshakes(proc), 1)
end

function testcase.client_caches_tls12_ticket()
    assert_client_ticket_cache('tlsv1.2')
end

function testcase.client_caches_tls13_psk_ticket()
    assert_client_ticket_cache('tlsv1.3')
end

function testcase.client_ticket_cache_requires_capacity_and_destination()
    for _, case in ipairs({
        {
            connect_opts = ticket_connect_opts('127.0.0.1', 443),
        },
        {
            capacity = 0,
            connect_opts = ticket_connect_opts('127.0.0.1', 443),
        },
        {
            capacity = 1,
            connect_opts = ticket_connect_opts(),
        },
    }) do
        local port = free_port()
        local proc = start_ticket_s_server(port, 'tlsv1.3')
        local cache
        if case.capacity ~= nil then
            cache = tls_cache({
                ctx_capacity = 1,
                session_capacity = case.capacity,
            })
        end
        local client = assert(tls_client({
            protocol = 'tlsv1.3',
            cache = cache,
        }))

        connect_ticket_client(port, proc, client, case.connect_opts)
        connect_ticket_client(port, proc, client, case.connect_opts)
        if cache then
            assert.equal(select(2, cache:size()), 0)
        end
        assert.equal(count_full_handshakes(proc), 2)
    end
end

function testcase.client_ticket_cache_separates_destination_and_policy()
    local base =
        ticket_connect_opts('server.example', 'https', 'server.example')
    local variants = {
        ticket_connect_opts('other.example', 'https', 'server.example'),
        ticket_connect_opts('server.example', '8443', 'server.example'),
        ticket_connect_opts('server.example', 'https', 'other.example'),
        ticket_connect_opts('server.example', 'https', 'server.example', false),
    }

    for _, variant in ipairs(variants) do
        local port = free_port()
        local proc = start_ticket_s_server(port, 'tlsv1.3')
        local cache = tls_cache({
            ctx_capacity = 1,
            session_capacity = 2,
        })
        local client = assert(tls_client({
            protocol = 'tlsv1.3',
            cache = cache,
        }))

        connect_ticket_client(port, proc, client, base)
        connect_ticket_client(port, proc, client, variant)
        local _, nsessions = cache:size()
        assert.equal(nsessions, 2)
        assert.equal(count_full_handshakes(proc), 2)
    end
end

function testcase.client_ticket_cache_ignores_tls12_session_ids()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.2', {
        '-no_ticket',
    })
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.2',
        cache = cache,
    }))
    local opts = ticket_connect_opts('127.0.0.1', port)

    connect_ticket_client(port, proc, client, opts)
    connect_ticket_client(port, proc, client, opts)
    local _, nsessions = cache:size()
    assert.equal(nsessions, 0)
    assert.equal(count_full_handshakes(proc), 2)
end

function testcase.client_ticket_cache_is_scoped_to_ssl_ctx()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.3')
    local cache = tls_cache({
        ctx_capacity = 2,
        session_capacity = 1,
    })
    local opts = ticket_connect_opts('127.0.0.1', port)
    local first = assert(tls_client({
        protocol = 'tlsv1.3',
        cache = cache,
    }))
    local second = assert(tls_client({
        protocol = 'tlsv1.3',
        alpn = {
            'h2',
        },
        cache = cache,
    }))

    connect_ticket_client(port, proc, first, opts)
    connect_ticket_client(port, proc, second, opts)
    local nctx, nsessions = cache:size()
    assert.equal(nctx, 2)
    assert.equal(nsessions, 2)
    assert.equal(count_full_handshakes(proc), 2)
end

function testcase.client_ticket_cache_clear_discards_session()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.3')
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.3',
        cache = cache,
    }))
    local opts = ticket_connect_opts('127.0.0.1', port)

    connect_ticket_client(port, proc, client, opts)
    assert.equal(select(2, cache:size()), 1)
    assert(cache:clear())
    assert.equal(select(2, cache:size()), 0)
    connect_ticket_client(port, proc, client, opts)
    assert.equal(count_full_handshakes(proc), 2)
end

function testcase.client_ticket_cache_survives_context_creation_failure()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.3')
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.3',
        cache = cache,
    }))
    local opts = ticket_connect_opts('127.0.0.1', port)

    connect_ticket_client(port, proc, client, opts)
    assert.equal(select(2, cache:size()), 1)

    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local failed_opts = ticket_connect_opts('127.0.0.1', port)
    failed_opts.bufcap = 2147483000
    local ctx, err = tls_context.connect(client, sp[1]:fd(), failed_opts)
    assert.is_nil(ctx)
    assert(err, 'connect must surface the bio_buf_init failure')
    sp[1]:close()
    sp[2]:close()

    assert.equal(select(2, cache:size()), 1)
    connect_ticket_client(port, proc, client, opts)
    assert.equal(count_full_handshakes(proc), 1)
end

function testcase.client_ticket_cache_retains_session_after_lua_error()
    local port = free_port()
    local proc = start_ticket_s_server(port, 'tlsv1.3', {
        '-num_tickets',
        '1',
    })
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.3',
        cache = cache,
    }))
    local opts = ticket_connect_opts('127.0.0.1', port)
    local sock = assert(wait_listen(port))
    local ctx = assert(tls_context.connect(client, sock:fd(), opts))
    local ep = new_ep(ctx, 'client', sock:fd())

    assert(handshake(ep))
    assert.equal(select(2, cache:size()), 0)

    local registry = debug.getregistry()
    local mtname = 'net.tls.ssl_session'
    local session_mt = assert(registry[mtname])
    registry[mtname] = nil
    local ok, err = pcall(function()
        assert(transfer_read(ep, proc, 'A'))
    end)
    registry[mtname] = session_mt

    assert.is_false(ok)
    assert.match(err, 'net.tls.cache is not initialized', false)
    assert.equal(select(2, cache:size()), 0)

    local data
    while not data do
        local chunk, readerr, want = ctx:read(1)
        if chunk then
            data = chunk
        elseif want and WANT[want] then
            pump(ep)
        else
            error('client:read: ' .. tostring(readerr))
        end
    end
    assert.equal(data, 'A')
    assert.equal(select(2, cache:size()), 1)
    assert(close_ep(ep))
    sock:close()

    connect_ticket_client(port, proc, client, opts)
    assert.equal(count_full_handshakes(proc), 1)
end

function testcase.connect_s_server_bio()
    -- memory-BIO client connect against openssl s_server, sending
    -- a 4 KiB payload so the BIO pump saturates both rings.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local socks = {
        csock,
    }
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local ep = new_ep(ctx, 'client', fd)
    assert(ep.bio, 'BIO not set on client context')

    assert(handshake(ep))
    assert(transfer_write(ep, proc, string.rep('A', 4096)))
    assert(transfer_read(ep, proc, string.rep('A', 4096)))
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.accept_s_client_alpn()
    -- ALPN 'h2' negotiation on the server side against s_client.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client(port, 'h2')
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                         'default', 'default', {
        'h2',
    }, 300))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert.equal(ep.ctx:get_alpn(), 'h2')
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.accept_s_client_alpn_mismatch_fails_handshake()
    -- RFC 7301 requires the server to abort the handshake with a fatal
    -- no_application_protocol alert when the client and server ALPN
    -- lists share no protocol.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client(port, 'h2')
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                         'default', 'default', {
        'http/1.1',
    }, 300))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    local ok, err = handshake(ep)
    assert.is_false(ok)
    assert.not_nil(err)

    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.secure_cipher_suite_selects_ecdhe_aead()
    -- the 'secure' cipher suite policy admits only ECDHE+AEAD suites on
    -- TLS 1.2 (the TLSRef intermediate profile); an AEAD client connects
    -- while an RSA-key-exchange CBC client must be rejected.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    -- the AEAD-only client negotiates an ECDHE-RSA AEAD suite
    local proc =
        start_s_client_tls12_cipher(port, 'ECDHE-RSA-AES128-GCM-SHA256')
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                         'tlsv1.2', 'secure', nil, 300))
    local ctx = assert(tls_context.accept(server, afd))
    local ep = new_ep(ctx, 'server', afd)

    assert(handshake(ep))
    assert.equal(ep.ctx:get_cipher(), 'ECDHE-RSA-AES128-GCM-SHA256')
    assert(close_ep(ep))
    proc:close()

    -- an RSA-key-exchange CBC client is inside HIGH:!aNULL but outside
    -- the ECDHE+AEAD-only policy, so the handshake must fail
    local proc2 = start_s_client_tls12_cipher(port, 'AES128-SHA')
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd2 = assert(lsock:acceptfd())
    local asock2 = assert(socket.wrap(afd2))
    socks[#socks + 1] = asock2
    local server2 = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                          'tlsv1.2', 'secure', nil, 300))
    local ctx2 = assert(tls_context.accept(server2, afd2))
    local ep2 = new_ep(ctx2, 'server', afd2)

    local ok, err = handshake(ep2)
    assert.is_false(ok)
    assert.not_nil(err)

    for _, s in ipairs(socks) do
        s:close()
    end
    proc2:close()
end

function testcase.connect_s_server_alpn()
    -- ALPN 'h2' negotiation on the client side against s_server.
    local port = free_port()
    local proc = start_s_server(port, 'h2')
    local csock = assert(wait_listen(port))
    local socks = {
        csock,
    }
    local fd = csock:fd()

    local client = assert(new_tls_client('default', 'default', {
        'h2',
    }, 0, 0))
    local ctx = assert(tls_context.connect(client, fd, UNVERIFIED))
    local ep = new_ep(ctx, 'client', fd)

    assert(handshake(ep))
    assert.equal(ep.ctx:get_alpn(), 'h2')
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.accept_s_client_tls13_ciphersuite_allowed()
    -- Every TLS 1.3 suite of the cipher policy must negotiate: s_client
    -- offers one suite per iteration, all of them inside the policy.
    for _, suite in ipairs({
        'TLS_AES_256_GCM_SHA384',
        'TLS_CHACHA20_POLY1305_SHA256',
        'TLS_AES_128_GCM_SHA256',
    }) do
        local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
            reuseaddr = true,
            reuseport = true,
        }))
        local socks = {
            lsock,
        }
        assert(lsock:listen())
        local port = assert(lsock:getsockname()):port()

        local proc = start_s_client(port, nil, suite)
        assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        local asock = assert(socket.wrap(afd))
        socks[#socks + 1] = asock
        local fd = asock:fd()

        local server = assert(new_tls_server(SERVER_CONFIG.cert,
                                             SERVER_CONFIG.key, 'default',
                                             'default'))
        local ctx = assert(tls_context.accept(server, fd))
        local ep = new_ep(ctx, 'server', fd)

        assert(handshake(ep), suite .. ' must negotiate')
        assert(transfer_write(ep, proc, 'tls1.3 ' .. suite))
        assert(close_ep(ep))
        for _, s in ipairs(socks) do
            s:close()
        end
        proc:close()
    end
end

function testcase.accept_s_client_tls13_ciphersuite_rejected()
    -- TLS 1.3 suites outside the cipher policy must not negotiate: s_client
    -- offers only TLS_AES_128_CCM_SHA256, which the policy does not include.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client(port, nil, 'TLS_AES_128_CCM_SHA256')
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                         'default', 'default'))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    local ok = handshake(ep)
    assert.is_false(ok,
                    'handshake must fail with an out-of-policy TLS 1.3 suite')

    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.connect_s_server_tls13_ciphersuite_rejected()
    -- Client side of the cipher policy: s_server offers only
    -- TLS_AES_128_CCM_SHA256, which the client policy does not include.
    local port = free_port()
    local proc = start_s_server(port, nil, 'TLS_AES_128_CCM_SHA256')
    local csock = assert(wait_listen(port))
    local socks = {
        csock,
    }
    local fd = csock:fd()

    local client = assert(new_tls_client('default', 'default'))
    local ctx = assert(tls_context.connect(client, fd, UNVERIFIED))
    local ep = new_ep(ctx, 'client', fd)

    local ok = handshake(ep)
    assert.is_false(ok,
                    'handshake must fail with an out-of-policy TLS 1.3 suite')

    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.new_server_cipher_preference()
    -- TLS 1.2 cipher preference: the client offers AES128-SHA256 before
    -- AES256-SHA384, while the 'default' server policy (HIGH:!aNULL) ranks
    -- AES256-SHA384 first. Default keeps SSL_OP_CIPHER_SERVER_PREFERENCE
    -- (server order wins); prefer_client_ciphers = true drops the option
    -- (client order wins).
    local selected_cipher = function(prefer_client)
        local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
            reuseaddr = true,
            reuseport = true,
        }))
        local socks = {
            lsock,
        }
        assert(lsock:listen())
        local port = assert(lsock:getsockname()):port()

        local proc = exec('openssl', {
            's_client',
            '-connect',
            '127.0.0.1:' .. tostring(port),
            '-brief',
            '-noservername',
            '-tls1_2',
            '-cipher',
            'ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384',
        })
        assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        -- Keep the wrapper alive so its __gc does not close the fd while
        -- the TLS context still uses it.
        local asock = assert(socket.wrap(afd))
        socks[#socks + 1] = asock
        local fd = asock:fd()

        local server = assert(new_tls_server(SERVER_CONFIG.cert,
                                             SERVER_CONFIG.key, 'tlsv1.2',
                                             'default', nil, 300, prefer_client))
        local ctx = assert(tls_context.accept(server, fd))
        local ep = new_ep(ctx, 'server', fd)
        assert(handshake(ep))

        -- s_client -brief prints the negotiated suite on stderr.
        local selected
        for line in proc.stderr:lines() do
            selected = line:match('^Ciphersuite:%s+(%S+)')
            if selected then
                break
            end
        end
        assert(close_ep(ep))
        for _, s in ipairs(socks) do
            s:close()
        end
        proc:close()
        return selected
    end

    -- default: the server preference (AES256-SHA384 ranks first) wins.
    assert.equal(selected_cipher(nil), 'ECDHE-RSA-AES256-SHA384')
    -- prefer_client_ciphers = true: the client order wins.
    assert.equal(selected_cipher(true), 'ECDHE-RSA-AES128-SHA256')
end

function testcase.new_server_alpn_invalid()
    -- ALPN validation rejects non-string entries and >255-byte protocols.
    assert.throws(function()
        new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key, 'default',
                       'default', {
            123,
        })
    end)
    assert.throws(function()
        new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key, 'default',
                       'default', {
            string.rep('x', 256),
        })
    end)
end

function testcase.new_client_alpn_invalid()
    -- ALPN validation rejects non-string entries and >255-byte protocols.
    -- non-string element
    assert.throws(function()
        new_tls_client('default', 'default', {
            123,
        })
    end)
    assert.throws(function()
        new_tls_client('default', 'default', {
            string.rep('x', 256),
        })
    end)
end

function testcase.new_client_alpn_total_length_invalid()
    -- RFC 7301 limits the wire-format ProtocolNameList to 65535 bytes;
    -- each element contributes 1 length byte plus its name, so a list of
    -- 256 elements x 255-byte names reaches 65536 bytes and must be
    -- rejected before it reaches OpenSSL.
    local protos = {}
    for i = 1, 256 do
        protos[i] = string.rep('x', 255)
    end
    assert.throws(function()
        new_tls_client('default', 'default', protos)
    end)
end

function testcase.new_client_alpn_total_length_at_limit()
    -- A list whose wire format totals exactly 65535 bytes stays within
    -- the RFC 7301 limit and must be accepted: 255 elements x 256 bytes
    -- (1 length byte + 255-byte name) plus one 254-byte name.
    local protos = {}
    for i = 1, 255 do
        protos[i] = string.rep('x', 255)
    end
    protos[256] = string.rep('y', 254)
    local ctx, err = new_tls_client('default', 'default', protos)
    assert(ctx, err)
end

function testcase.connect_requires_servername_when_full_verify()
    -- Full verification without a servername has no identity to match
    -- against the peer certificate, so connect must refuse to proceed.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    -- servername=nil, verify_name=true, verify_time=true,
    -- verify_cert=true: full verification requested with no identity
    -- to verify against.
    local ctx, cerr = tls_context.connect(client, sp[1]:fd())
    assert(ctx == nil, 'connect must fail when servername is required')
    assert(cerr, 'connect must return an error object')
    assert.match(tostring(cerr), 'servername', false)
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.connect_allows_missing_servername_with_verify_cert_false()
    -- With certificate verification fully disabled there is no identity
    -- to match, so connect must not demand a servername; SNI is simply
    -- not sent.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    -- servername=nil, verify_name=false, verify_time=true,
    -- verify_cert=false: verification is fully disabled, so there is
    -- no identity requirement to satisfy.
    local ctx, err = tls_context.connect(client, sp[1]:fd(), UNVERIFIED)
    assert(ctx, err)
    assert(ctx:close())
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.connect_rejects_verify_name_without_verify_cert()
    -- Name verification runs as part of certificate verification, so
    -- requesting it while disabling certificate verification is a
    -- contradiction and must surface as an error instead of silently
    -- taking no effect.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    -- servername='www.example.com', verify_name=true, verify_time=true,
    -- verify_cert=false
    local ctx, err = tls_context.connect(client, sp[1]:fd(), {
        servername = 'www.example.com',
        verify_cert = false,
    })
    assert(ctx == nil, 'connect must fail on the contradictory request')
    assert(err, 'connect must return an error object')
    assert.match(tostring(err), 'verify_name', false)
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.connect_rejects_embedded_nul_servername()
    -- A servername containing an embedded NUL ("www.example.com\0.evil")
    -- would be silently truncated to "www.example.com" by the C string APIs
    -- used for SNI, hostname verification and IP identity; connect must
    -- reject it with EINVAL instead.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())

    -- with full verification
    local ctx, err = tls_context.connect(client, sp[1]:fd(), {
        servername = 'www.example.com\0.evil',
    })
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    -- with verification fully disabled (SNI would still truncate)
    ctx, err = tls_context.connect(client, sp[1]:fd(), {
        servername = 'a\0.evil',
        verify_name = false,
        verify_cert = false,
    })
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    for _, s in ipairs(sp) do
        s:close()
    end
end

function testcase.handshake_reports_clean_close_without_error()
    -- A clean close_notify from the peer during the handshake surfaces
    -- as a failure without an error object, the TCP-convention signature
    -- shared with read(): (false, nil) means the peer closed cleanly,
    -- while every actual failure carries an error object.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = {
        sp[1],
        sp[2],
    }

    local client = assert(new_tls_client())
    local cctx = assert(tls_context.connect(client, sp[1]:fd(), {
        servername = 'www.example.com',
        verify_name = false,
        verify_cert = false,
    }))

    -- the first round sends the ClientHello and asks to read
    local ok, err, want = cctx:handshake()
    assert.is_false(ok)
    assert.is_nil(err)
    assert.is_number(want)
    -- the ClientHello ciphertext must reach the peer
    assert(cctx:get_bio():drain())

    -- the peer answers with a plaintext close_notify alert record
    assert(sp[2]:send('\21\3\3\0\2\1\0'))
    -- move the injected record from the socket into the rx ring so the
    -- BIO-backed handshake can observe it
    assert(cctx:get_bio():fill())

    ok, err, want = cctx:handshake()
    -- the clean close returns no values at all, the TCP-convention
    -- signature shared with read()
    assert.is_nil(ok)
    assert.is_nil(err, 'the clean close must not carry an error object')
    assert.is_nil(want)

    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.handshake_wrapper_reports_clean_close_without_error()
    -- the net.tls.Socket wrapper keeps the same signature when the peer
    -- closes during the handshake: (false, nil) for the clean close
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = {
        sp[1],
        sp[2],
    }

    local client = assert(new_tls_client())
    local cctx = assert(tls_context.connect(client, sp[1]:fd(), {
        servername = 'www.example.com',
        verify_name = false,
        verify_cert = false,
    }))
    -- the ClientHello ciphertext must reach the peer before it can answer
    -- with a close_notify; the wrapper drives the handshake internally,
    -- so drain/fill manually here
    assert(sp[2]:send('\21\3\3\0\2\1\0'))
    local c = tls_inet.Client(sp[1], cctx)

    local ok, err = c:handshake()
    assert.is_false(ok)
    assert.is_nil(err, 'the clean close must not carry an error object')

    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.connect_accepts_ip_servername_with_verify()
    -- IPv4/IPv6 literals are accepted with verify enabled; SSL_get0_param
    -- receives an IP identity through X509_VERIFY_PARAM_set1_ip_asc.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    for _, servername in ipairs({
        '127.0.0.1',
        '::1',
    }) do
        local ctx, cerr = tls_context.connect(client, sp[1]:fd(), {
            servername = servername,
        })
        assert(ctx, cerr and tostring(cerr) or
                   'connect must accept IP servername with verify enabled')
    end
    -- close only after the loop: connect() now rejects the -1 fd reported by
    -- a closed socket instead of silently handing it to OpenSSL.
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.connect_accepts_no_servername_when_hostname_verify_disabled()
    -- Dropping hostname verification exempts the caller from providing a
    -- servername; connect must accept nil then.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    local ctx, cerr = tls_context.connect(client, sp[1]:fd(), UNVERIFIED)
    assert(ctx, cerr and tostring(cerr) or
               'connect must accept nil servername when verify_name=false')
    for _, s in ipairs(socks) do
        s:close()
    end
end

-- The client-verification test group below uses the fixtures generated
-- into VERIFY_FIXTURE_DIR by before_all: a trusted CA, a good server
-- certificate chaining to it, and three certificates each breaking
-- exactly one verification aspect (trust, hostname, validity period).

--- Start `openssl s_server` presenting the given certificate pair; it
--- exits after 1 client.
--- @param port integer
--- @param cert string
--- @param key string
--- @return exec.process proc
local function start_s_server_cert(port, cert, key)
    return exec('openssl', {
        's_server',
        '-accept',
        '127.0.0.1:' .. tostring(port),
        '-cert',
        cert,
        '-key',
        key,
        '-quiet',
        '-naccept',
        '1',
    })
end

--- Connect a client that trusts only the fixture CA and drives the
--- handshake with the given verification switches.  Returns the endpoint
--- on success; on handshake failure returns nil and the error.
--- @param port integer
--- @param servername string
--- @param verify_name boolean
--- @param verify_time boolean
--- @param verify_cert boolean
--- @return table? ep
--- @return any err
local function connect_verifying_client(port, servername, verify_name,
                                        verify_time, verify_cert)
    local csock, cerr = wait_listen(port)
    if not csock then
        return nil, cerr
    end
    local fd = csock:fd()

    local client, err = tls_client({
        cafile = VERIFY_FIXTURE_DIR .. '/trusted-ca.crt',
    })
    if not client then
        csock:close()
        return nil, err
    end
    local ctx
    ctx, err = tls_context.connect(client, fd, {
        servername = servername,
        verify_name = verify_name,
        verify_time = verify_time,
        verify_cert = verify_cert,
    })
    if not ctx then
        csock:close()
        return nil, err
    end

    local ep = new_ep(ctx, 'client', fd, csock)
    local hok
    hok, err = handshake(ep)
    if not hok then
        ep.ctx:close()
        csock:close()
        return nil, err
    end
    return ep
end

function testcase.client_verify_good_chain_succeeds()
    -- control for the negative fixtures: the good-server certificate
    -- chains to the loaded trust anchor and matches the servername, so
    -- full verification succeeds and the session transfers data.
    local port = free_port()
    local proc = start_s_server_cert(port,
                                     VERIFY_FIXTURE_DIR .. '/good-server.crt',
                                     VERIFY_FIXTURE_DIR .. '/good-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', true,
                                             true, true)
    assert(ep, err and tostring(err) or
               'full verification must accept the good certificate')
    collectgarbage('collect')
    assert(transfer_write(ep, proc, 'verified'))
    assert(close_ep(ep))
    proc:close()
end

function testcase.client_verify_untrusted_chain_fails_handshake()
    -- a self-signed certificate that does not chain to the loaded trust
    -- anchor must fail the handshake under full verification
    local port = free_port()
    local proc = start_s_server_cert(port, VERIFY_FIXTURE_DIR ..
                                         '/untrusted-server.crt',
                                     VERIFY_FIXTURE_DIR ..
                                         '/untrusted-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', true,
                                             true, true)
    assert.is_nil(ep)
    assert.not_nil(err, 'the handshake must fail with an error object')

    proc:close()
end

function testcase.client_verify_name_mismatch_fails_handshake()
    -- a validly chained certificate whose CN does not match the
    -- servername must fail the handshake under full verification
    local port = free_port()
    local proc = start_s_server_cert(port, VERIFY_FIXTURE_DIR ..
                                         '/wrongname-server.crt',
                                     VERIFY_FIXTURE_DIR ..
                                         '/wrongname-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', true,
                                             true, true)
    assert.is_nil(ep)
    assert.not_nil(err, 'the handshake must fail with an error object')

    proc:close()
end

function testcase.client_verify_expired_cert_fails_handshake()
    -- an otherwise valid certificate whose validity period has ended
    -- must fail the handshake under full verification
    local port = free_port()
    local proc = start_s_server_cert(port, VERIFY_FIXTURE_DIR ..
                                         '/expired-server.crt',
                                     VERIFY_FIXTURE_DIR .. '/expired-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', true,
                                             true, true)
    assert.is_nil(ep)
    assert.not_nil(err, 'the handshake must fail with an error object')

    proc:close()
end

function testcase.client_verify_cert_false_allows_untrusted_chain()
    -- effectiveness of verify_cert=false: certificate verification is
    -- skipped entirely, so even the untrusted certificate connects and
    -- transfers data
    local port = free_port()
    local proc = start_s_server_cert(port, VERIFY_FIXTURE_DIR ..
                                         '/untrusted-server.crt',
                                     VERIFY_FIXTURE_DIR ..
                                         '/untrusted-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', false,
                                             true, false)
    assert(ep, err and tostring(err) or
               'verify_cert=false must accept the untrusted certificate')
    assert(transfer_write(ep, proc, 'unverified'))
    assert(close_ep(ep))
    proc:close()
end

function testcase.client_verify_name_false_allows_name_mismatch()
    -- effectiveness of verify_name=false: the chain is still verified
    -- but the hostname mismatch no longer fails the handshake
    local port = free_port()
    local proc = start_s_server_cert(port, VERIFY_FIXTURE_DIR ..
                                         '/wrongname-server.crt',
                                     VERIFY_FIXTURE_DIR ..
                                         '/wrongname-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', false,
                                             true, true)
    assert(ep, err and tostring(err) or
               'verify_name=false must accept the mismatched hostname')
    assert(transfer_write(ep, proc, 'name-off'))
    assert(close_ep(ep))
    proc:close()
end

function testcase.client_verify_time_false_allows_expired_cert()
    -- effectiveness of verify_time=false: the chain and the hostname are
    -- still verified but the expired validity period no longer fails
    -- the handshake
    local port = free_port()
    local proc = start_s_server_cert(port, VERIFY_FIXTURE_DIR ..
                                         '/expired-server.crt',
                                     VERIFY_FIXTURE_DIR .. '/expired-server.key')
    local ep, err = connect_verifying_client(port, 'www.example.com', true,
                                             false, true)
    assert(ep, err and tostring(err) or
               'verify_time=false must accept the expired certificate')
    assert(transfer_write(ep, proc, 'time-off'))
    assert(close_ep(ep))
    proc:close()
end

function testcase.new_client_with_crls()
    -- valid PEM CRL is accepted (regression against luaL_checkstring's
    -- zero-length bug) and non-string arguments raise a Lua error.
    assert(CRL_FIXTURE_PEM and #CRL_FIXTURE_PEM > 0,
           'CRL fixture must be prepared by before_all')
    local client = assert(tls_client({
        crls = CRL_FIXTURE_PEM,
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

function testcase.connect_bio_bufcap_too_large()
    -- unreasonable bufcap makes BUF_MEM_grow fail; the fix must return
    -- (nil, error) rather than double-free abort.
    local client = assert(new_tls_client())
    for _, bufcap in ipairs({
        2147483000, -- just below INT_MAX
        2147483648, -- INT_MAX + 1
        4611686018427387904, -- 2^62
    }) do
        local sp = assert(socket.pair({
            socktype = 'stream',
        }))
        -- huge bufcap makes BUF_MEM_grow fail; before the fix this aborted
        -- with a double free, after the fix connect returns (nil, error).
        local ctx, err = tls_context.connect(client, sp[1]:fd(), {
            verify_name = false,
            verify_cert = false,
            bufcap = bufcap,
        })
        assert.is_nil(ctx)
        assert(err, 'connect must surface the bio_buf_init failure')
        sp[1]:close()
        sp[2]:close()
    end
end

function testcase.connect_bio_bufcap_no_int_truncation()
    -- 2^32 + 1000 used to narrow to int 1000 in tls_bio_new() and silently
    -- create undersized buffers; the unallocatable request must surface as
    -- (nil, error) instead.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx, err = tls_context.connect(client, sp[1]:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 4294968296,
    })
    assert.is_nil(ctx)
    assert(err, 'connect must surface the unallocatable bufcap as an error')
    sp[1]:close()
    sp[2]:close()
end

function testcase.accept_bio_bufcap_no_int_truncation()
    -- accept() shares tls_bio_new() with connect(); the same narrowing
    -- regression must not silently create undersized buffers there either.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local ctx, err = tls_context.accept(server, sp[1]:fd(), {
        bufcap = 4294968296,
    })
    assert.is_nil(ctx)
    assert(err, 'accept must surface the unallocatable bufcap as an error')
    sp[1]:close()
    sp[2]:close()
end

function testcase.connect_bio_bufcap_exact()
    -- a representable bufcap above the minimum is honoured as-is: the empty
    -- ring reports exactly the requested writable space.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local cap = 1048576
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = cap,
    }))
    local bio = assert(ctx:get_bio())
    local _, space_len = bio:space()
    assert.equal(space_len, cap)
    sp[1]:close()
    sp[2]:close()
end

function testcase.connect_options_table()
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local cap = 1048576
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), {
        verify_name = false,
        verify_time = true,
        verify_cert = false,
        bufcap = cap,
    }))
    local _, space_len = assert(ctx:get_bio()):space()
    assert.equal(space_len, cap)
    assert(ctx:close())
    sp[1]:close()
    sp[2]:close()
end

function testcase.accept_options_table()
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local cap = 1048576
    local ctx = assert(tls_context.accept(server, sp[1]:fd(), {
        bufcap = cap,
    }))
    local _, space_len = assert(ctx:get_bio()):space()
    assert.equal(space_len, cap)
    assert(ctx:close())
    sp[1]:close()
    sp[2]:close()
end

--- Drive both endpoints of an in-process BIO pair to a completed handshake
--- by alternating single handshake steps with pump().
--- @param cep table client endpoint
--- @param sep table server endpoint
--- @return boolean ok
--- @return any err
local function handshake_pair(cep, sep)
    for _ = 1, 100 do
        if cep.done and sep.done then
            return true
        end
        for _, ep in ipairs({
            cep,
            sep,
        }) do
            if not ep.done then
                local ok, err, want = ep.ctx:handshake()
                pump(ep)
                if ok then
                    ep.done = true
                else
                    assert(want and WANT[want],
                           ep.name .. ':handshake: ' .. tostring(err))
                end
            end
        end
    end
    return false, 'handshake did not converge'
end

function testcase.client_ticket_cache_discards_expired_session()
    local cache = tls_cache({
        ctx_capacity = 1,
        session_capacity = 1,
    })
    local client = assert(tls_client({
        protocol = 'tlsv1.2',
        cache = cache,
    }))
    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        protocol = 'tlsv1.2',
        session_timeout = 1,
    }))

    local function new_pair()
        local csock, ssock = make_loopback_pair()
        local cctx = assert(tls_context.connect(client, csock:fd(), {
            host = '127.0.0.1',
            port = 443,
            verify_name = false,
            verify_cert = false,
        }))
        local sctx = assert(tls_context.accept(server, ssock:fd()))
        return csock, ssock, cctx, sctx
    end

    local csock, ssock, cctx, sctx = new_pair()
    assert(handshake_pair(new_ep(cctx, 'client', csock:fd()),
                          new_ep(sctx, 'server', ssock:fd())))
    assert.equal(select(2, cache:size()), 1)
    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()

    sleep(2)
    csock, ssock, cctx, sctx = new_pair()
    assert.equal(select(2, cache:size()), 0)
    assert(handshake_pair(new_ep(cctx, 'client', csock:fd()),
                          new_ep(sctx, 'server', ssock:fd())))
    assert.equal(select(2, cache:size()), 1)
    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.shutdown_close_notify_reaches_peer_bio()
    -- shutdown() must not free the context; the close_notify ciphertext it
    -- leaves in the TX BIO has to be drained to the socket so the peer sees
    -- a clean EOF instead of a truncation.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local cctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))

    -- the initiator's first shutdown leaves its close_notify in the TX BIO
    local ok, err, want = cctx:shutdown()
    assert.is_false(ok)
    assert.is_nil(err)
    assert.equal(want, tls_context.WANT_WRITE)
    -- the context and its BIO must still be alive after the call
    assert(cctx:get_bio(), 'BIO must survive shutdown()')
    pump(cep)

    -- retry: close_notify sent, now waiting for the peer's one
    ok, err, want = cctx:shutdown()
    assert.is_false(ok)
    assert.is_nil(err)
    assert.equal(want, tls_context.WANT_READ)

    -- the peer receives the close_notify as a clean EOF
    pump(sep)
    assert.is_nil(sctx:read(1024), 'peer must see close_notify as EOF')

    -- the peer already received our close_notify, so its shutdown completes
    -- immediately with its own close_notify left in the TX BIO
    ok, err, want = sctx:shutdown()
    assert.is_true(ok)
    assert.is_nil(err)
    assert.is_nil(want)
    -- the SSL object is released on completion but the BIO stays available
    -- for the final drain
    assert(sctx:get_bio(), 'BIO must survive shutdown() completion')
    pump(sep)
    pump(cep)

    -- the initiator's retry completes once the peer's close_notify arrives
    assert(cctx:shutdown())

    -- close() is a pure disposal and idempotent; shutdown() stays true
    -- after disposal
    assert(cctx:close())
    assert(cctx:close())
    assert(cctx:shutdown())
    assert(sctx:close())

    csock:close()
    ssock:close()
end

function testcase.read_reports_clean_close_on_close_notify()
    -- After the peer shuts down cleanly, read() follows the TCP
    -- convention and returns nothing: (nil, nil), like a plain socket
    -- read at EOF, instead of surfacing the close as an error.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local cctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))

    -- initiate the client shutdown and deliver its close_notify
    cctx:shutdown()
    pump(cep)
    pump(sep)

    local str, err = sctx:read(1024)
    assert.is_nil(str)
    assert.is_nil(err, 'the clean close must not carry an error object')

    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.write_fails_after_own_close_notify_sent()
    -- After our own close_notify has been sent, a further write must
    -- fail with an error instead of looking like success.  (Writing
    -- after only the peer's close_notify stays legal: TLS 1.3 allows
    -- the half-close direction.)
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local cctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))

    -- the client's first shutdown leaves its close_notify in the TX BIO
    cctx:shutdown()
    pump(cep)
    pump(sep)

    local n, err = cctx:write('x')
    assert.is_nil(n)
    assert.not_nil(err)

    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.shutdown_before_handshake_and_close_idempotent()
    -- shutdown() before the handshake is a no-op that must not free the
    -- context; close() is an unconditional disposal and idempotent.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), UNVERIFIED))

    assert(ctx:shutdown())
    local bio = assert(ctx:get_bio(), 'BIO must survive shutdown()')
    -- an empty ring drains as a no-op
    assert.equal(bio:drain(), 0)

    assert(ctx:close())
    assert(ctx:close())
    assert(ctx:shutdown())
    assert.is_nil(ctx:get_bio())

    sp[1]:close()
    sp[2]:close()
end

function testcase.bio_fill_returns_total_when_rxbuf_full()
    -- fill() must return the byte count when the ring saturates, not 0;
    -- the buggy loop retried into NULL and read(fd, NULL, 0) == 0 spelt EOF.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())
    local _, space_len = bio:space()
    assert.greater(space_len, 0)

    -- peer sends more than bufcap so a single fill() saturates the ring.
    assert(ssock:write(string.rep('X', space_len + 100)))
    sleep(0.1)
    -- The fill() call must read the entire rxbuf capacity, not EOF.
    local total, err, again = bio:fill()
    assert.equal(total, space_len)
    assert.is_nil(err)
    assert.is_nil(again)

    csock:close()
    ssock:close()
end

function testcase.methods_after_close()
    -- close before handshake exercises the "handshake_cb != NULL" branch that
    -- releases the SSL context without SSL_shutdown; further calls surface
    -- EINVAL through the shared "!ctx->ssl" gates in each method.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), UNVERIFIED))

    assert(ctx:close())
    -- second close is a no-op via the "!ctx->ssl" early return
    assert(ctx:close())

    -- every method returns (nil/false, EINVAL) once the SSL context is gone
    local ok, err = ctx:handshake()
    assert.is_false(ok)
    assert.equal(err.type, errno.EINVAL)

    local n, werr = ctx:write('data')
    assert.is_nil(n)
    assert.equal(werr.type, errno.EINVAL)

    local s, rerr = ctx:read()
    assert.is_nil(s)
    assert.equal(rerr.type, errno.EINVAL)

    local bio, gerr = ctx:get_bio()
    assert.is_nil(bio)
    assert.equal(gerr.type, errno.EINVAL)

    local alpn, aerr = ctx:get_alpn()
    assert.is_nil(alpn)
    assert.equal(aerr.type, errno.EINVAL)

    sp[1]:close()
    sp[2]:close()
end

function testcase.write_read_edge_lengths()
    -- write of an empty string is rejected like the plain socket write
    -- and never reaches SSL_write.  read with bufsiz <= 0 must fall back
    -- to BUFSIZ.  Neither branch needs a completed handshake; using a
    -- not-yet-handshaked ctx keeps the test self-contained.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), UNVERIFIED))

    -- empty payload: the write is rejected with EINVAL before SSL_write
    -- is invoked, matching the plain socket write.
    local n, werr = ctx:write('')
    assert.is_nil(n)
    assert.not_nil(error_is(werr, errno.EINVAL))

    -- a non-positive bufsiz is rejected with EINVAL like the plain
    -- socket read; passing 0 through to SSL_read made the retry loop
    -- block until the receive deadline.
    local s, rerr = ctx:read(0)
    assert.is_nil(s)
    assert.not_nil(error_is(rerr, errno.EINVAL))
    s, rerr = ctx:read(-1)
    assert.is_nil(s)
    assert.not_nil(error_is(rerr, errno.EINVAL))

    ctx:close()
    sp[1]:close()
    sp[2]:close()
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
        cafile = SERVER_CONFIG.cert,
        capath = '.',
        crls = CRL_FIXTURE_PEM,
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

function testcase.new_contexts_have_no_mutation_methods()
    local client = assert(new_tls_client())
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))

    assert.is_nil(client.set_verify_depth)
    assert.is_nil(client.load_verify_locations)
    assert.is_nil(client.set_crls)
    assert.is_nil(server.set_verify)
    assert.is_nil(server.set_sni_callback)
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

function testcase.sni_callback_with_captured_arguments()
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local target = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local extra = {}
    for i = 1, 20 do
        extra[i] = i
    end
    local got
    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        sni_callback = function(name)
            got = {
                n = #extra + 1,
            }
            for i = 1, #extra do
                got[i] = extra[i]
            end
            got[#extra + 1] = name
            return target
        end,
    }))

    local cctx = assert(tls_context.connect(client, csock:fd(), {
        servername = 'www.example.com',
        verify_name = false,
        verify_cert = false,
    }))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))

    -- all 20 extra arguments plus the servername reach the callback intact
    assert(got, 'the sni callback must have run')
    assert.equal(got.n, 21)
    for i = 1, 20 do
        assert.equal(got[i], i)
    end
    assert.equal(got[21], 'www.example.com')

    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.cached_server_sni_callback_survives_clear_and_gc()
    local csock, ssock = make_loopback_pair()
    local cache = tls_cache({
        ctx_capacity = 1,
    })
    local seen
    local opts = {
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        cache = cache,
        sni_callback = function(name)
            seen = name
        end,
    }
    local server
    do
        local first = assert(tls_server(opts))
        server = assert(tls_server(opts))
        assert.is_true(first ~= server)
        assert.equal(cache:size(), 1)
    end

    assert.is_true(cache:clear())
    collectgarbage('collect')

    local client = assert(tls_client({}))
    local cctx = assert(tls_context.connect(client, csock:fd(), {
        servername = 'www.example.com',
        verify_name = false,
        verify_cert = false,
    }))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local cep = new_ep(cctx, 'client', csock:fd())
    local sep = new_ep(sctx, 'server', ssock:fd())
    assert(handshake_pair(cep, sep))
    assert.equal(seen, 'www.example.com')

    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.new_client_verify_options()
    local client = assert(tls_client({
        verify_depth = 5,
        cafile = 'cert.pem',
        capath = '.',
    }))
    assert.match(tostring(client), '^net.tls.client: ', false)

    local ctx, err = tls_client({
        cafile = './no-such-ca.pem',
        capath = '.',
    })
    assert.is_nil(ctx)
    assert.not_nil(err)
end

function testcase.new_client_verify_locations_optional_arguments()
    assert(tls_client({
        cafile = 'cert.pem',
    }))
    assert(tls_client({
        capath = '.',
    }))
end

function testcase.bio_userdata_methods()
    -- exercise the tls_bio Lua methods (peek/consume/space/commit) directly
    -- so tls_bio.c's uncovered pipeline surface gets touched even without a
    -- full handshake.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())

    -- space() returns the writable region.  Filling it with a small
    -- payload from the peer and then reading it back exercises the
    -- fill / commit / peek / consume path.
    local space_ptr, space_len = bio:space()
    assert.not_nil(space_ptr)
    assert.greater(space_len, 0)

    assert(ssock:write('AB'))
    sleep(0.1)
    local n = assert(bio:fill())
    assert.greater(n, 0)

    -- peek reveals the readable region without consuming; peek on an
    -- empty tx buffer returns nil / 0.
    local tx_ptr, tx_len = bio:peek()
    assert.is_nil(tx_ptr)
    assert.equal(tx_len, 0)

    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.bio_consume_and_commit_reject_negative_offsets()
    -- consume/commit build their error message via snprintf + lua_error
    -- because lua_pushvfstring on Lua 5.3+ refuses %lld.  Passing a
    -- negative offset must therefore raise with the formatted message
    -- intact rather than an "invalid option '%l'" pushfstring error.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())

    local cerr = assert.throws(function()
        bio:consume(-1)
    end)
    assert.match(cerr, 'consume(-1): out of range', true)

    local merr = assert.throws(function()
        bio:commit(-1)
    end)
    assert.match(merr, 'commit(-1): out of range', true)

    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.tostring_metamethods()
    -- __tostring on tls.client, tls.server and tls.context userdata.
    local client = assert(new_tls_client())
    assert.match(tostring(client), '^net.tls.client: ', false)

    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    assert.match(tostring(server), '^net.tls.server: ', false)

    local csock, ssock = make_loopback_pair()
    local ctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))
    assert.match(tostring(ctx), '^net.tls.context: ', false)
    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.connect_verify_time_false_with_valid_cert()
    -- verify_time=false installs the expiry-ignoring callback; a valid (non-expired)
    -- fixture cert drives its preverify_ok=1 branch.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(tls_client({
        cafile = 'cert.pem',
        capath = '.',
    }))
    -- servername matches CN of the fixture cert; verify_time=false, but
    -- the cert is not expired, so the callback returns preverify_ok as-is.
    local ctx = assert(tls_context.connect(client, fd, {
        servername = 'www.example.com',
        verify_time = false,
    }))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))
    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.bio_fill_returns_eagain_on_empty_socket()
    -- fill on an idle socket must surface EAGAIN via the (nil, nil, again)
    -- return convention.  This drives tls_bio.c's RETRY / EAGAIN branch.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())

    local n, err, again = bio:fill()
    assert.is_nil(n)
    assert.is_nil(err)
    assert.is_true(again)

    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.new_client_rejects_non_pem_crls()
    -- Non-PEM input drives PEM_X509_INFO_read_bio's 0-item path; the
    -- subsequent X509_STORE_set_flags success still returns true because
    -- the empty list is legal.  A garbage-only string, however, makes
    -- PEM_X509_INFO_read_bio return NULL.
    local client, err = tls_client({
        crls = 'not a pem at all',
    })
    -- Depending on OpenSSL version this may return true (zero CRLs read)
    -- or false with an error.  Either way the code path is exercised;
    -- assert that no crash occurs and the return contract holds.
    if client then
        assert.match(tostring(client), '^net.tls.client: ', false)
    else
        assert.is_nil(client)
        assert.not_nil(err)
    end
end

function testcase.new_client_crls_skips_non_crl_pem_entries()
    -- A cert-only PEM (no CRL blocks) drives the `!it->crl` continue
    -- branch inside the sk_X509_INFO iteration.  The overall call still
    -- succeeds because X509_STORE_set_flags is unconditionally applied.
    local pem = assert(io.open('cert.pem', 'r'))
    local body = pem:read('*a')
    pem:close()

    assert(tls_client({
        crls = body,
    }))
end

function testcase.handshake_idempotent_after_success()
    -- Once the handshake completes, handshake_cb is cleared; calling
    -- handshake() again must short-circuit to the "already done" branch
    -- instead of re-entering SSL_connect/SSL_accept.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, UNVERIFIED))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))
    assert(ctx:handshake())

    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.get_alpn_returns_nil_when_not_negotiated()
    -- get_alpn is a hot path that ends in `return 0` when no ALPN was
    -- selected; the plain handshake path never advertises ALPN, so a
    -- fresh handshake must expose the len==0 branch.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, UNVERIFIED))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))
    assert.is_nil(ctx:get_alpn())

    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.bio_peek_returns_data_after_ssl_write()
    -- After a full BIO handshake and SSL_write, the tx ring holds
    -- ciphertext; peek() must return a lightuserdata pointer and length.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))

    -- SSL_write pushes ciphertext into txbuf; drain() has not run yet
    -- inside our helper because we call write() directly on the ctx.
    local bio = assert(ctx:get_bio())
    assert(ctx:write('hi'))
    local ptr, len = bio:peek()
    assert.not_nil(ptr)
    assert.greater(len, 0)

    -- drain so proc doesn't block on the next iteration
    assert(bio:drain())

    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.drain_survives_sigpipe_after_shutdown_wr()
    -- Draining the TX ring after the local write direction is shut down
    -- must surface EPIPE as a Lua error object, not kill the process with
    -- SIGPIPE.  The child runs with SIGPIPE at its default disposition so
    -- the runner's SIGPIPE ignore cannot mask the behaviour; the parent
    -- detects a SIGPIPE death via the wait status.
    local proc = assert(fork())
    if proc:is_child() then
        signal.sigdefault('SIGPIPE')

        -- the first handshake call emits the ClientHello into the TX ring
        -- and then reports WANT_READ; shutting down the write direction
        -- makes the subsequent drain() fail deterministically
        local socks = assert(socket.pair({
            socktype = 'stream',
        }))
        local client = assert(new_tls_client())
        local ctx = assert(tls_context.connect(client, socks[1]:fd(), {
            verify_name = false,
            verify_cert = false,
            bufcap = 1,
        }))
        local bio = assert(ctx:get_bio())
        local ok = ctx:handshake()
        assert(not ok, 'handshake must not complete without a TLS peer')

        assert(socks[1]:shutdown('wr'))
        local n, derr = bio:drain()
        assert.is_nil(n)
        assert.match(derr, 'EPIPE')
        os.exit(0)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.bio_space_returns_nil_when_rxbuf_full()
    -- After fill saturates the rx ring, space() must expose the "no room"
    -- return (nil, 0) branch instead of a valid pointer.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())
    local _, space_len = bio:space()
    assert(ssock:write(string.rep('X', space_len + 100)))
    sleep(0.1)
    local total = assert(bio:fill())
    assert.equal(total, space_len)

    local ptr, len = bio:space()
    assert.is_nil(ptr)
    assert.equal(len, 0)

    csock:close()
    ssock:close()
end

function testcase.bio_fill_and_drain_after_close_return_einval()
    -- Once ctx:close() releases the BIO, its fd is set to -1; fill/drain
    -- must surface EINVAL through the fd<0 gate.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())
    assert(ctx:close())

    local n, ferr = bio:fill()
    assert.is_nil(n)
    assert.equal(ferr.type, errno.EINVAL)

    local d, derr = bio:drain()
    assert.is_nil(d)
    assert.equal(derr.type, errno.EINVAL)

    csock:close()
    ssock:close()
end

function testcase.connect_ip_servername_with_verify_name_false()
    -- servername is a numeric IP AND verify_name=false: the SNI-skip +
    -- verify-skip branch runs (no X509_VERIFY_PARAM_set1_ip_asc call).
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, {
        servername = '127.0.0.1',
        verify_name = false,
        verify_cert = false,
    }))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))

    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.connect_rejects_servername_longer_than_sni_limit()
    -- SNI hostnames are capped at 255 octets.  Passing a longer name must
    -- surface SSL_set_tlsext_host_name's failure through the standard
    -- (nil, error) return of tls_context.connect.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx, err = tls_context.connect(client, sp[1]:fd(), {
        servername = string.rep('a', 256),
    })
    assert.is_nil(ctx)
    assert(err)
    assert.match(tostring(err), 'ssl3_ctrl', false)

    sp[1]:close()
    sp[2]:close()
end

function testcase.accept_s_client_fullchain()
    -- socket-BIO server accept: the server loads fullchain.pem (leaf +
    -- intermediate) while s_client trusts the root CA only, so the
    -- handshake verifies only when the intermediate is actually sent.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client_with_ca(port, CHAIN_FIXTURE_DIR .. '/root.crt')
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    -- wrap() guarantees non-blocking; keep the wrapper alive so its __gc
    -- does not close the fd while the TLS context still uses it.
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(CHAIN_FIXTURE_DIR .. '/fullchain.pem',
                                         CHAIN_FIXTURE_DIR .. '/leaf.key'))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert(transfer_read(ep, proc, 'hello from client'))
    assert(transfer_write(ep, proc, 'hello from server'))
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.server_new_rejects_key_mismatch()
    -- net.tls.server must refuse a private key that does not match the
    -- certificate instead of failing later at handshake time.
    local server, err = new_tls_server(CHAIN_FIXTURE_DIR .. '/leaf.crt',
                                       'cert.key')
    assert.is_nil(server)
    assert(err, 'key/cert mismatch must return an error')
end

function testcase.bio_methods_reusable_across_many_connections()
    -- BIO_METHOD objects are created per connection; the composed type is
    -- cached and shared so that BIO_get_new_index()'s small budget is not
    -- drained.  Creating many sequential connections must keep succeeding
    -- (a per-connection index would exhaust the budget at ~64).
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()
    local client = assert(new_tls_client())

    for _ = 1, 70 do
        local csock = assert(socket.connect_inet('127.0.0.1', port, {
            socktype = 'stream',
            protocol = 'tcp',
        }))
        sleep(0.01)
        local ssock = assert(lsock:accept())
        local ctx, err = tls_context.connect(client, csock:fd(), UNVERIFIED)
        assert(ctx, err and tostring(err) or
                   'connect must keep succeeding across 70 connections')
        assert(ctx:get_bio())
        assert(ctx:close())
        assert(ctx:shutdown())
        csock:close()
        ssock:close()
    end
    lsock:close()
end

function testcase.bio_methods_after_ctx_close()
    -- get_bio() exposes the BIO userdata to Lua; after ctx:close() freed the
    -- BUF_MEM backing, space()/peek() used to hand out lightuserdata into
    -- the freed region (use-after-free).  Every method must report EINVAL
    -- on the freed BIO instead.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), UNVERIFIED))
    local bio = assert(ctx:get_bio())

    assert(ctx:close())

    -- space() / peek() must not return a lightuserdata into freed memory
    local sptr, slen = bio:space()
    assert.is_nil(sptr)
    assert.equal(slen.type, errno.EINVAL)
    local pptr, plen = bio:peek()
    assert.is_nil(pptr)
    assert.equal(plen.type, errno.EINVAL)

    -- commit() / consume() / fill() / drain() must report EINVAL
    local ok, cerr = bio:commit(0)
    assert.is_nil(ok)
    assert.equal(cerr.type, errno.EINVAL)
    ok, cerr = bio:consume(0)
    assert.is_nil(ok)
    assert.equal(cerr.type, errno.EINVAL)
    local n, ferr = bio:fill()
    assert.is_nil(n)
    assert.equal(ferr.type, errno.EINVAL)
    n, ferr = bio:drain()
    assert.is_nil(n)
    assert.equal(ferr.type, errno.EINVAL)

    sp[1]:close()
    sp[2]:close()
end

function testcase.negotiation_getters_after_handshake()
    -- Verified handshake against the chain fixture (root -> intermediate ->
    -- leaf): get_version / get_cipher / get_peer_cert / get_verify_result
    -- report the negotiated parameters on both endpoints.
    local csock, ssock = assert(make_loopback_pair())
    local server = assert(new_tls_server(CHAIN_FIXTURE_DIR .. '/fullchain.pem',
                                         CHAIN_FIXTURE_DIR .. '/leaf.key'))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local sep = new_ep(sctx, 'server', ssock:fd())

    local client = assert(tls_client({
        cafile = CHAIN_FIXTURE_DIR .. '/root.crt',
        capath = '.',
    }))
    local cctx = assert(tls_context.connect(client, csock:fd(), {
        servername = 'www.example.com',
    }))
    local cep = new_ep(cctx, 'client', csock:fd())

    assert(handshake_pair(cep, sep))

    -- the negotiated parameters are visible on both endpoints
    for _, ep in ipairs({
        cep,
        sep,
    }) do
        assert.re_match(ep.ctx:get_version(), '^TLSv1\\.[23]$')
        assert.re_match(ep.ctx:get_cipher(), '^TLS_')
    end

    -- the client sees the server leaf certificate in PEM form; the server
    -- sees no peer certificate because the client presented none
    assert.re_match(cep.ctx:get_peer_cert(), '^-----BEGIN CERTIFICATE')
    assert.is_nil(sep.ctx:get_peer_cert())

    -- the chain verified successfully against the root CA
    assert.is_true(cep.ctx:get_verify_result())

    -- the getters are not the subject here; dispose both contexts
    assert(cctx:close())
    assert(sctx:close())
    csock:close()
    ssock:close()
end

function testcase.negotiation_getters_before_and_after_close()
    -- Before the handshake OpenSSL reports an unknown version, no cipher
    -- and no peer certificate; after close() every getter surfaces the
    -- disposed-context error like get_alpn().
    local csock, ssock = assert(make_loopback_pair())
    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    local client = assert(new_tls_client())
    local cctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))

    -- before the handshake the version value is OpenSSL-dependent (some
    -- versions report the maximum supported version, others "unknown");
    -- only its presence is stable.  No cipher is selected and the peer has
    -- not presented a certificate yet.
    assert.is_string(cctx:get_version())
    assert.is_nil(cctx:get_cipher())
    assert.is_nil(cctx:get_peer_cert())
    -- the verify result starts at X509_V_OK and has not been computed yet
    assert.is_true(cctx:get_verify_result())

    assert(cctx:close())
    assert(sctx:close())
    local v, err = cctx:get_version()
    assert.is_nil(v)
    assert.not_nil(err)
    v, err = cctx:get_cipher()
    assert.is_nil(v)
    assert.not_nil(err)
    v, err = cctx:get_peer_cert()
    assert.is_nil(v)
    assert.not_nil(err)
    v, err = cctx:get_verify_result()
    assert.is_nil(v)
    assert.not_nil(err)

    csock:close()
    ssock:close()
end

function testcase.server_verify_client_cert_required()
    -- A require-mode server that trusts the client CA accepts a client
    -- presenting a valid certificate; the client certificate and its
    -- verification result are visible on the accepted context.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client_with_cert(port, CLIENT_CERT_FIXTURE_DIR ..
                                              '/client.crt',
                                          CLIENT_CERT_FIXTURE_DIR ..
                                              '/client.key')
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        verify_mode = 'require',
        cafile = CLIENT_CERT_FIXTURE_DIR .. '/ca.crt',
        capath = '.',
    }))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert.re_match(ctx:get_peer_cert(), '^-----BEGIN CERTIFICATE')
    assert.is_true(ctx:get_verify_result())

    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.server_verify_client_cert_required_rejects_no_cert()
    -- require mode aborts the handshake when the client presents no
    -- certificate
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client(port)
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        verify_mode = 'require',
        cafile = CLIENT_CERT_FIXTURE_DIR .. '/ca.crt',
        capath = '.',
    }))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    local ok, err = handshake(ep)
    assert.is_false(ok)
    assert.not_nil(err)

    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.server_verify_client_cert_required_rejects_untrusted()
    -- a certificate from a CA the server does not trust fails the handshake
    -- in require mode
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client_with_cert(port, SERVER_CONFIG.cert,
                                          SERVER_CONFIG.key)
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        verify_mode = 'require',
        cafile = CLIENT_CERT_FIXTURE_DIR .. '/ca.crt',
        capath = '.',
    }))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    local ok, err = handshake(ep)
    assert.is_false(ok)
    assert.not_nil(err)

    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.server_verify_client_cert_request_without_cert()
    -- request mode lets the handshake continue without a client
    -- certificate; no peer certificate is then visible
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client(port)
    assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        verify_mode = 'request',
        cafile = CLIENT_CERT_FIXTURE_DIR .. '/ca.crt',
        capath = '.',
    }))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert.is_nil(ctx:get_peer_cert())

    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.sni_switch_applies_vhost_verify_settings()
    -- SSL_set_SSL_CTX() only swaps the certificate chain and the sid_ctx;
    -- the verify mode, depth and verify parameters stay on the
    -- connection. A vhost configured with verify_mode='require' was
    -- previously not enforced after an SNI switch, so a client could
    -- bypass the certificate requirement by connecting with the vhost's
    -- hostname.  The switch must re-apply the target CTX verify settings.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    -- the root server keeps the default (no client verification)
    -- vhost A requires a client certificate signed by its CA
    local vhosta = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        verify_mode = 'require',
        cafile = CLIENT_CERT_FIXTURE_DIR .. '/ca.crt',
    }))
    -- vhost B keeps the default like the root
    local vhostb = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    local root = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        sni_callback = function(name)
            if name == 'www.example.com' then
                return vhosta
            end
            return vhostb
        end,
    }))

    local function accept_handshake()
        assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        local asock = assert(socket.wrap(afd))
        socks[#socks + 1] = asock
        local fd = asock:fd()
        local ctx = assert(tls_context.accept(root, fd))
        local ep = new_ep(ctx, 'server', fd)
        return ep, handshake(ep)
    end

    -- 1) vhost A without a client certificate: the handshake must fail
    local proc = start_s_client_sni(port, 'www.example.com')
    local ep, ok, err = accept_handshake()
    assert.is_false(ok)
    assert.not_nil(err, 'vhost A must demand a client certificate')
    assert(close_ep(ep))
    proc:close()

    -- 2) vhost A with the client certificate: the handshake succeeds
    proc = start_s_client_sni(port, 'www.example.com',
                              CLIENT_CERT_FIXTURE_DIR .. '/client.crt',
                              CLIENT_CERT_FIXTURE_DIR .. '/client.key')
    ep, ok, err = accept_handshake()
    assert(ok, err)
    assert(close_ep(ep))
    proc:close()

    -- 3) vhost B without a client certificate: the handshake succeeds
    proc = start_s_client_sni(port, 'other.example.net')
    ep, ok, err = accept_handshake()
    assert(ok, err)
    assert(close_ep(ep))
    proc:close()

    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.new_server_rejects_out_of_range_verify_depth()
    assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        verify_depth = 2147483647,
    }))
    assert.throws(function()
        tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            verify_depth = 2147483648,
        })
    end)
end

--- Accept and hand-shake `nconns` sequential TLS connections on `lsock`
--- with `server` against `openssl s_client -reconnect`, then count how
--- many of the connections resumed the session.
--- @param lsock net.socket listening socket
--- @param server net.tls.server
--- @param port integer
--- @param nconns integer
function testcase.new_client_rejects_out_of_range_verify_depth()
    assert(tls_client({
        verify_depth = 0,
    }))
    assert(tls_client({
        verify_depth = 2147483647,
    }))
    assert.throws(function()
        tls_client({
            verify_depth = 2147483648,
        })
    end)
end

--- Count how many of `nconns` sequential TLS 1.2 connections against the
--- server resumed their session.  Every connection is closed with the
--- graceful shutdown of close_ep(): without the close_notify exchange
--- the client discards the session per the TLS 1.2 specification, which
--- would make even enabled tickets look disabled. TLS 1.2 is forced so
--- -no_ticket can separately probe Session ID resumption.
--- @param lsock net.socket listening socket
--- @param server net.tls.server
--- @param port integer
--- @param nconns integer
--- @return integer reused count of "Reused," connections
local function count_resumed(lsock, server, port, nconns, no_ticket)
    local args = {
        's_client',
        '-connect',
        '127.0.0.1:' .. tostring(port),
        '-reconnect',
        '-noservername',
        '-tls1_2',
    }
    if no_ticket then
        args[#args + 1] = '-no_ticket'
    end
    local proc = assert(exec('openssl', args))

    for _ = 1, nconns do
        assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        -- keep the wrapper alive so its __gc does not close the fd during
        -- the handshake
        local asock = assert(socket.wrap(afd))
        local ctx = assert(tls_context.accept(server, afd))
        local ep = new_ep(ctx, 'server', afd)
        assert(handshake(ep))
        assert(close_ep(ep))
        asock:close()
    end

    -- "Q" terminates s_client's interactive loop, closing stdout and
    -- thus ending the iteration below
    assert(proc.stdin:write('Q\n'))
    local reused = 0
    for line in proc.stdout:lines() do
        if line:match('^Reused,') then
            reused = reused + 1
        end
    end
    proc:close()
    return reused
end

function testcase.new_server_session_tickets_disabled()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                         'tlsv1.2'))
    assert.equal(count_resumed(lsock, server, port, 6), 5)
    assert.equal(count_resumed(lsock, server, port, 6, true), 0)

    server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                   'tlsv1.2', 'default', nil, 0))
    assert.equal(count_resumed(lsock, server, port, 6), 0)

    server = assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                   'tlsv1.2', 'default', nil, -1))
    assert.equal(count_resumed(lsock, server, port, 6), 0)

    lsock:close()
end

local ticket_connection = context_helpers.new_ticket_connection(TICKET_TRACE)

function testcase.new_server_resumes_tls12_and_tls13_tickets()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local session = TICKET_SESSION
    os.remove(session)

    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local server = assert(new_tls_server(SERVER_CONFIG.cert,
                                             SERVER_CONFIG.key))
        local reused, ticket = ticket_connection(lsock, server, protocol,
                                                 session)
        assert.is_false(reused)
        assert.is_true(ticket)
        reused, ticket = ticket_connection(lsock, server, protocol, session,
                                           true)
        assert.is_true(reused)
        assert.is_true(ticket)

        local other = assert(new_tls_server(SERVER_CONFIG.cert,
                                            SERVER_CONFIG.key))
        reused = ticket_connection(lsock, other, protocol, session, true)
        assert.is_false(reused)
    end
    os.remove(session)
    lsock:close()
end

function testcase.new_server_disables_tls13_tickets()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, timeout in ipairs({
        0,
        -1,
    }) do
        local server = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            session_timeout = timeout,
        }))
        os.remove(TICKET_SESSION)
        local reused, ticket = ticket_connection(lsock, server, '-tls1_3',
                                                 TICKET_SESSION)
        assert.is_false(reused)
        assert.is_false(ticket)
    end
    lsock:close()
end

function testcase.new_server_shares_ticket_keys_with_cached_context()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local cache = tls_cache({
            ctx_capacity = 1,
            session_capacity = 64,
        })
        local opts = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            cache = cache,
        }
        local first = assert(tls_server(opts))
        local reused, ticket = ticket_connection(lsock, first, protocol,
                                                 TICKET_SESSION)
        assert.is_false(reused)
        assert.is_true(ticket)
        local second = assert(tls_server(opts))
        assert.is_true(ticket_connection(lsock, second, protocol,
                                         TICKET_SESSION, true))
        local nctx, nsessions = cache:size()
        assert.equal(nctx, 1)
        assert.equal(nsessions, 0)
        assert(cache:clear())
        local fresh = assert(tls_server(opts))
        assert.is_false(ticket_connection(lsock, fresh, protocol,
                                          TICKET_SESSION, true))
    end
    lsock:close()
end

function testcase.new_server_expired_tickets_fall_back_to_full_handshake()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local server = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            session_timeout = 1,
        }))
        local reused, ticket = ticket_connection(lsock, server, protocol,
                                                 TICKET_SESSION)
        assert.is_false(reused)
        assert.is_true(ticket)
        sleep(2)
        assert.is_false(ticket_connection(lsock, server, protocol,
                                          TICKET_SESSION, true))
    end
    lsock:close()
end

function testcase.new_server_resumes_tickets_with_client_certificate()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local client_opts = {
        cert = CLIENT_CERT_FIXTURE_DIR .. '/client.crt',
        key = CLIENT_CERT_FIXTURE_DIR .. '/client.key',
    }
    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local server = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            verify_mode = 'require',
            cafile = CLIENT_CERT_FIXTURE_DIR .. '/ca.crt',
        }))
        assert.is_false(ticket_connection(lsock, server, protocol,
                                          TICKET_SESSION, false, client_opts))
        assert.is_true(ticket_connection(lsock, server, protocol,
                                         TICKET_SESSION, true, client_opts))
    end
    lsock:close()
end

function testcase.new_server_sni_does_not_reuse_root_verification_policy()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local target = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            verify_mode = 'require',
            cafile = CLIENT_CERT_FIXTURE_DIR .. '/ca.crt',
        }))
        local root = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            sni_callback = function()
                return target
            end,
        }))
        assert.is_false(ticket_connection(lsock, root, protocol, TICKET_SESSION))
        local err = assert.throws(ticket_connection, lsock, root, protocol,
                                  TICKET_SESSION, true, {
            servername = 'www.example.com',
        })
        assert.match(err, 'certificate')
    end
    lsock:close()
end

function testcase.new_server_resumes_tickets_for_selected_sni_server()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, protocol in ipairs({
        '-tls1_2',
        '-tls1_3',
    }) do
        local first = assert(new_tls_server(SERVER_CONFIG.cert,
                                            SERVER_CONFIG.key))
        local second = assert(new_tls_server(SERVER_CONFIG.cert,
                                             SERVER_CONFIG.key))
        local names = {}
        local root = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            sni_callback = function(name)
                names[#names + 1] = name
                if name == 'www.example.com' then
                    return first
                elseif name == 'other.example.com' then
                    return second
                end
            end,
        }))
        local opts = {
            servername = 'www.example.com',
        }
        assert.is_false(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                          false, opts))
        assert.is_true(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                         true, opts))
        opts.servername = 'other.example.com'
        assert.is_false(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                          true, opts))
        opts.servername = 'unknown.example.com'
        assert.is_false(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                          false, opts))
        assert.is_true(ticket_connection(lsock, root, protocol, TICKET_SESSION,
                                         true, opts))
        assert.equal(names, {
            'www.example.com',
            'www.example.com',
            'other.example.com',
            'unknown.example.com',
            'unknown.example.com',
        })
    end
    lsock:close()
end

function testcase.new_server_skips_sni_callback_for_ip_literals()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local called = false
    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        sni_callback = function()
            called = true
        end,
    }))
    for _, name in ipairs({
        '127.0.0.1',
        '::1',
    }) do
        assert.is_false(ticket_connection(lsock, server, '-tls1_2', nil, false,
                                          {
            servername = name,
        }))
        assert.is_false(called)
    end
    lsock:close()
end

function testcase.new_server_acknowledges_sni_on_default_fallback()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        sni_callback = function(name)
            assert.equal(name, 'unknown.example.com')
            return nil
        end,
    }))
    local reused, _, trace = ticket_connection(lsock, server, '-tls1_2', nil,
                                               false, {
        servername = 'unknown.example.com',
    })
    assert.is_false(reused)
    local bytes = {}
    local hello = assert(trace:match('], ServerHello\n(.-)\n<<<'))
    for hex in hello:gmatch('%x%x') do
        bytes[#bytes + 1] = tonumber(hex, 16)
    end
    -- Skip the handshake header, version, random, session ID, cipher,
    -- compression method and extension-list length.
    local idx = 45 + bytes[39]
    local acknowledged = false
    while idx + 3 <= #bytes do
        local kind = bytes[idx] * 256 + bytes[idx + 1]
        local len = bytes[idx + 2] * 256 + bytes[idx + 3]
        if kind == 0 then
            assert.equal(len, 0)
            acknowledged = true
        end
        idx = idx + 4 + len
    end
    assert.is_true(acknowledged)
    lsock:close()
end

function testcase.new_server_sni_callback_errors_abort_handshake()
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    for _, callback in ipairs({
        function()
            error('SNI selection failed')
        end,
        function()
            error({})
        end,
        function()
            return false
        end,
    }) do
        local server = assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            sni_callback = callback,
        }))
        local err = assert.throws(ticket_connection, lsock, server, '-tls1_3',
                                  nil, false, {
            servername = 'www.example.com',
        })
        assert.match(err, 'callback failed')
    end
    lsock:close()
end

function testcase.new_server_rejects_malformed_sni()
    local function u16(n)
        return string.char(math.floor(n / 256), n % 256)
    end
    local called = false
    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        sni_callback = function()
            called = true
        end,
    }))
    for _, sni in ipairs({
        '', -- truncated list
        '\0\0\0\0\1A', -- wrong list length
        '\0\4\1\0\1A', -- unsupported name type
        '\0\4\0\0\2A', -- wrong name length
        '\0\3\0\0\0', -- empty hostname
        u16(259) .. '\0' .. u16(256) .. string.rep('A', 256),
        '\0\4\0\0\1\0', -- embedded NUL
    }) do
        local csock, ssock = make_loopback_pair()
        local ctx = assert(tls_context.accept(server, ssock:fd()))
        local ext = '\0\0' .. u16(#sni) .. sni
        local body = '\3\3' .. string.rep('\0', 32) .. '\0\0\2\192\47\1\0' ..
                         u16(#ext) .. ext
        local hello = '\1\0' .. u16(#body) .. body
        local record = '\22\3\1' .. u16(#hello) .. hello
        assert.equal(csock:write(record), #record)
        assert(gpoll.wait_readable(ssock:fd(), DEADLINE))
        assert.equal(ctx:get_bio():fill(), #record)
        local ok, err = ctx:handshake()
        assert.is_false(ok)
        assert.not_nil(err)
        assert.is_false(called)
        ctx:close()
        csock:close()
        ssock:close()
    end
end

function testcase.new_server_verify_options()
    local err = assert.throws(function()
        tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            verify_mode = 'hello',
        })
    end)
    assert.re_match(err, 'hello')

    local server
    server, err = tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        verify_mode = 'require',
        cafile = '__net_no_such_ca__.crt',
    })
    assert.is_nil(server)
    assert.not_nil(err)

    assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        cafile = SERVER_CONFIG.cert,
        capath = '.',
    }))
    for _, mode in ipairs({
        'none',
        'request',
        'require',
    }) do
        assert(tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            verify_mode = mode,
            verify_depth = 2,
        }))
    end
    assert.throws(function()
        tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            verify_depth = -1,
        })
    end)
    assert.throws(function()
        tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            verify_mode = 'require\0',
        })
    end)
end

function testcase.new_server_accepts_complete_option_table()
    local server = assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
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
        cafile = SERVER_CONFIG.cert,
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
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
        }
        opts[field] = value
        local err = assert.throws(function()
            tls_server(opts)
        end)
        assert.match(err, 'opts.' .. field .. ' must be ' .. expected)
    end
end

function testcase.new_server_requires_option_table_and_credentials()
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
            cert = SERVER_CONFIG.cert,
        })
    end)
    assert.match(err, 'opts.key is required')

    err = assert.throws(function()
        tls_server({
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            [1] = 'invalid key',
        })
    end)
    assert.match(err, 'opts keys must be strings')

    assert(tls_server({
        cert = SERVER_CONFIG.cert,
        key = SERVER_CONFIG.key,
        unknown_option = true,
    }))
end

function testcase.new_server_rejects_unknown_protocol_and_cipher()
    for _, field in ipairs({
        'protocol',
        'cipher',
    }) do
        local err = assert.throws(function()
            tls_server({
                cert = SERVER_CONFIG.cert,
                key = SERVER_CONFIG.key,
                [field] = 'not-a-' .. field,
            })
        end)
        assert.match(err, 'opts.' .. field .. '=')
        assert.match(err, 'is not recognized')
    end
end

function testcase.new_rejects_nul_paths()
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
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
        }
        opts[field] = 'cert.pem\0ignored'
        local err = assert.throws(function()
            tls_server(opts)
        end)
        assert.match(err, 'must not contain NUL', false)
    end

end
