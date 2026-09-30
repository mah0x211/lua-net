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

return {
    server_certificate = server_certificate,
    client_certificate = client_certificate,
}
