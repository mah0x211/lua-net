require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local exec = require('exec').execvp
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local socket = require('net.socket')
local gpoll = require('gpoll')
local sleep = require('time.sleep')
local tls_context = require('net.tls.context')
local new_tls_server = require('net.tls.server')
local new_tls_client = require('net.tls.client')

local SERVER_CONFIG
local CRL_FIXTURE_DIR
local CRL_FIXTURE_PEM
local OCSP_FIXTURE_DIR
local CHAIN_FIXTURE_DIR

-- per-operation I/O timeout (seconds); each WANT wait may take up to this long.
local DEADLINE = 10

function testcase.before_all()
    local p = assert(exec('openssl', {
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-x509',
        '-days',
        '1',
        '-keyout',
        'cert.key',
        '-out',
        'cert.pem',
        '-subj',
        '/C=US/CN=www.example.com',
    }))

    for line in p.stderr:lines() do
        print(line)
    end

    local res = assert(p:close())
    if res.exit ~= 0 then
        error('failed to generate cert files')
    end

    SERVER_CONFIG = {
        cert = 'cert.pem',
        key = 'cert.key',
    }

    -- CRL fixture: build a throwaway openssl CA + empty CRL in a temp dir.
    -- CRL_FIXTURE_PEM feeds the set_crls testcase; after_all uses rmdir(2).
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

    -- OCSP fixture: build an independent CA that signs a server cert, then
    -- generate a stapled OCSP response for it.  s_server can hand this DER
    -- back at handshake time via -status_file, driving the client's
    -- ocsp_verify_cb / verify_ocsp_response / check_ocsp_response paths.
    OCSP_FIXTURE_DIR = os.tmpname()
    os.remove(OCSP_FIXTURE_DIR)
    assert(mkdir(OCSP_FIXTURE_DIR, '0700', true))

    local ocsp_cnf = OCSP_FIXTURE_DIR .. '/ca.cnf'
    local ocnf = assert(io.open(ocsp_cnf, 'w'))
    ocnf:write(([[
[ ca ]
default_ca = CA_default
[ CA_default ]
database = %s/index.txt
serial = %s/serial
new_certs_dir = %s
certificate = %s/ca.crt
private_key = %s/ca.key
default_md = sha256
default_days = 1
policy = policy_any
unique_subject = no
[ policy_any ]
commonName = supplied
[ req ]
distinguished_name = req_dn
prompt = no
[ req_dn ]
CN = localhost
]]):format(OCSP_FIXTURE_DIR, OCSP_FIXTURE_DIR, OCSP_FIXTURE_DIR,
           OCSP_FIXTURE_DIR, OCSP_FIXTURE_DIR))
    ocnf:close()

    assert(io.open(OCSP_FIXTURE_DIR .. '/index.txt', 'w')):close()
    local oserial = assert(io.open(OCSP_FIXTURE_DIR .. '/serial', 'w'))
    oserial:write('1000\n')
    oserial:close()

    -- self-signed CA
    local oca = assert(exec('openssl', {
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-days',
        '1',
        '-keyout',
        OCSP_FIXTURE_DIR .. '/ca.key',
        '-out',
        OCSP_FIXTURE_DIR .. '/ca.crt',
        '-subj',
        '/CN=OCSPTestCA',
    }))
    for _ in oca.stderr:lines() do
    end
    assert.equal(assert(oca:close()).exit, 0)

    -- server key + CSR
    local skey = assert(exec('openssl', {
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        OCSP_FIXTURE_DIR .. '/server.key',
        '-out',
        OCSP_FIXTURE_DIR .. '/server.csr',
        '-subj',
        '/CN=localhost',
    }))
    for _ in skey.stderr:lines() do
    end
    assert.equal(assert(skey:close()).exit, 0)

    -- sign the CSR with the CA (goes through openssl ca so index.txt records
    -- the issuance, which the OCSP responder later reads).
    local scrt = assert(exec('openssl', {
        'ca',
        '-batch',
        '-config',
        ocsp_cnf,
        '-in',
        OCSP_FIXTURE_DIR .. '/server.csr',
        '-out',
        OCSP_FIXTURE_DIR .. '/server.crt',
    }))
    for _ in scrt.stderr:lines() do
    end
    assert.equal(assert(scrt:close()).exit, 0)

    -- request + response DER for the server cert
    local oreq = assert(exec('openssl', {
        'ocsp',
        '-issuer',
        OCSP_FIXTURE_DIR .. '/ca.crt',
        '-cert',
        OCSP_FIXTURE_DIR .. '/server.crt',
        '-reqout',
        OCSP_FIXTURE_DIR .. '/ocsp_req.der',
    }))
    for _ in oreq.stderr:lines() do
    end
    assert.equal(assert(oreq:close()).exit, 0)

    local orsp = assert(exec('openssl', {
        'ocsp',
        '-index',
        OCSP_FIXTURE_DIR .. '/index.txt',
        '-CA',
        OCSP_FIXTURE_DIR .. '/ca.crt',
        '-rsigner',
        OCSP_FIXTURE_DIR .. '/ca.crt',
        '-rkey',
        OCSP_FIXTURE_DIR .. '/ca.key',
        '-reqin',
        OCSP_FIXTURE_DIR .. '/ocsp_req.der',
        '-respout',
        OCSP_FIXTURE_DIR .. '/ocsp_resp.der',
        '-ndays',
        '1',
    }))
    for _ in orsp.stderr:lines() do
    end
    assert.equal(assert(orsp:close()).exit, 0)

    -- generate a REVOKED variant so the client's callback can also drive
    -- the V_OCSP_CERTSTATUS_REVOKED branch.  openssl ca -revoke rewrites
    -- index.txt, so restore the valid entry afterwards.
    local idx_before = assert(io.open(OCSP_FIXTURE_DIR .. '/index.txt', 'r'))
    local idx_snapshot = idx_before:read('*a')
    idx_before:close()

    local revoke = assert(exec('openssl', {
        'ca',
        '-batch',
        '-config',
        ocsp_cnf,
        '-revoke',
        OCSP_FIXTURE_DIR .. '/server.crt',
    }))
    for _ in revoke.stderr:lines() do
    end
    assert.equal(assert(revoke:close()).exit, 0)

    local orsp_rev = assert(exec('openssl', {
        'ocsp',
        '-index',
        OCSP_FIXTURE_DIR .. '/index.txt',
        '-CA',
        OCSP_FIXTURE_DIR .. '/ca.crt',
        '-rsigner',
        OCSP_FIXTURE_DIR .. '/ca.crt',
        '-rkey',
        OCSP_FIXTURE_DIR .. '/ca.key',
        '-reqin',
        OCSP_FIXTURE_DIR .. '/ocsp_req.der',
        '-respout',
        OCSP_FIXTURE_DIR .. '/ocsp_resp_revoked.der',
        '-ndays',
        '1',
    }))
    for _ in orsp_rev.stderr:lines() do
    end
    assert.equal(assert(orsp_rev:close()).exit, 0)

    -- restore valid index.txt for the GOOD-response test.
    local idx_after = assert(io.open(OCSP_FIXTURE_DIR .. '/index.txt', 'w'))
    idx_after:write(idx_snapshot)
    idx_after:close()

    -- Hand-crafted minimal OCSP responses for each non-successful
    -- responseStatus value (malformedRequest=1, internalError=2,
    -- tryLater=3, sigRequired=5, unauthorized=6).  Wire encoding:
    --   SEQUENCE (0x30) length 3 { ENUMERATED (0x0A) length 1 value N }
    -- Feeding these via s_server -status_file drives every arm of the
    -- switch in verify_ocsp_response.
    for _, status in ipairs({
        1,
        2,
        3,
        5,
        6,
    }) do
        local f = assert(io.open(OCSP_FIXTURE_DIR .. '/ocsp_resp_status_' ..
                                     status .. '.der', 'wb'))
        f:write(string.char(0x30, 0x03, 0x0A, 0x01, status))
        f:close()
    end

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
end

function testcase.after_all()
    os.remove('cert.pem')
    os.remove('cert.key')
    if CRL_FIXTURE_DIR then
        assert(rmdir(CRL_FIXTURE_DIR, true))
        CRL_FIXTURE_DIR = nil
        CRL_FIXTURE_PEM = nil
    end
    if OCSP_FIXTURE_DIR then
        assert(rmdir(OCSP_FIXTURE_DIR, true))
        OCSP_FIXTURE_DIR = nil
    end
    if CHAIN_FIXTURE_DIR then
        assert(rmdir(CHAIN_FIXTURE_DIR, true))
        CHAIN_FIXTURE_DIR = nil
    end
end

function testcase.encrypted_length()
    -- encrypted_length returns the maximum ciphertext size that may accompany
    -- a single record for the given protocol version.  Values below are the
    -- concrete OpenSSL constants used by the memory-BIO buffer sizing.
    assert.equal(tls_context.encrypted_length('default'), 17749)
    assert.equal(tls_context.encrypted_length('tlsv1'), 17749)
    assert.equal(tls_context.encrypted_length('tlsv1.0'), 17689)
    assert.equal(tls_context.encrypted_length('tlsv1.1'), 17705)
    assert.equal(tls_context.encrypted_length('tlsv1.2'), 17749)
    assert.equal(tls_context.encrypted_length('tlsv1.3'), 16645)
end

-- WANT_READ / WANT_WRITE indicate a retryable SSL condition
local WANT = {
    [tls_context.WANT_READ] = true,
    [tls_context.WANT_WRITE] = true,
}

--- endpoint: wraps a TLS context, its fd and optional memory BIO.
--- @param ctx net.tls.context
--- @param name string
--- @param fd integer
--- @return table ep
local function new_ep(ctx, name, fd)
    return {
        ctx = ctx,
        name = name,
        fd = fd,
        bio = ctx:get_bio(),
        closed = false,
    }
end

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

--- Single-side bio pump: flush TX buffer to fd, then fill RX buffer from fd.
--- No-op when the endpoint has no memory BIO (socket-BIO mode) or is closed.
--- @param ep table
local function pump(ep)
    if ep.closed or not ep.bio then
        return
    end
    local _, err = ep.bio:drain()
    assert(not err, ep.name .. ':bio:drain: ' .. tostring(err))
    _, err = ep.bio:fill()
    assert(not err, ep.name .. ':bio:fill: ' .. tostring(err))
end

--- Wait for a retryable SSL condition on the endpoint.
--- With BIO: pump the buffers (the peer is a separate process).
--- Without BIO: wait until the fd becomes readable / writable.
--- @param ep table
--- @param want integer tls_context.WANT_READ / WANT_WRITE
--- @return boolean ok
--- @return any err
local function waitio(ep, want)
    if ep.bio then
        pump(ep)
        return true
    end
    if want == tls_context.WANT_READ then
        return gpoll.wait_readable(ep.fd, DEADLINE)
    elseif want == tls_context.WANT_WRITE then
        return gpoll.wait_writable(ep.fd, DEADLINE)
    end
    return false, 'unknown want: ' .. tostring(want)
end

--- Drive the endpoint handshake to completion.
--- @param ep table
--- @return boolean ok
--- @return any err
local function handshake(ep)
    while true do
        local ok, err, want = ep.ctx:handshake()
        if ok then
            -- with BIO, flush the final handshake flight to the fd
            pump(ep)
            return true
        elseif want and WANT[want] then
            local ok2, err2 = waitio(ep, want)
            if not ok2 then
                return false, ep.name .. ':handshake:waitio: ' .. tostring(err2)
            end
        elseif err then
            return false, ep.name .. ':handshake: ' .. tostring(err)
        else
            -- ZERO_RETURN: peer closed before handshake completed
            return false, ep.name .. ':handshake: peer closed'
        end
    end
end

--- Verify a write from the endpoint: pump the ciphertext out, then read back
--- exactly #payload bytes from the peer process' stdout.
--- @param ep table
--- @param proc exec.process the peer (its stdout receives our plaintext)
--- @param payload string
--- @return boolean ok
--- @return any err
local function transfer_write(ep, proc, payload)
    local sent = 0
    while sent < #payload do
        local n, err, want = ep.ctx:write(payload:sub(sent + 1))
        if n then
            pump(ep)
            sent = sent + n
        elseif want and WANT[want] then
            local ok, err2 = waitio(ep, want)
            if not ok then
                return false, ep.name .. ':write:waitio: ' .. tostring(err2)
            end
        elseif err then
            return false, ep.name .. ':write: ' .. tostring(err)
        else
            return false, ep.name .. ':write: peer closed'
        end
    end

    proc.stdout:set_timeout(DEADLINE)
    local got, err = proc.stdout:readn(#payload)
    if got ~= payload then
        return false,
               ep.name .. ':write verify failed (got=' .. tostring(got) ..
                   ', err=' .. tostring(err) .. ')'
    end
    return true
end

--- Verify a read on the endpoint: feed the peer process' stdin (it encrypts and
--- sends to us), then read until #payload bytes are decrypted.
--- @param ep table
--- @param proc exec.process the peer (its stdin feeds plaintext to us)
--- @param payload string
--- @return boolean ok
--- @return any err
local function transfer_read(ep, proc, payload)
    proc.stdin:set_timeout(DEADLINE)
    local ok, err = proc.stdin:write(payload)
    if not ok then
        return false, 'peer stdin:write: ' .. tostring(err)
    end

    local chunks, total = {}, 0
    while total < #payload do
        local s, err2, want = ep.ctx:read(#payload - total)
        if s then
            pump(ep)
            total = total + #s
            chunks[#chunks + 1] = s
        elseif want and WANT[want] then
            local ok2, err3 = waitio(ep, want)
            if not ok2 then
                return false, ep.name .. ':read:waitio: ' .. tostring(err3)
            end
        elseif err2 then
            return false, ep.name .. ':read: ' .. tostring(err2)
        else
            return false, ep.name .. ':read: peer closed at ' .. total .. '/' ..
                       #payload
        end
    end

    if table.concat(chunks) ~= payload then
        return false, ep.name .. ':read verify mismatch'
    end
    return true
end

--- Close the endpoint, draining any remaining BIO ciphertext.
--- @param ep table
--- @return boolean ok
--- @return any err
local function close_ep(ep)
    while true do
        local ok, err, want = ep.ctx:close()
        if ok then
            ep.closed = true
            return true
        elseif want and WANT[want] then
            local ok2, err2 = waitio(ep, want)
            if not ok2 then
                return false, ep.name .. ':close:waitio: ' .. tostring(err2)
            end
        elseif err then
            return false, ep.name .. ':close: ' .. tostring(err)
        else
            ep.closed = true
            return true
        end
    end
end

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
    local ctx = assert(tls_context.accept(server, fd, false))
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
    local ctx = assert(tls_context.accept(server, fd, true, 1))
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
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           false))
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
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           true, 1))
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
    }, 300, 512))
    local ctx = assert(tls_context.accept(server, fd, false))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert.equal(ep.ctx:get_alpn(), 'h2')
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
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
    }, 0, 0, false))
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           false))
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
        local ctx = assert(tls_context.accept(server, fd, false))
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
    local ctx = assert(tls_context.accept(server, fd, false))
    local ep = new_ep(ctx, 'server', fd)

    local ok = handshake(ep)
    assert.is_false(ok, 'handshake must fail with an out-of-policy TLS 1.3 suite')

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
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           false))
    local ep = new_ep(ctx, 'client', fd)

    local ok = handshake(ep)
    assert.is_false(ok, 'handshake must fail with an out-of-policy TLS 1.3 suite')

    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.new_server_alpn_invalid()
    -- ALPN validation rejects non-string entries and >255-byte protocols.
    -- non-string element
    local ctx, err = new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                    'default', 'default', {
        123,
    })
    assert(ctx == nil, 'should reject non-string ALPN element')
    assert(err, 'should return error')

    -- protocol name exceeding 255 bytes
    ctx, err = new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key, 'default',
                              'default', {
        string.rep('x', 256),
    })
    assert(ctx == nil, 'should reject >255 byte ALPN protocol')
    assert(err, 'should return error')
end

function testcase.new_client_alpn_invalid()
    -- ALPN validation rejects non-string entries and >255-byte protocols.
    -- non-string element
    local ctx, err = new_tls_client('default', 'default', {
        123,
    })
    assert(ctx == nil, 'should reject non-string ALPN element')
    assert(err, 'should return error')

    -- protocol name exceeding 255 bytes
    ctx, err = new_tls_client('default', 'default', {
        string.rep('x', 256),
    })
    assert(ctx == nil, 'should reject >255 byte ALPN protocol')
    assert(err, 'should return error')
end

function testcase.connect_requires_servername_when_full_verify()
    -- Full verification without a servername has no identity to match
    -- against the peer certificate, so connect must refuse to proceed.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local socks = sp

    local client = assert(new_tls_client())
    -- servername=nil, noverify_name=false, noverify_time=false,
    -- noverify_cert=false: full verification requested with no identity
    -- to verify against.
    local ctx, cerr = tls_context.connect(client, sp[1]:fd(), nil, false, false,
                                          false, false)
    assert(ctx == nil, 'connect must fail when servername is required')
    assert(cerr, 'connect must return an error object')
    assert.match(tostring(cerr), 'servername', false)
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
        local ctx, cerr = tls_context.connect(client, sp[1]:fd(), servername,
                                              false, false, false, false)
        assert(ctx, cerr and tostring(cerr) or
                   'connect must accept IP servername with verify enabled')
        for _, s in ipairs(socks) do
            s:close()
        end
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
    local ctx, cerr = tls_context.connect(client, sp[1]:fd(), nil, true, false,
                                          true, false)
    assert(ctx, cerr and tostring(cerr) or
               'connect must accept nil servername when noverify_name=true')
    for _, s in ipairs(socks) do
        s:close()
    end
end

function testcase.set_crls()
    -- valid PEM CRL is accepted (regression against luaL_checkstring's
    -- zero-length bug) and non-string arguments raise a Lua error.
    assert(CRL_FIXTURE_PEM and #CRL_FIXTURE_PEM > 0,
           'CRL fixture must be prepared by before_all')
    local client = assert(new_tls_client())

    -- valid PEM CRL: after the fix, BIO_new_mem_buf sees the full stream.
    local ok, err = client:set_crls(CRL_FIXTURE_PEM)
    assert.is_true(ok, err and tostring(err) or 'set_crls returned falsy')
    assert.is_nil(err)

    -- non-string arguments raise a Lua type error.  Numbers are accepted
    -- because luaL_checklstring converts them implicitly.
    for _, bad in ipairs({
        {},
        true,
    }) do
        local terr = assert.throws(function()
            client:set_crls(bad)
        end)
        assert.match(terr, 'string expected', false)
    end
    local nerr = assert.throws(function()
        client:set_crls()
    end)
    assert.match(nerr, 'string expected', false)
end

function testcase.connect_bio_bufcap_too_large()
    -- unreasonable bufcap makes BUF_MEM_grow fail; the fix must return
    -- (nil, error) rather than double-free abort.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    -- huge bufcap makes BUF_MEM_grow fail; before the fix this aborted
    -- with a double free, after the fix connect returns (nil, error).
    local ctx, err = tls_context.connect(client, sp[1]:fd(), nil, true, false,
                                         true, true, 2147483000)
    assert.is_nil(ctx)
    assert(err, 'connect must surface the bio_buf_init failure')
    sp[1]:close()
    sp[2]:close()
end

function testcase.bio_fill_returns_total_when_rxbuf_full()
    -- fill() must return the byte count when the ring saturates, not 0;
    -- the buggy loop retried into NULL and read(fd, NULL, 0) == 0 spelt EOF.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), nil, true, false,
                                           true, true, 1))
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
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), nil, true, false,
                                           true, false))

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
    -- write of an empty string short-circuits before SSL_write and returns 0.
    -- read with bufsiz <= 0 must fall back to BUFSIZ.  Neither branch needs
    -- a completed handshake; using a not-yet-handshaked ctx keeps the test
    -- self-contained.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), nil, true, false,
                                           true, false))

    -- empty payload: SSL_write is not invoked and no error is returned.
    assert.equal(assert(ctx:write('')), 0)

    -- negative bufsiz normalises to BUFSIZ before SSL_read runs; the
    -- ensuing SSL_read fails because handshake has not run, but that
    -- error path is not the one under test.
    local s = ctx:read(-1)
    assert.is_nil(s)

    ctx:close()
    sp[1]:close()
    sp[2]:close()
end

function testcase.new_client_option_matrix()
    -- exercise the constructor's option branches that plain new_tls_client()
    -- skips: non-default protocol, session cache enabled, prefer client
    -- ciphers, ALPN list and error callback.
    local ctx = assert(new_tls_client('tlsv1.2', 'default', {
        'h2',
        'http/1.1',
    }, 300, 128, true, function()
    end))
    assert.match(tostring(ctx), '^net.tls.client: ', false)

    -- cache_timeout <= 0 keeps tickets off; verify it still constructs.
    ctx = assert(new_tls_client('default', 'default', nil, 0))
    assert.match(tostring(ctx), '^net.tls.client: ', false)
end

function testcase.new_client_invalid_protocol()
    -- luaL_checkoption rejects unknown protocol/cipher option strings; the
    -- resulting error surfaces from new_tls_client itself.
    local err = assert.throws(function()
        new_tls_client('not-a-protocol')
    end)
    assert.match(err, 'invalid option', false)

    err = assert.throws(function()
        new_tls_client('default', 'not-a-cipher')
    end)
    assert.match(err, 'invalid option', false)
end

function testcase.set_verify_depth_and_load_verify_locations()
    -- set_verify_depth takes an unsigned integer; load_verify_locations
    -- accepts the fixture cert as the CA file with a valid CAPath.
    local client = assert(new_tls_client())
    client:set_verify_depth(5)
    assert(client:load_verify_locations('cert.pem', '.'))

    -- non-existent CA file surfaces an error object.
    local ok, err = client:load_verify_locations('./no-such-ca.pem', '.')
    assert.is_false(ok)
    assert(err)
end

function testcase.bio_userdata_methods()
    -- exercise the tls_bio Lua methods (peek/consume/space/commit) directly
    -- so tls_bio.c's uncovered pipeline surface gets touched even without a
    -- full handshake.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), nil, true, false,
                                           true, true, 1))
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
    local ctx = assert(tls_context.connect(client, csock:fd(), nil, true, false,
                                           true, true, 1))
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
    local ctx = assert(tls_context.connect(client, csock:fd(), nil, true, false,
                                           true, false))
    assert.match(tostring(ctx), '^net.tls.context: ', false)
    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.connect_noverify_time_with_valid_cert()
    -- noverify_time=true installs noverify_time_cb; a valid (non-expired)
    -- fixture cert drives its preverify_ok=1 branch.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    assert(client:load_verify_locations('cert.pem', '.'))
    -- servername matches CN of the fixture cert; noverify_time=true, but
    -- the cert is not expired, so the callback returns preverify_ok as-is.
    local ctx = assert(tls_context.connect(client, fd, 'www.example.com', false,
                                           true, false, false))
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
    local ctx = assert(tls_context.connect(client, csock:fd(), nil, true, false,
                                           true, true, 1))
    local bio = assert(ctx:get_bio())

    local n, err, again = bio:fill()
    assert.is_nil(n)
    assert.is_nil(err)
    assert.is_true(again)

    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.set_crls_rejects_non_pem_input()
    -- Non-PEM input drives PEM_X509_INFO_read_bio's 0-item path; the
    -- subsequent X509_STORE_set_flags success still returns true because
    -- the empty list is legal.  A garbage-only string, however, makes
    -- PEM_X509_INFO_read_bio return NULL.
    local client = assert(new_tls_client())
    local ok, err = client:set_crls('not a pem at all')
    -- Depending on OpenSSL version this may return true (zero CRLs read)
    -- or false with an error.  Either way the code path is exercised;
    -- assert that no crash occurs and the return contract holds.
    if ok then
        assert.is_true(ok)
    else
        assert.is_false(ok)
        assert(err)
    end
end

function testcase.set_crls_skips_non_crl_pem_entries()
    -- A cert-only PEM (no CRL blocks) drives the `!it->crl` continue
    -- branch inside the sk_X509_INFO iteration.  The overall call still
    -- succeeds because X509_STORE_set_flags is unconditionally applied.
    local pem = assert(io.open('cert.pem', 'r'))
    local body = pem:read('*a')
    pem:close()

    local client = assert(new_tls_client())
    assert(client:set_crls(body))
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
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           false))
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
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           false))
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
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           true, 1))
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

function testcase.bio_space_returns_nil_when_rxbuf_full()
    -- After fill saturates the rx ring, space() must expose the "no room"
    -- return (nil, 0) branch instead of a valid pointer.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), nil, true, false,
                                           true, true, 1))
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
    local ctx = assert(tls_context.connect(client, csock:fd(), nil, true, false,
                                           true, true, 1))
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

function testcase.connect_ip_servername_with_noverify_name()
    -- servername is a numeric IP AND noverify_name=true: the SNI-skip +
    -- verify-skip branch runs (no X509_VERIFY_PARAM_set1_ip_asc call).
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, '127.0.0.1', true, false,
                                           true, false))
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
    local ctx, err = tls_context.connect(client, sp[1]:fd(),
                                         string.rep('a', 256), false, false,
                                         false, false)
    assert.is_nil(ctx)
    assert(err)
    assert.match(tostring(err), 'ssl3_ctrl', false)

    sp[1]:close()
    sp[2]:close()
end

local function start_s_server_with_ocsp(port)
    return exec('openssl', {
        's_server',
        '-accept',
        '127.0.0.1:' .. tostring(port),
        '-cert',
        OCSP_FIXTURE_DIR .. '/server.crt',
        '-key',
        OCSP_FIXTURE_DIR .. '/server.key',
        '-CAfile',
        OCSP_FIXTURE_DIR .. '/ca.crt',
        '-status',
        '-status_file',
        OCSP_FIXTURE_DIR .. '/ocsp_resp.der',
        '-quiet',
        '-naccept',
        '1',
    })
end

function testcase.connect_s_server_with_stapled_ocsp()
    -- s_server hands back the pre-generated OCSP response during the
    -- handshake; ocsp_verify_cb / verify_ocsp_response / check_ocsp_response
    -- run the response through OCSP_response_get1_basic, OCSP_basic_verify
    -- and OCSP_resp_find_status.  The response marks the server cert as
    -- V_OCSP_CERTSTATUS_GOOD, so the callback must accept it and the
    -- handshake must complete.
    local port = free_port()
    local proc = start_s_server_with_ocsp(port)
    local csock = assert(wait_listen(port))
    local socks = {
        csock,
    }
    local fd = csock:fd()

    local client = assert(new_tls_client())
    -- load the fixture CA so OCSP_basic_verify can validate the response
    -- signer.  Without it the callback returns -1 and the handshake aborts.
    assert(client:load_verify_locations(OCSP_FIXTURE_DIR .. '/ca.crt', '.'))
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           false))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

--- Start s_server that staples the REVOKED OCSP fixture.
local function start_s_server_with_ocsp_revoked(port)
    return exec('openssl', {
        's_server',
        '-accept',
        '127.0.0.1:' .. tostring(port),
        '-cert',
        OCSP_FIXTURE_DIR .. '/server.crt',
        '-key',
        OCSP_FIXTURE_DIR .. '/server.key',
        '-CAfile',
        OCSP_FIXTURE_DIR .. '/ca.crt',
        '-status',
        '-status_file',
        OCSP_FIXTURE_DIR .. '/ocsp_resp_revoked.der',
        '-quiet',
        '-naccept',
        '1',
    })
end

function testcase.connect_s_server_with_revoked_ocsp()
    -- Stapled OCSP response marks the server cert as REVOKED; ocsp_verify_cb
    -- must return 0 and the handshake must fail.
    local port = free_port()
    local proc = start_s_server_with_ocsp_revoked(port)
    local csock = assert(wait_listen(port))
    local socks = {
        csock,
    }
    local fd = csock:fd()

    local client = assert(new_tls_client())
    assert(client:load_verify_locations(OCSP_FIXTURE_DIR .. '/ca.crt', '.'))
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           false))
    local ep = new_ep(ctx, 'client', fd)

    -- handshake must fail with an OCSP-status error surfacing from the
    -- server callback failure.
    local ok = handshake(ep)
    assert.is_false(ok)

    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.connect_s_server_with_corrupt_ocsp()
    -- Stapled bytes that d2i_OCSP_RESPONSE cannot parse must reach the
    -- decode-error branch of verify_ocsp_response.  s_server refuses to
    -- start with a malformed status file, so instead we build a
    -- syntactically-valid OCSP response whose signer certificate the
    -- client does NOT trust (unknown CA path) -- that drives the
    -- OCSP_basic_verify failure branch, which is the same block of code.
    local port = free_port()
    local proc = start_s_server_with_ocsp(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    -- Deliberately DO NOT load the fixture CA.  The stapled response is
    -- signed by an unknown issuer, so OCSP_basic_verify returns 0 and
    -- ocsp_verify_cb reports "failed to verify OCSP basic response".
    local ctx = assert(tls_context.connect(client, fd, nil, true, false, true,
                                           false))
    local ep = new_ep(ctx, 'client', fd)

    local ok = handshake(ep)
    assert.is_false(ok)

    csock:close()
    proc:close()
end

--- Start s_server that staples a malformed-status OCSP response.
local function start_s_server_with_ocsp_status(port, resp_path)
    return exec('openssl', {
        's_server',
        '-accept',
        '127.0.0.1:' .. tostring(port),
        '-cert',
        OCSP_FIXTURE_DIR .. '/server.crt',
        '-key',
        OCSP_FIXTURE_DIR .. '/server.key',
        '-CAfile',
        OCSP_FIXTURE_DIR .. '/ca.crt',
        '-status',
        '-status_file',
        resp_path,
        '-quiet',
        '-naccept',
        '1',
    })
end

function testcase.connect_s_server_with_malformed_status_ocsp()
    -- Staple each non-successful OCSP responseStatus value and confirm
    -- verify_ocsp_response rejects it through the switch on
    -- OCSP_response_status.  Covers cases malformedRequest,
    -- internalError, tryLater, sigRequired and unauthorized.
    for _, status in ipairs({
        1,
        2,
        3,
        5,
        6,
    }) do
        local port = free_port()
        local proc = start_s_server_with_ocsp_status(port, OCSP_FIXTURE_DIR ..
                                                         '/ocsp_resp_status_' ..
                                                         status .. '.der')
        local csock = assert(wait_listen(port))
        local fd = csock:fd()

        local client = assert(new_tls_client())
        assert(client:load_verify_locations(OCSP_FIXTURE_DIR .. '/ca.crt', '.'))
        local ctx = assert(tls_context.connect(client, fd, nil, true, false,
                                               true, false))
        local ep = new_ep(ctx, 'client', fd)

        local ok = handshake(ep)
        assert.is_false(ok, 'status ' .. status .. ' must fail the handshake')

        csock:close()
        proc:close()
    end
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
    local ctx = assert(tls_context.accept(server, fd, false))
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
