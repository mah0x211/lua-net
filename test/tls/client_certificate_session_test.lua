local testcase = require('testcase')
local assert = require('assert')
local exec = require('exec').execvp
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local socket = require('net.socket')
local inet = require('net.stream.inet')
local new_cache = require('net.tls.cache')
local fixtures = require('test.tls.cert_fixtures')

local DIR
local PROC

local function readfile(path)
    local file = assert(io.open(path))
    local value = assert(file:read('*a'))
    file:close()
    return value
end

function testcase.before_all()
    DIR = os.tmpname()
    os.remove(DIR)
    for _, name in ipairs({
        'a',
        'b',
    }) do
        local dir = DIR .. '/' .. name
        assert(mkdir(dir, '0700', true))
        fixtures.client_certificate(dir)
    end
    fixtures.server_certificate(DIR .. '/server.crt', DIR .. '/server.key')
    local ca = assert(io.open(DIR .. '/trusted-ca.pem', 'w'))
    ca:write(readfile(DIR .. '/a/ca.crt'), readfile(DIR .. '/b/ca.crt'))
    ca:close()
end

function testcase.after_each()
    if PROC then
        PROC:close(0.1)
        PROC = nil
    end
end

function testcase.after_all()
    if DIR then
        assert(rmdir(DIR, true))
    end
end

function testcase.client_sessions_resume_only_for_the_same_certificate()
    for _, protocol in ipairs({
        'tlsv1.2',
        'tlsv1.3',
    }) do
        local sock = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
        }))
        local port = assert(sock:getsockname()):port()
        sock:close()
        PROC = assert(exec('openssl', {
            's_server',
            '-accept',
            '127.0.0.1:' .. port,
            '-cert',
            DIR .. '/server.crt',
            '-key',
            DIR .. '/server.key',
            '-CAfile',
            DIR .. '/trusted-ca.pem',
            '-verify',
            '3',
            '-verify_return_error',
            '-www',
            '-naccept',
            '7',
            protocol == 'tlsv1.2' and '-tls1_2' or '-tls1_3',
        }))
        PROC.stdout:set_timeout(5)
        local ready = false
        for line in PROC.stdout:lines() do
            if line == 'ACCEPT' then
                ready = true;
                break
            end
        end
        assert.is_true(ready)
        local cache = new_cache({
            ctx_capacity = 4,
            session_capacity = 2,
        })
        for _, case in ipairs({
            {
                'a',
                false,
            },
            {
                'a',
                true,
            },
            {
                'b',
                false,
            },
            {
                'b',
                true,
            },
            {
                false,
                false,
            },
            {
                false,
                true,
            },
            {
                'a',
                true,
            },
        }) do
            local cfg = {
                cache = cache,
                protocol = protocol,
                cafile = DIR .. '/server.crt',
            }
            if case[1] then
                cfg.cert = DIR .. '/' .. case[1] .. '/client.crt'
                cfg.key = DIR .. '/' .. case[1] .. '/client.key'
            end
            local peer = assert(inet.client.new('127.0.0.1', port, {
                servername = 'www.example.com',
                tlscfg = cfg,
            }))
            peer:rcvtimeo(5)
            peer:sndtimeo(5)
            local ok, err = pcall(function()
                assert(peer:write('GET / HTTP/1.0\r\n\r\n'))
                local chunks = {}
                while true do
                    local data, rerr, timeout = peer:read()
                    assert.is_nil(rerr)
                    assert.is_nil(timeout)
                    if not data then
                        break
                    end
                    chunks[#chunks + 1] = data
                end
                local response = table.concat(chunks)
                -- s_server reports SSL_session_reused() and the authenticated
                -- peer certificate in its real HTTP response.
                local reused = response:find('\nReused, ', 1, true) ~= nil
                assert.equal(reused, case[2])
                if case[1] then
                    assert.match(response, readfile(cfg.cert), true)
                else
                    assert.match(response, 'no client certificate available',
                                 true)
                end
            end)
            peer:close()
            assert(ok, err)
        end
        assert.equal(assert(PROC:close(5)).exit, 0)
        PROC = nil
    end
end
