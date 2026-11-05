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
local CRLS

function testcase.before_all()
    DIR = os.tmpname()
    os.remove(DIR)
    assert(mkdir(DIR, '0700'))
    CRLS = fixtures.crl_certificates(DIR)
end

function testcase.after_all()
    if DIR then
        assert(rmdir(DIR, true))
    end
end

local function new_server(family, crls)
    local cfg = {
        cert = DIR .. '/server.crt',
        key = DIR .. '/server.key',
        cafile = DIR .. '/ca.crt',
        verify_mode = 'require',
        crls = crls,
    }
    if family == 'inet' then
        return inet.server.new('127.0.0.1', 0, {
            tlscfg = cfg,
        })
    end
    return unix.server.new(DIR .. '/socket', cfg)
end

function testcase.stream_servers_reject_zero_crls_before_binding()
    for _, family in ipairs({
        'inet',
        'unix',
    }) do
        local listener, err = new_server(family, '')
        if listener then
            listener:close()
        end
        assert.is_nil(listener)
        assert.not_nil(err)
        assert.match(tostring(err), 'no CRL loaded', true)
    end
end

local function exchange(family, revoked)
    local listener = assert(new_server(family, revoked and CRLS.revoked_crl or
                                           CRLS.empty_crl))
    assert(listener:listen())
    local destination = family == 'inet' and
                            assert(listener:getsockname()):port() or DIR ..
                            '/socket'
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            listener:close()
            local opts = {
                servername = 'localhost',
                tlscfg = {
                    cert = DIR .. '/server.crt',
                    key = DIR .. '/server.key',
                    cafile = DIR .. '/ca.crt',
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
            local sent, err = sock:write('client-certificate')
            if revoked then
                if sent then
                    local reply, rerr = sock:read()
                    assert.is_nil(reply)
                    assert.not_nil(rerr)
                else
                    assert.not_nil(err)
                end
            else
                assert(sent, err)
                assert.equal(sock:read(), 'accepted')
            end
            sock:close()
        end)
    end
    local peer
    local ok, err = pcall(function()
        peer = assert(listener:accept(nil, 5))
        assert(peer:rcvtimeo(5))
        assert(peer:sndtimeo(5))
        local data, rerr = peer:read()
        if revoked then
            assert.is_nil(data)
            assert.not_nil(rerr)
        else
            assert.equal(data, 'client-certificate')
            assert.is_nil(rerr)
            assert.is_true(peer:get_verify_result())
            assert(peer:write('accepted'))
        end
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

function testcase.inet_server_crls_checks_client_certificate()
    exchange('inet', false)
    exchange('inet', true)
end

function testcase.unix_server_crls_checks_client_certificate()
    exchange('unix', false)
    exchange('unix', true)
end
