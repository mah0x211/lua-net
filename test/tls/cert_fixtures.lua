local assert = require('assert')
local exec = require('exec').execvp

local function server_certificate(cert, key)
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
        key,
        '-out',
        cert,
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
end

local function client_certificate(dir)
    local cca = assert(exec('openssl', {
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
        '-subj',
        '/CN=ClientTestCA',
    }))
    for _ in cca.stderr:lines() do
    end
    assert.equal(assert(cca:close()).exit, 0)

    local ccsr = assert(exec('openssl', {
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        dir .. '/client.key',
        '-out',
        dir .. '/client.csr',
        '-subj',
        '/CN=test-client',
    }))
    for _ in ccsr.stderr:lines() do
    end
    assert.equal(assert(ccsr:close()).exit, 0)

    local ccrt = assert(exec('openssl', {
        'x509',
        '-req',
        '-in',
        dir .. '/client.csr',
        '-CA',
        dir .. '/ca.crt',
        '-CAkey',
        dir .. '/ca.key',
        '-CAcreateserial',
        '-days',
        '1',
        '-out',
        dir .. '/client.crt',
    }))
    for _ in ccrt.stderr:lines() do
    end
    assert.equal(assert(ccrt:close()).exit, 0)
end

local function client_certificate_chain(dir)
    client_certificate(dir)
    local function openssl(args)
        local proc = assert(exec('openssl', args))
        for _ in proc.stderr:lines() do
        end
        assert.equal(assert(proc:close()).exit, 0)
    end
    local ext = assert(io.open(dir .. '/intermediate.ext', 'w'))
    ext:write('basicConstraints=critical,CA:true\n',
              'keyUsage=critical,keyCertSign,cRLSign\n')
    ext:close()
    openssl({
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        dir .. '/intermediate.key',
        '-out',
        dir .. '/intermediate.csr',
        '-subj',
        '/CN=ClientIntermediate',
    })
    openssl({
        'x509',
        '-req',
        '-in',
        dir .. '/intermediate.csr',
        '-CA',
        dir .. '/ca.crt',
        '-CAkey',
        dir .. '/ca.key',
        '-CAcreateserial',
        '-days',
        '1',
        '-extfile',
        dir .. '/intermediate.ext',
        '-out',
        dir .. '/intermediate.crt',
    })
    openssl({
        'x509',
        '-req',
        '-in',
        dir .. '/client.csr',
        '-CA',
        dir .. '/intermediate.crt',
        '-CAkey',
        dir .. '/intermediate.key',
        '-CAcreateserial',
        '-days',
        '1',
        '-out',
        dir .. '/client.crt',
    })
    local chain = assert(io.open(dir .. '/client-chain.pem', 'w'))
    for _, name in ipairs({
        'client.crt',
        'intermediate.crt',
    }) do
        local file = assert(io.open(dir .. '/' .. name))
        chain:write(file:read('*a'))
        file:close()
    end
    chain:close()
end

return {
    server_certificate = server_certificate,
    client_certificate = client_certificate,
    client_certificate_chain = client_certificate_chain,
}
