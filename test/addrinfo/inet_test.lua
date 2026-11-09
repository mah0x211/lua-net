local testcase = require('testcase')
local assert = require('assert')
local addrinfo = require('net.addrinfo')


function testcase.inet()
    -- Create an IPv4 addrinfo with the default options: socktype = 0,
    -- protocol = 0, no flags, no canonname.  addrinfo:family/addr/port/
    -- socktype/protocol/canonname all return the expected defaults.
    local ai = assert(addrinfo.inet('127.0.0.1', 8080))
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert.equal(ai:family(), 'inet')
    assert.equal(ai:addr(), '127.0.0.1')
    assert.equal(ai:port(), 8080)
    assert.equal(ai:socktype(), 'unspec')
    assert.equal(ai:protocol(), 'auto')
    assert.is_nil(ai:canonname())
end

function testcase.inet_wildcard()
    -- addrinfo.inet() with no arguments returns the IPv4 wildcard (0.0.0.0:0).
    local ai = assert(addrinfo.inet())
    assert.equal(ai:addr(), '0.0.0.0')
    assert.equal(ai:port(), 0)
end

function testcase.inet_opts_socktype_protocol()
    -- opts.socktype and opts.protocol are applied to the resulting
    -- addrinfo (both the stream/tcp and dgram/udp forms).
    local ai = assert(addrinfo.inet('127.0.0.1', 80, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:socktype(), 'stream')
    assert.equal(ai:protocol(), 'tcp')

    ai = assert(addrinfo.inet('127.0.0.1', 53, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(ai:socktype(), 'dgram')
    assert.equal(ai:protocol(), 'udp')
end

function testcase.inet_invalid_address()
    -- An address that inet_pton() cannot parse returns an error object.
    local ai, err = addrinfo.inet('not.an.ip.address', 0)
    assert.is_nil(ai)
    assert(err, 'expected error for invalid IPv4 address')
end

function testcase.inet_rejects_embedded_nul_address()
    for _, address in ipairs({
        '127.0.0.1\0unexpected',
        '\000127.0.0.1',
        '127.0.0.1\0',
        '\0',
    }) do
        local err = assert.throws(function()
            addrinfo.inet(address, 80)
        end)
        assert.match(err, 'bad argument #1')
        assert.match(err, 'NUL')
    end
end

function testcase.inet_invalid_socktype()
    -- opts.socktype must be one of the recognized symbolic names.
    local err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            socktype = 'bogus',
        })
    end)
    assert.match(err, 'socktype', false)
end

function testcase.inet_invalid_protocol()
    -- opts.protocol must be one of the recognized symbolic names.
    local err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            protocol = 'bogus',
        })
    end)
    assert.match(err, 'protocol', false)
end

function testcase.inet_invalid_flags()
    -- opts.flags is an array of strings where every element must be a
    -- recognized AI_* flag name.
    local err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            flags = {
                'passive',
                'bogus',
            },
        })
    end)
    assert.match(err, 'flags', false)
end

function testcase.inet_ignores_unknown_opts()
    -- Unknown opts keys are silently ignored so that callers can pass a
    -- superset of options without a check-per-key roundtrip.
    local ai = assert(addrinfo.inet('127.0.0.1', 0, {
        typo_option = true,
    }))
    assert.equal(ai:family(), 'inet')
end

function testcase.inet_opts_must_be_table()
    -- opts, if provided, must be a Lua table.
    local err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, 'not-a-table')
    end)
    assert.match(err, 'opts', false)
end

function testcase.inet6()
    -- Create an IPv6 addrinfo with the default options.
    local ai = assert(addrinfo.inet6('::1', 8080))
    assert.equal(ai:family(), 'inet6')
    assert.equal(ai:addr(), '::1')
    assert.equal(ai:port(), 8080)
end

function testcase.inet6_wildcard()
    -- addrinfo.inet6() with no arguments returns the IPv6 wildcard (::0).
    local ai = assert(addrinfo.inet6())
    assert.equal(ai:addr(), '::')
    assert.equal(ai:port(), 0)
end

function testcase.inet6_opts_socktype_protocol()
    -- opts.socktype and opts.protocol are applied to the resulting IPv6
    -- addrinfo (both the stream/tcp and dgram/udp forms).
    local ai = assert(addrinfo.inet6('::1', 80, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:socktype(), 'stream')
    assert.equal(ai:protocol(), 'tcp')

    ai = assert(addrinfo.inet6('::1', 53, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(ai:socktype(), 'dgram')
    assert.equal(ai:protocol(), 'udp')
end

function testcase.inet6_invalid_address()
    -- An address that inet_pton() cannot parse returns an error object.
    local ai, err = addrinfo.inet6('not.an.ip6', 0)
    assert.is_nil(ai)
    assert(err, 'expected error for invalid IPv6 address')
end

function testcase.inet6_rejects_embedded_nul_address()
    for _, address in ipairs({
        '::1\0unexpected',
        '\0::1',
        '::1\0',
        '\0',
    }) do
        local err = assert.throws(function()
            addrinfo.inet6(address, 80)
        end)
        assert.match(err, 'bad argument #1')
        assert.match(err, 'NUL')
    end
end

function testcase.inet_passive_must_be_boolean()
    -- opts.passive must be a boolean; non-boolean values raise a Lua error.
    local err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            passive = 1,
        })
    end)
    assert.match(err, 'passive', false)
end
