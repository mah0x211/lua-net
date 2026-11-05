local testcase = require('testcase')
local assert = require('assert')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local mkdir = require('mkdir')
local rmdir = require('rmdir')
local inet = require('net.stream.inet')
local unix = require('net.stream.unix')
local fixtures = require('test.tls.cert_fixtures')

local DIR

function testcase.before_all()
    DIR = os.tmpname()
    os.remove(DIR)
    assert(mkdir(DIR, '0700'))
    fixtures.client_certificate_chain(DIR)
    fixtures.server_certificate(DIR .. '/server.crt', DIR .. '/server.key')
end

function testcase.after_all()
    if DIR then
        assert(rmdir(DIR, true))
    end
end

local function exchange(family)
    local cfg = {
        cert = DIR .. '/server.crt',
        key = DIR .. '/server.key',
        verify_mode = 'require',
        cafile = DIR .. '/ca.crt',
    }
    local listener
    local destination
    if family == 'inet' then
        listener = assert(inet.server.new('127.0.0.1', 0, {
            tlscfg = cfg,
        }))
        destination = assert(listener:getsockname()):port()
    else
        destination = DIR .. '/socket'
        listener = assert(unix.server.new(destination, cfg))
    end
    assert(listener:listen())
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            listener:close()
            local opts = {
                servername = 'www.example.com',
                tlscfg = {
                    cert = DIR .. '/client-chain.pem',
                    key = DIR .. '/client.key',
                    cafile = DIR .. '/server.crt',
                },
            }
            local sock
            if family == 'inet' then
                sock = assert(inet.client.new('127.0.0.1', destination, opts))
            else
                sock = assert(unix.client.new(destination, opts))
            end
            assert(sock:rcvtimeo(5))
            assert(sock:sndtimeo(5))
            assert(sock:write('client-certificate'))
            assert.equal(sock:read(), 'accepted')
            assert(sock:close())
        end)
    end
    local peer
    local ok, err = pcall(function()
        peer = assert(listener:accept(nil, 5))
        assert(peer:rcvtimeo(5))
        assert(peer:sndtimeo(5))
        assert.equal(peer:read(), 'client-certificate')
        assert.is_true(peer:get_verify_result())
        local cert = assert(io.open(DIR .. '/client.crt'))
        assert.equal(peer:get_peer_cert(), cert:read('*a'))
        cert:close()
        assert(peer:write('accepted'))
    end)
    if peer then
        peer:close()
    end
    listener:close()
    if family == 'unix' then
        os.remove(destination)
    end
    local res = assert(proc:wait())
    assert(ok, err)
    assert.equal(res.exit, 0)
end

function testcase.inet_client_sends_certificate_chain()
    exchange('inet')
end

function testcase.unix_client_sends_certificate_chain()
    exchange('unix')
end
