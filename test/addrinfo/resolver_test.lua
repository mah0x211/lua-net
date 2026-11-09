local testcase = require('testcase')
local assert = require('assert')
local errno_eai = require('errno.eai')
local addrinfo = require('net.addrinfo')


function testcase.getaddrinfo()
    -- Resolve 127.0.0.1 (a literal IPv4) into a list of matching
    -- addrinfo entries.  All entries should carry the family / socktype /
    -- protocol we requested through opts.
    local addrs = assert(addrinfo.getaddrinfo('127.0.0.1', 0, {
        family = 'inet',
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.greater(#addrs, 0)
    for _, ai in ipairs(addrs) do
        assert.equal(ai:family(), 'inet')
        assert.equal(ai:socktype(), 'stream')
        assert.equal(ai:protocol(), 'tcp')
    end
end

function testcase.getaddrinfo_passive_wildcard()
    -- opts.flags = {'passive'} + host = nil produces the wildcard
    -- addrinfo (0.0.0.0 for IPv4).
    local addrs = assert(addrinfo.getaddrinfo(nil, 0, {
        family = 'inet',
        socktype = 'stream',
        flags = {
            'passive',
        },
    }))
    assert.equal(addrs[1]:addr(), '0.0.0.0')
end

function testcase.getaddrinfo_unresolvable_host()
    -- An unresolvable hostname surfaces EAI_NONAME.  A single DNS label
    -- is limited to 63 octets, so a longer one cannot be encoded on the
    -- wire and the resolver library rejects it locally before any query
    -- leaves the host; this keeps the failure deterministic even behind
    -- a wildcard resolver, which would answer for a nonexistent but
    -- well-formed name.
    local ai, err = addrinfo.getaddrinfo(string.rep('a', 64), 0)
    assert.is_nil(ai)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_NONAME)
end

function testcase.getaddrinfo_invalid_service()
    -- A non-numeric port that is not a known service name surfaces
    -- EAI_SERVICE (or EAI_NONAME on some platforms).
    local ai, err = addrinfo.getaddrinfo('127.0.0.1', 'invalid-service')
    assert.is_nil(ai)
    assert(err)
    assert(err.type == errno_eai.EAI_SERVICE or err.type == errno_eai.EAI_NONAME)
end

function testcase.getaddrinfo_rejects_embedded_nul_host()
    for _, host in ipairs({
        '127.0.0.1\0unexpected',
        '\000127.0.0.1',
        '127.0.0.1\0',
        '\0',
    }) do
        local err = assert.throws(function()
            addrinfo.getaddrinfo(host, 80, {
                family = 'inet',
                socktype = 'stream',
                flags = {
                    'numerichost',
                },
            })
        end)
        assert.match(err, 'bad argument #1')
        assert.match(err, 'NUL')
    end
end

function testcase.getaddrinfo_rejects_embedded_nul_service()
    for _, service in ipairs({
        '80\0unexpected',
        '\00080',
        '80\0',
        '\0',
        'http\0unexpected',
        'http\0',
    }) do
        local err = assert.throws(function()
            addrinfo.getaddrinfo('127.0.0.1', service, {
                family = 'inet',
                socktype = 'stream',
                flags = {
                    'numerichost',
                },
            })
        end)
        assert.match(err, 'bad argument #2')
        assert.match(err, 'NUL')
    end
end

function testcase.getaddrinfo_invalid_family()
    -- opts.family must be one of the recognized symbolic names.
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            family = 'bogus',
        })
    end)
    assert.match(err, 'family', false)
end

function testcase.getaddrinfo_ignores_unknown_opts()
    -- Unknown opts keys are silently ignored.
    local addrs = assert(addrinfo.getaddrinfo('127.0.0.1', 0, {
        typo = 1,
    }))
    assert.greater(#addrs, 0)
end

function testcase.getaddrinfo_boolean_shortcuts_passive()
    -- opts.passive is honored as an AI_PASSIVE shortcut on getaddrinfo().
    local addrs = assert(addrinfo.getaddrinfo(nil, 0, {
        family = 'inet',
        socktype = 'stream',
        passive = true,
    }))
    assert.greater(#addrs, 0)
    for _, ai in ipairs(addrs) do
        assert.equal(ai:addr(), '0.0.0.0')
    end
end

function testcase.getaddrinfo_boolean_shortcuts_canonname()
    -- opts.canonname returns a canonical name on the first result.
    local addrs = assert(addrinfo.getaddrinfo('localhost', 0, {
        family = 'inet',
        socktype = 'stream',
        canonname = true,
    }))
    assert.greater(#addrs, 0)
    assert.not_equal(assert.is_string(addrs[1]:canonname()), '')
end

function testcase.getaddrinfo_passive_must_be_boolean()
    -- opts.passive must be a boolean.
    local err = assert.throws(function()
        addrinfo.getaddrinfo(nil, 0, {
            passive = 'yes',
        })
    end)
    assert.match(err, 'passive', false)
end

function testcase.getaddrinfo_canonname_must_be_boolean()
    -- opts.canonname must be a boolean.
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            canonname = 1,
        })
    end)
    assert.match(err, 'canonname', false)
end

function testcase.canonname()
    -- canonname() returns the canonical hostname when 'canonname' is
    -- included in opts.flags via getaddrinfo().
    local addrs = assert(addrinfo.getaddrinfo('localhost', 0, {
        family = 'inet',
        socktype = 'stream',
        flags = {
            'canonname',
        },
    }))
    assert.is_string(addrs[1]:canonname())
end

function testcase.getnameinfo()
    -- ai:getnameinfo() with no flags reverses the addrinfo into a
    -- {host, service} table via getnameinfo(3).
    local ai = assert(addrinfo.inet('127.0.0.1', 22, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local info = assert(ai:getnameinfo())
    assert.is_string(info.host)
    assert.is_string(info.service)
end

function testcase.getnameinfo_numeric_flags()
    -- 'numerichost' + 'numericserv' bypass reverse DNS / service lookup
    -- and return the literal address and port.
    local ai = assert(addrinfo.inet('127.0.0.1', 22, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local info = assert(ai:getnameinfo('numerichost', 'numericserv'))
    assert.equal(info.host, '127.0.0.1')
    assert.equal(info.service, '22')
end

function testcase.getnameinfo_invalid_flag_string()
    -- An unknown flag name surfaces a Lua error identifying the offending
    -- string.
    local ai = assert(addrinfo.inet('127.0.0.1', 22, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local err = assert.throws(function()
        ai:getnameinfo('bogus')
    end)
    assert.match(err, 'bogus', false)
end

function testcase.flags_combine_with_booleans()
    -- With both options set, nil host selects the wildcard and a hostname
    -- is rejected rather than resolved.
    local opts = {
        family = 'inet',
        socktype = 'stream',
        passive = true,
        flags = {
            'numerichost',
        },
    }
    local addrs = assert(addrinfo.getaddrinfo(nil, 0, opts))
    assert.greater(#addrs, 0)
    for _, ai in ipairs(addrs) do
        assert.equal(ai:addr(), '0.0.0.0')
    end

    local result, err = addrinfo.getaddrinfo('localhost', 0, opts)
    assert.is_nil(result)
    assert.equal(assert(err).type, errno_eai.EAI_NONAME)
end

function testcase.opts_family_must_be_string()
    -- opts.family must be a string; a non-string value raises a Lua error.
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            family = 4,
        })
    end)
    assert.match(err, 'family', false)
end

function testcase.opts_flags_must_be_table()
    -- opts.flags must be a table (an array of AI_* flag names).
    local err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            flags = 'passive',
        })
    end)
    assert.match(err, 'flags', false)
end

function testcase.opts_flags_element_must_be_string()
    -- Each entry inside opts.flags must be a string.
    local err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            flags = {
                1,
            },
        })
    end)
    assert.match(err, 'flags', false)
end

function testcase.opts_numeric_index_keys_rejected()
    -- opts keys must all be strings; array-style (numeric-index) entries
    -- are rejected.
    local err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            'passive',
        })
    end)
    assert.match(err, 'opts', false)
end

function testcase.opts_socktype_invalid_string()
    -- An unrecognized opts.socktype string surfaces a diagnostic Lua
    -- error via check_socktype.
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            socktype = 'invalid',
        })
    end)
    assert.match(err, 'socktype', false)
    assert.match(err, 'invalid', false)
end

function testcase.opts_protocol_invalid_string()
    -- An unrecognized opts.protocol string surfaces a diagnostic Lua
    -- error via check_protocol.
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            protocol = 'invalid',
        })
    end)
    assert.match(err, 'protocol', false)
    assert.match(err, 'invalid', false)
end

function testcase.opts_socktype_must_be_string()
    -- opts.socktype must be a string.
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            socktype = 123,
        })
    end)
    assert.match(err, 'socktype', false)
    assert.match(err, 'string', false)
end

function testcase.opts_protocol_must_be_string()
    -- opts.protocol must be a string.
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            protocol = 123,
        })
    end)
    assert.match(err, 'protocol', false)
    assert.match(err, 'string', false)
end

function testcase.opts_passive_must_be_boolean()
    -- opts.passive must be a boolean.
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            passive = 'notbool',
        })
    end)
    assert.match(err, 'passive', false)
end

function testcase.opts_canonname_must_be_boolean()
    -- opts.canonname must be a boolean.
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            canonname = 123,
        })
    end)
    assert.match(err, 'canonname', false)
end

function testcase.getnameinfo_flag_must_be_string()
    -- ai:getnameinfo() flag arguments must be strings.
    local ai = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'stream',
    }))
    local err = assert.throws(function()
        ai:getnameinfo(123)
    end)
    assert.match(err, 'must be string', false)
end

function testcase.getnameinfo_unknown_flag()
    -- ai:getnameinfo() rejects flag names outside the recognized set.
    local ai = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'stream',
    }))
    local err = assert.throws(function()
        ai:getnameinfo('unknown_flag')
    end)
    assert.match(err, 'invalid flag', false)
end

function testcase.getnameinfo_rejects_conflicting_host_flags()
    -- NUMERICHOST disables lookup while NAMEREQD forbids numeric fallback.
    -- NUMERICSERV also avoids service lookup.
    local ai = assert(addrinfo.inet('127.0.0.1', 80, {
        socktype = 'stream',
    }))
    local r, err = ai:getnameinfo('numerichost', 'namereqd', 'numericserv')
    assert.is_nil(r)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_NONAME)
end

function testcase.port_variants_string()
    -- getaddrinfo() accepts a string port (either numeric or a service
    -- name).  A numeric string is parsed as an integer port.
    local addrs = assert(addrinfo.getaddrinfo('127.0.0.1', '80', {
        family = 'inet',
        socktype = 'stream',
    }))
    assert.equal(addrs[1]:port(), 80)
end

function testcase.port_variants_negative()
    -- Negative port numbers are outside the uint16 range and surface
    -- EAI_SERVICE.
    local ai, err = addrinfo.getaddrinfo('127.0.0.1', -1)
    assert.is_nil(ai)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_SERVICE)
end

function testcase.port_variants_overflow()
    -- Port numbers > UINT16_MAX are outside the valid range.
    local ai, err = addrinfo.getaddrinfo('127.0.0.1', 65536)
    assert.is_nil(ai)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_SERVICE)
end

function testcase.port_variants_non_integer()
    -- Non-integer numeric ports (e.g. 1.5) are rejected because the
    -- underlying sockaddr port is a uint16.
    local ai, err = addrinfo.getaddrinfo('127.0.0.1', 1.5)
    assert.is_nil(ai)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_SERVICE)
end

function testcase.port_variants_boolean()
    -- Non-numeric / non-string port arguments (e.g. a boolean) are
    -- rejected by get_service()'s type dispatch.
    local ai, err = addrinfo.getaddrinfo('127.0.0.1', true)
    assert.is_nil(ai)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_SERVICE)
end

function testcase.port_variants_nil()
    -- A nil port is accepted (LUA_TNIL branch of get_service); the
    -- resulting addrinfo carries port = 0.
    local addrs = assert(addrinfo.getaddrinfo('127.0.0.1', nil, {
        family = 'inet',
        socktype = 'stream',
    }))
    assert.greater(#addrs, 0)
    for _, ai in ipairs(addrs) do
        assert.equal(ai:port(), 0)
    end
end

function testcase.port_variants_empty_string()
    -- An empty-string port is accepted via the LUA_TSTRING slen==0 branch
    -- of get_service (equivalent to nil).
    local addrs = assert(addrinfo.getaddrinfo('127.0.0.1', '', {
        family = 'inet',
        socktype = 'stream',
    }))
    assert.greater(#addrs, 0)
    for _, ai in ipairs(addrs) do
        assert.equal(ai:port(), 0)
    end
end

function testcase.getaddrinfo_flags_embedded_nul()
    -- a flag name containing an embedded NUL must not match "numerichost"
    local err = assert.throws(function()
        addrinfo.getaddrinfo('localhost', 0, {
            socktype = 'stream',
            flags = {
                'numerichost\0',
            },
        })
    end)
    assert.match(err, "invalid opts.flags[1] value")
end
