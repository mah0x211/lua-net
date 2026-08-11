require('luacov')
local testcase = require('testcase')
local errno = require('errno')
local errno_eai = require('errno.eai')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')

--
-- helper
--
local function tmpsock()
    return os.tmpname()
end

local function is_linux()
    -- luacov: disable
    local fp = io.open('/proc/version', 'r')
    if not fp then
        return false
    end
    local content = fp:read('*l')
    fp:close()
    return content and content:find('Linux', 1, true) ~= nil
    -- luacov: enable
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
    -- An address that inet_pton() cannot parse surfaces an EAI-style
    -- error object.
    local ai, err = addrinfo.inet('not.an.ip.address', 0)
    assert.is_nil(ai)
    assert(err, 'expected error for invalid IPv4 address')
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

--
-- low-level: addrinfo.inet6
--
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
    -- addrinfo.
    local ai = assert(addrinfo.inet6('::1', 80, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:socktype(), 'stream')
    assert.equal(ai:protocol(), 'tcp')
end

function testcase.inet6_invalid_address()
    -- An address that inet_pton() cannot parse surfaces an EAI-style
    -- error object.
    local ai, err = addrinfo.inet6('not.an.ip6', 0)
    assert.is_nil(ai)
    assert(err, 'expected error for invalid IPv6 address')
end

--
-- low-level: addrinfo.unix
--
function testcase.unix()
    -- Create an AF_UNIX addrinfo from a pathname.  addrinfo:family/addr
    -- reflect the "unix" family and the given path; port is nil because unix
    -- sockets do not have a port.  socktype and protocol use symbolic
    -- defaults.
    local path = tmpsock()
    local ai = assert(addrinfo.unix(path))
    assert.equal(ai:family(), 'unix')
    assert.equal(ai:addr(), path)
    assert.is_nil(ai:port())
    assert.equal(ai:socktype(), 'unspec')
    assert.equal(ai:protocol(), 'auto')
end

function testcase.unix_opts_socktype()
    -- opts.socktype is applied to the resulting AF_UNIX addrinfo.
    local path = tmpsock()
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    assert.equal(ai:socktype(), 'stream')
end

function testcase.unix_pathname_too_long()
    -- A pathname that exceeds sun_path length surfaces ENAMETOOLONG.
    local long = string.rep('x', UNIX_PATH_MAX + 1)
    local ai, err = addrinfo.unix(long)
    assert.is_nil(ai)
    assert.equal(err.type, errno.ENAMETOOLONG)
end

function testcase.unix_pathname_required()
    -- The pathname argument is required; omitting it raises a Lua error.
    local err = assert.throws(function()
        addrinfo.unix()
    end)
    assert.match(err, 'string expected', false)
end

--
-- getaddrinfo
--
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
    -- An unresolvable hostname surfaces EAI_NONAME.
    local ai, err = addrinfo.getaddrinfo('invalid.host.example.invalid', 0)
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

--
-- inet with socktype/protocol/passive/canonname opts
--
function testcase.inet_typed_convenience()
    -- opts.socktype + opts.protocol produce a fully-typed TCP stream
    -- addrinfo (family/addr/port/socktype/protocol all set).
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:family(), 'inet')
    assert.equal(ai:socktype(), 'stream')
    assert.equal(ai:protocol(), 'tcp')
    assert.equal(ai:addr(), '127.0.0.1')
    assert.equal(ai:port(), 8080)
end

function testcase.inet_passive_wildcard()
    -- opts.passive = true ORs AI_PASSIVE into the addrinfo flags; combined
    -- with host = nil this produces the IPv4 wildcard.
    local ai = assert(addrinfo.inet(nil, 0, {
        socktype = 'stream',
        protocol = 'tcp',
        passive = true,
    }))
    assert.equal(ai:addr(), '0.0.0.0')
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

function testcase.inet_typed_convenience_dgram()
    -- opts.socktype = 'dgram' + protocol = 'udp' produces a UDP dgram
    -- addrinfo.
    local ai = assert(addrinfo.inet('127.0.0.1', 53, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(ai:socktype(), 'dgram')
    assert.equal(ai:protocol(), 'udp')
end

function testcase.inet6_typed_convenience()
    -- opts produce a fully-typed TCP IPv6 stream addrinfo.
    local ai = assert(addrinfo.inet6('::1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:family(), 'inet6')
    assert.equal(ai:socktype(), 'stream')
    assert.equal(ai:protocol(), 'tcp')
    assert.equal(ai:addr(), '::1')
    assert.equal(ai:port(), 8080)
end

function testcase.inet6_typed_convenience_dgram()
    -- opts.socktype = 'dgram' + protocol = 'udp' works on IPv6 too.
    local ai = assert(addrinfo.inet6('::1', 53, {
        socktype = 'dgram',
        protocol = 'udp',
    }))
    assert.equal(ai:socktype(), 'dgram')
    assert.equal(ai:protocol(), 'udp')
end

--
-- unix with socktype opts
--
function testcase.unix_typed_convenience()
    -- opts.socktype = 'stream' produces a fully-typed AF_UNIX / SOCK_STREAM
    -- addrinfo.
    local path = tmpsock()
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    assert.equal(ai:family(), 'unix')
    assert.equal(ai:socktype(), 'stream')
    assert.equal(ai:addr(), path)
end

function testcase.unix_typed_convenience_dgram()
    -- opts.socktype = 'dgram' produces an AF_UNIX / SOCK_DGRAM addrinfo.
    local path = tmpsock()
    local ai = assert(addrinfo.unix(path, {
        socktype = 'dgram',
    }))
    assert.equal(ai:socktype(), 'dgram')
end

function testcase.unix_typed_convenience_pathname_too_long()
    -- A pathname that exceeds sun_path length surfaces ENAMETOOLONG even
    -- when opts.socktype is provided.
    local ai, err = addrinfo.unix(string.rep('x', UNIX_PATH_MAX + 1), {
        socktype = 'stream',
    })
    assert.is_nil(ai)
    assert.equal(err.type, errno.ENAMETOOLONG)
end

function testcase.getaddrinfo_boolean_shortcuts_passive()
    -- opts.passive is honored as an AI_PASSIVE shortcut on getaddrinfo().
    local addrs = assert(addrinfo.getaddrinfo(nil, 0, {
        family = 'inet',
        socktype = 'stream',
        passive = true,
    }))
    assert.greater(#addrs, 0)
end

function testcase.getaddrinfo_boolean_shortcuts_canonname()
    -- opts.canonname is honored as an AI_CANONNAME shortcut; this drives
    -- check_canonname's `hints->ai_flags |= AI_CANONNAME` branch.
    local addrs = assert(addrinfo.getaddrinfo('localhost', 0, {
        family = 'inet',
        socktype = 'stream',
        canonname = true,
    }))
    assert.greater(#addrs, 0)
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

function testcase.family()
    -- family() returns the symbolic address-family name.
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:family(), 'inet')
end

function testcase.socktype()
    -- socktype() returns the symbolic name configured via opts.socktype.
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:socktype(), 'stream')
end

function testcase.protocol()
    -- protocol() returns the symbolic name configured via opts.protocol.
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:protocol(), 'tcp')
end

function testcase.addr()
    -- addr() returns the string form of the address (IPv4 dotted-quad,
    -- IPv6 hex, or unix path).
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:addr(), '127.0.0.1')
end

function testcase.port()
    -- port() returns the integer port number stored in the sockaddr.
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.equal(ai:port(), 8080)
end

function testcase.canonname()
    -- canonname() returns nil when AI_CANONNAME was not requested; it
    -- returns the canonical hostname string when 'canonname' is included
    -- in opts.flags via getaddrinfo().
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.is_nil(ai:canonname())

    local addrs = assert(addrinfo.getaddrinfo('localhost', 0, {
        family = 'inet',
        socktype = 'stream',
        flags = {
            'canonname',
        },
    }))
    assert.is_string(addrs[1]:canonname())
end

function testcase.tostring()
    -- tostring(ai) returns a string identifying the userdata's metatable
    -- and pointer, matching Lua's standard __tostring convention.
    local ai = assert(addrinfo.inet('127.0.0.1', 8080, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.match(tostring(ai), '^net.addrinfo: ', false)
end

--
-- ai:getnameinfo
--
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

--
-- unix family does not expose port
--
function testcase.unix_port_is_nil()
    -- AF_UNIX addrinfo values do not carry a port; the port() method
    -- returns nil rather than an integer.
    local ai = assert(addrinfo.unix(tmpsock(), {
        socktype = 'stream',
    }))
    assert.is_nil(ai:port())
end

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

function testcase.getnameinfo_surfaces_resolver_error()
    -- ai:getnameinfo('namereqd') on an IP with no reverse DNS returns
    -- (nil, err_eai) — this drives the rc != 0 branch of getnameinfo_lua.
    local ai = assert(addrinfo.inet('192.0.2.1', 80, {
        socktype = 'stream',
    }))
    local r, err = ai:getnameinfo('namereqd')
    assert.is_nil(r)
    assert(err)
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
end

function testcase.port_variants_empty_string()
    -- An empty-string port is accepted via the LUA_TSTRING slen==0 branch
    -- of get_service (equivalent to nil).
    local addrs = assert(addrinfo.getaddrinfo('127.0.0.1', '', {
        family = 'inet',
        socktype = 'stream',
    }))
    assert.greater(#addrs, 0)
end

function testcase.unix_addr_via_getsockname_pathname()
    local path = tmpsock()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    local sock = assert(socket.bind_unix(ai))
    -- kernel-provided sun_path may omit the trailing NUL; strnlen bounds
    -- the read so buggy strlen paths cannot spill into uninitialised bytes.
    local got = assert(sock:getsockname())
    assert.equal(got:addr(), path)
    sock:close()
    os.remove(path)
end

function testcase.unix_addr_via_getsockname_abstract()
    if not is_linux() then
        return
    end
    -- Linux abstract socket: sun_path[0] == '\0' and the name may embed NULs.
    local ai = assert(addrinfo.unix('\0lua-net-wi07', {
        socktype = 'stream',
    }))
    local sock = assert(socket.bind_unix(ai))
    local got = assert(sock:getsockname())
    local addr = got:addr()
    -- buggy strlen returned 0 chars for the leading NUL; the fix returns
    -- the binary name intact.
    assert.greater(#addr, 0)
    assert.equal(addr:sub(1, 1), '\0')
    sock:close()
end
