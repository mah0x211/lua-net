local testcase = require('testcase')
local assert = require('assert')
local exec = require('exec').execvp
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local socket = require('net.socket')
local client = require('net.tls.client')
local server = require('net.tls.server')
local context = require('net.tls.context')
local helpers = require('test.tls.context_helpers')

local DIR
local EMPTY_CRL
local REVOKED_CRL

local function writefile(name, value)
    local file = assert(io.open(DIR .. '/' .. name, 'w'))
    assert(file:write(value))
    assert(file:close())
end

local function readfile(name)
    local file = assert(io.open(DIR .. '/' .. name))
    local value = assert(file:read('*a'))
    assert(file:close())
    return value
end

local function openssl(args)
    local proc = assert(exec('openssl', args))
    local output = {}
    for line in proc.stderr:lines() do
        output[#output + 1] = line
    end
    assert.equal(assert(proc:close()).exit, 0, table.concat(output, '\n'))
end

function testcase.before_all()
    DIR = os.tmpname()
    os.remove(DIR)
    assert(mkdir(DIR, '0700'))
    writefile('index.txt', '')
    writefile('serial', '1000\n')
    writefile('crlnumber', '1000\n')
    writefile('ca.cnf', ([[
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = %s
database = $dir/index.txt
serial = $dir/serial
crlnumber = $dir/crlnumber
new_certs_dir = $dir
certificate = $dir/ca.crt
private_key = $dir/ca.key
default_md = sha256
default_days = 1
default_crl_days = 1
policy = policy_any
x509_extensions = server_cert
[ policy_any ]
commonName = supplied
[ server_cert ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost
]]):format(DIR))
    openssl({
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-days',
        '1',
        '-keyout',
        DIR .. '/ca.key',
        '-out',
        DIR .. '/ca.crt',
        '-subj',
        '/CN=CRLTestCA',
        '-addext',
        'basicConstraints=critical,CA:true',
        '-addext',
        'keyUsage=critical,keyCertSign,cRLSign',
    })
    openssl({
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        DIR .. '/server.key',
        '-out',
        DIR .. '/server.csr',
        '-subj',
        '/CN=localhost',
    })
    openssl({
        'ca',
        '-batch',
        '-config',
        DIR .. '/ca.cnf',
        '-in',
        DIR .. '/server.csr',
        '-out',
        DIR .. '/server.crt',
        '-notext',
    })
    openssl({
        'ca',
        '-config',
        DIR .. '/ca.cnf',
        '-gencrl',
        '-out',
        DIR .. '/empty.crl',
    })
    EMPTY_CRL = readfile('empty.crl')
    openssl({
        'ca',
        '-config',
        DIR .. '/ca.cnf',
        '-revoke',
        DIR .. '/server.crt',
    })
    openssl({
        'ca',
        '-config',
        DIR .. '/ca.cnf',
        '-gencrl',
        '-out',
        DIR .. '/revoked.crl',
    })
    REVOKED_CRL = readfile('revoked.crl')
end

function testcase.after_all()
    if DIR then
        assert(rmdir(DIR, true))
    end
end

local function exchange(crls)
    local pair = assert(socket.pair({
        socktype = 'stream',
    }))
    local cctx
    local sctx
    local verified
    local verify_error
    local failure
    local ok, err = pcall(function()
        cctx = assert(context.connect(assert(client({
            cafile = DIR .. '/ca.crt',
            crls = crls,
        })), pair[1]:fd(), {
            servername = 'localhost',
        }))
        sctx = assert(context.accept(assert(server({
            cert = DIR .. '/server.crt',
            key = DIR .. '/server.key',
        })), pair[2]:fd()))
        local cep = helpers.new_ep(cctx, 'client', pair[1]:fd())
        local sep = helpers.new_ep(sctx, 'server', pair[2]:fd())
        local client_done
        local server_done
        for _ = 1, 64 do
            if not client_done then
                local want
                client_done, failure, want = cctx:handshake()
                if failure then
                    break
                end
                assert(client_done or helpers.WANT[want])
            end
            helpers.pump(cep)
            helpers.pump(sep)
            if not server_done then
                local result, serr, want = sctx:handshake()
                assert.is_nil(serr)
                server_done = result
                assert(server_done or helpers.WANT[want])
            end
            helpers.pump(sep)
            helpers.pump(cep)
            if client_done and server_done then
                break
            end
        end
        assert(failure or (client_done and server_done),
               'handshake did not complete')
        verified, verify_error = cctx:get_verify_result()
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
    return failure, verified, verify_error
end

function testcase.client_accepts_crl_without_revoked_certificates()
    local err, verified = exchange(EMPTY_CRL)
    assert.is_nil(err)
    assert.is_true(verified)
end

function testcase.client_rejects_revoked_server_certificate()
    local err, verified, verify_error = exchange(REVOKED_CRL)
    assert.not_nil(err)
    assert.is_nil(verified)
    assert.match(verify_error, 'certificate revoked', true)
end

function testcase.client_without_crls_does_not_enable_crl_checking()
    local err, verified = exchange(nil)
    assert.is_nil(err)
    assert.is_true(verified)
end

function testcase.client_rejects_zero_crls_even_when_cafile_contains_crl()
    writefile('trust.pem', readfile('ca.crt') .. EMPTY_CRL)
    assert(client({
        cafile = DIR .. '/trust.pem',
    }))
    local ctx, err = client({
        cafile = DIR .. '/trust.pem',
        crls = '',
    })
    assert.is_nil(ctx)
    assert.not_nil(err)
    assert.match(tostring(err), 'no CRL loaded', true)
end
