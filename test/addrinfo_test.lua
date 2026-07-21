require('luacov')
local testcase = require('testcase')
local errno = require('errno')
local errno_eai = require('errno.eai')
local net = require('net')
local addrinfo = require('net.addrinfo')

--
-- helper
--
local function tmpsock()
    return os.tmpname()
end

local UNIX_PATH_MAX = 104
-- discover the real limit at runtime; different platforms differ (macOS
-- reserves 104 bytes for sun_path, Linux 108).  Try a length that fits in
-- Linux's sun_path but overflows macOS's to disambiguate.
do
    local _, err = addrinfo.unix(string.rep('x', 107))
    if not err then
        UNIX_PATH_MAX = 108
    end
end

--
-- low-level: addrinfo.inet
--
function testcase.inet()
    -- test that create IPv4 addrinfo with default options
    local ai = assert(addrinfo.inet('127.0.0.1', 8080))
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert.equal(ai:family(), net.AF_INET)
    assert.equal(ai:addr(), '127.0.0.1')
    assert.equal(ai:port(), 8080)
    assert.equal(ai:socktype(), 0)
    assert.equal(ai:protocol(), 0)
    assert.is_nil(ai:canonname())

    -- test that address and port are optional (wildcard)
    ai = assert(addrinfo.inet())
    assert.equal(ai:addr(), '0.0.0.0')
    assert.equal(ai:port(), 0)

    -- test that opts.socktype and opts.protocol are applied
    ai = assert(addrinfo.inet('127.0.0.1', 80, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:socktype(), net.SOCK_STREAM)
    assert.equal(ai:protocol(), net.IPPROTO_TCP)

    -- test that opts.socktype = 'dgram' + protocol = 'udp' works
    ai = assert(addrinfo.inet('127.0.0.1', 53, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(ai:socktype(), net.SOCK_DGRAM)
    assert.equal(ai:protocol(), net.IPPROTO_UDP)

    -- test that invalid IPv4 address returns error
    local _, err = addrinfo.inet('not.an.ip.address', 0)
    assert(err, 'expected error for invalid IPv4 address')

    -- test that opts.socktype must be a known enum
    err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            socktype = 'bogus',
        })
    end)
    assert.match(err, 'socktype', false)

    -- test that opts.protocol must be a known enum
    err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            protocol = 'bogus',
        })
    end)
    assert.match(err, 'protocol', false)

    -- test that opts.flags must be an array of known strings
    err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            flags = {
                'passive',
                'bogus',
            },
        })
    end)
    assert.match(err, 'flags', false)

    -- test that unknown opts key throws an error
    err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            typo_option = true,
        })
    end)
    assert.match(err, 'typo_option', false)

    -- test that opts must be a table
    err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, 'not-a-table')
    end)
    assert.match(err, 'opts', false)
end

--
-- low-level: addrinfo.inet6
--
function testcase.inet6()
    -- test that create IPv6 addrinfo with default options
    local ai = assert(addrinfo.inet6('::1', 8080))
    assert.equal(ai:family(), net.AF_INET6)
    assert.equal(ai:addr(), '::1')
    assert.equal(ai:port(), 8080)

    -- test that address and port are optional (wildcard)
    ai = assert(addrinfo.inet6())
    assert.equal(ai:addr(), '::')
    assert.equal(ai:port(), 0)

    -- test that opts.socktype = 'stream' + protocol = 'tcp' works
    ai = assert(addrinfo.inet6('::1', 80, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:socktype(), net.SOCK_STREAM)
    assert.equal(ai:protocol(), net.IPPROTO_TCP)

    -- test that invalid IPv6 address returns error
    local _, err = addrinfo.inet6('not.an.ip6', 0)
    assert(err, 'expected error for invalid IPv6 address')
end

--
-- low-level: addrinfo.unix
--
function testcase.unix()
    local path = tmpsock()

    -- test that create AF_UNIX addrinfo from a pathname
    local ai = assert(addrinfo.unix(path))
    assert.equal(ai:family(), net.AF_UNIX)
    assert.equal(ai:addr(), path)
    assert.is_nil(ai:port())
    assert.equal(ai:socktype(), 0)
    assert.equal(ai:protocol(), 0)

    -- test that opts.socktype = 'stream' works
    ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    assert.equal(ai:socktype(), net.SOCK_STREAM)

    -- test that a pathname that exceeds sun_path length returns ENAMETOOLONG
    local long = string.rep('x', UNIX_PATH_MAX + 1)
    local _, err = addrinfo.unix(long)
    assert.equal(err.type, errno.ENAMETOOLONG)

    -- test that pathname is required
    err = assert.throws(function()
        addrinfo.unix()
    end)
    assert.match(err, 'string expected', false)
end

--
-- getaddrinfo
--
function testcase.getaddrinfo()
    -- test that resolves 127.0.0.1 to an IPv4 addrinfo list
    local addrs = assert(addrinfo.getaddrinfo('127.0.0.1', 0, {
        family = 'inet',
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.greater(#addrs, 0)
    for _, ai in ipairs(addrs) do
        assert.equal(ai:family(), net.AF_INET)
        assert.equal(ai:socktype(), net.SOCK_STREAM)
        assert.equal(ai:protocol(), net.IPPROTO_TCP)
    end

    -- test that AI_PASSIVE flag returns wildcard when host is nil
    addrs = assert(addrinfo.getaddrinfo(nil, 0, {
        family = 'inet',
        socktype = 'stream',
        flags = {
            'passive',
        },
    }))
    assert.equal(addrs[1]:addr(), '0.0.0.0')

    -- test that unresolvable hostname returns EAI_NONAME
    local _, err = addrinfo.getaddrinfo('invalid.host.example.invalid', 0)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_NONAME)

    -- test that non-integer port returns EAI_SERVICE
    _, err = addrinfo.getaddrinfo('127.0.0.1', 'invalid-service')
    assert(err)
    assert(err.type == errno_eai.EAI_SERVICE or err.type == errno_eai.EAI_NONAME)

    -- test that unknown enum value in opts.family throws
    err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            family = 'bogus',
        })
    end)
    assert.match(err, 'family', false)

    -- test that unknown opts key throws
    err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            typo = 1,
        })
    end)
    assert.match(err, 'typo', false)
end

--
-- inet with socktype/protocol/passive/canonname opts
--
function testcase.inet_typed_convenience()
    -- test that opts.socktype + opts.protocol produce a TCP stream addrinfo
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:family(), net.AF_INET)
    assert.equal(ai:socktype(), net.SOCK_STREAM)
    assert.equal(ai:protocol(), net.IPPROTO_TCP)
    assert.equal(ai:addr(), '127.0.0.1')
    assert.equal(ai:port(), 8080)

    -- test that opts.passive OR's AI_PASSIVE into the wildcard addrinfo
    ai = assert(addrinfo.inet(nil, 0, {
        socktype = 'stream',
        protocol = 'tcp',
        passive = true,
    }))
    assert.equal(ai:addr(), '0.0.0.0')

    -- test that opts.passive must be boolean
    local err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            passive = 1,
        })
    end)
    assert.match(err, 'passive', false)

    -- test that opts.socktype = 'dgram' + protocol = 'udp' works
    ai = assert(addrinfo.inet('127.0.0.1', 53, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(ai:socktype(), net.SOCK_DGRAM)
    assert.equal(ai:protocol(), net.IPPROTO_UDP)
end

--
-- inet6 with socktype/protocol opts
--
function testcase.inet6_typed_convenience()
    -- test that opts produce a TCP IPv6 stream addrinfo
    local ai = assert(addrinfo.inet6('::1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:family(), net.AF_INET6)
    assert.equal(ai:socktype(), net.SOCK_STREAM)
    assert.equal(ai:protocol(), net.IPPROTO_TCP)
    assert.equal(ai:addr(), '::1')
    assert.equal(ai:port(), 8080)

    -- test that opts.socktype = 'dgram' + protocol = 'udp' works
    ai = assert(addrinfo.inet6('::1', 53, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(ai:socktype(), net.SOCK_DGRAM)
    assert.equal(ai:protocol(), net.IPPROTO_UDP)
end

--
-- unix with socktype opts
--
function testcase.unix_typed_convenience()
    local path = tmpsock()

    -- test that opts.socktype = 'stream' works
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    assert.equal(ai:family(), net.AF_UNIX)
    assert.equal(ai:socktype(), net.SOCK_STREAM)
    assert.equal(ai:addr(), path)

    -- test that opts.socktype = 'dgram' works
    ai = assert(addrinfo.unix(path, {
        socktype = 'dgram',
    }))
    assert.equal(ai:socktype(), net.SOCK_DGRAM)

    -- test that ENAMETOOLONG is returned for too long pathname
    local _, err = addrinfo.unix(string.rep('x', UNIX_PATH_MAX + 1), {
        socktype = 'stream',
    })
    assert.equal(err.type, errno.ENAMETOOLONG)
end

--
-- getaddrinfo with passive/canonname boolean shortcuts
--
function testcase.getaddrinfo_boolean_shortcuts()
    -- test that opts.passive is honored as an AI_PASSIVE shortcut
    local addrs = assert(addrinfo.getaddrinfo(nil, 0, {
        family = 'inet',
        socktype = 'stream',
        passive = true,
    }))
    assert.greater(#addrs, 0)

    -- test that opts.passive must be boolean
    local err = assert.throws(function()
        addrinfo.getaddrinfo(nil, 0, {
            passive = 'yes',
        })
    end)
    assert.match(err, 'passive', false)

    -- test that opts.canonname must be boolean
    err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            canonname = 1,
        })
    end)
    assert.match(err, 'canonname', false)
end

--
-- methods
--
function testcase.methods()
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))

    -- test that family() returns AF_INET
    assert.equal(ai:family(), net.AF_INET)
    -- test that socktype() returns SOCK_STREAM
    assert.equal(ai:socktype(), net.SOCK_STREAM)
    -- test that protocol() returns IPPROTO_TCP
    assert.equal(ai:protocol(), net.IPPROTO_TCP)
    -- test that addr() returns the string form of the address
    assert.equal(ai:addr(), '127.0.0.1')
    -- test that port() returns the integer port
    assert.equal(ai:port(), 8080)
    -- test that canonname() is nil when not requested
    assert.is_nil(ai:canonname())
    -- test that tostring embeds the metatable name
    assert.match(tostring(ai), '^net.addrinfo: ', false)

    -- test that canonname() is populated when requested
    local addrs = assert(addrinfo.getaddrinfo('localhost', 0, {
        family = 'inet',
        socktype = 'stream',
        flags = {
            'canonname',
        },
    }))
    assert.is_string(addrs[1]:canonname())
end

--
-- ai:getnameinfo
--
function testcase.getnameinfo()
    local ai = assert(addrinfo.inet('127.0.0.1', 22, {
        socktype = 'stream',
        protocol = 'tcp',
    }))

    -- test that returns {host, service} table without flags
    local info = assert(ai:getnameinfo())
    assert.is_string(info.host)
    assert.is_string(info.service)

    -- test that numerichost / numericserv flags return literal values
    info = assert(ai:getnameinfo('numerichost', 'numericserv'))
    assert.equal(info.host, '127.0.0.1')
    assert.equal(info.service, '22')

    -- test that invalid flag string is rejected
    local err = assert.throws(function()
        ai:getnameinfo('bogus')
    end)
    assert.match(err, 'bogus', false)
end

--
-- unix family does not expose port
--
function testcase.unix_port_is_nil()
    local ai = assert(addrinfo.unix(tmpsock(), {
        socktype = 'stream',
    }))
    assert.is_nil(ai:port())
end

--
-- flags array and boolean shortcuts must combine, not clobber
--
function testcase.flags_combine_with_booleans()
    -- passive shortcut + flags array set at the same time; independent of
    -- Lua's undefined key enumeration order the final ai_flags must include
    -- both AI_PASSIVE (from opts.passive) and AI_NUMERICHOST (from
    -- opts.flags).  On Linux getaddrinfo(NULL, ...) without AI_PASSIVE
    -- fails with EAI_NONAME, so a successful call with nil host proves
    -- that AI_PASSIVE survived even when the flags array was also
    -- processed.  Loop several times because lua_next enumeration order
    -- for string keys is unspecified.
    for _ = 1, 10 do
        local addrs = assert(addrinfo.getaddrinfo(nil, 0, {
            family = 'inet',
            socktype = 'stream',
            passive = true,
            flags = {
                'numerichost',
            },
        }))
        assert.greater(#addrs, 0)
        assert.equal(addrs[1]:addr(), '0.0.0.0')
    end
end

--
-- opts validation edge cases
--
function testcase.opts_type_errors()
    -- test that opts.family must be a string
    local err = assert.throws(function()
        addrinfo.getaddrinfo('127.0.0.1', 0, {
            family = 4,
        })
    end)
    assert.match(err, 'family', false)

    -- test that opts.flags must be a table
    err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            flags = 'passive',
        })
    end)
    assert.match(err, 'flags', false)

    -- test that opts.flags element must be a string
    err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            flags = {
                1,
            },
        })
    end)
    assert.match(err, 'flags', false)

    -- test that opts key must be a string (numeric-index keys rejected)
    err = assert.throws(function()
        addrinfo.inet('127.0.0.1', 0, {
            'passive',
        })
    end)
    assert.match(err, 'opts', false)
end

--
-- port variants
--
function testcase.port_variants()
    -- test that string port is accepted
    local addrs = assert(addrinfo.getaddrinfo('127.0.0.1', '80', {
        family = 'inet',
        socktype = 'stream',
    }))
    assert.equal(addrs[1]:port(), 80)

    -- test that negative port is rejected
    local _, err = addrinfo.getaddrinfo('127.0.0.1', -1)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_SERVICE)

    -- test that port exceeding UINT16_MAX is rejected
    _, err = addrinfo.getaddrinfo('127.0.0.1', 65536)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_SERVICE)

    -- test that non-integer port number is rejected
    _, err = addrinfo.getaddrinfo('127.0.0.1', 1.5)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_SERVICE)

    -- test that boolean port is rejected
    _, err = addrinfo.getaddrinfo('127.0.0.1', true)
    assert(err)
    assert.equal(err.type, errno_eai.EAI_SERVICE)
end
