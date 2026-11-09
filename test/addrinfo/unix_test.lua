local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')

local uname = assert(io.popen('uname -s'))
local OS = assert(uname:read('*l'))
assert(uname:close())
local UNIX_PATH_MAX = OS == 'Linux' and 108 or 104

local TMPPATHS = {}

--- Tracked tmpname(): the path is removed by after_each even when a
--- test fails midway, so no unix socket or temp file is left behind.
--- @return string path
local function tmpname()
    local path = os.tmpname()
    TMPPATHS[#TMPPATHS + 1] = path
    return path
end

function testcase.after_each()
    for i = #TMPPATHS, 1, -1 do
        os.remove(TMPPATHS[i])
        TMPPATHS[i] = nil
    end
end

local function tmpsock()
    return tmpname()
end


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
    -- opts.socktype is applied to the resulting AF_UNIX addrinfo (stream
    -- and dgram forms).
    local path = tmpsock()
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    assert.equal(ai:socktype(), 'stream')

    ai = assert(addrinfo.unix(path, {
        socktype = 'dgram',
    }))
    assert.equal(ai:socktype(), 'dgram')
end

function testcase.unix_empty_name()
    local ai = assert(addrinfo.unix(''))
    assert.equal(ai:addr(), '')
end

function testcase.unix_rejects_nul_pathname()
    for _, path in ipairs({
        'socket\0suffix',
        'socket\0',
        'socket\0\0suffix',
        string.rep('x', UNIX_PATH_MAX - 2) .. '\0',
    }) do
        local err = assert.throws(function()
            addrinfo.unix(path)
        end)
        assert.match(err, 'bad argument #1')
        assert.match(err, 'pathname must not contain NUL bytes')
    end
end

if OS == 'Linux' then
    function testcase.unix_preserves_nul_in_abstract_name()
        for _, name in ipairs({
            '\0',
            '\0\0',
            '\0socket\0suffix\0',
        }) do
            local ai = assert(addrinfo.unix(name))
            assert.equal(ai:addr(), name)
        end
    end
else
    function testcase.unix_rejects_leading_nul_without_abstract_namespace()
        for _, path in ipairs({
            '\0',
            '\0socket',
            '\0socket\0suffix',
        }) do
            local err = assert.throws(function()
                addrinfo.unix(path)
            end)
            assert.match(err, 'bad argument #1')
            assert.match(err, 'pathname must not contain NUL bytes')
        end
    end
end

function testcase.unix_pathname_max_length()
    -- Filesystem pathnames reserve one byte for the terminating NUL.
    local path = string.rep('x', UNIX_PATH_MAX - 1)
    local ai, err = addrinfo.unix(path)
    assert(ai, err)
    assert.is_nil(err)
    assert.equal(ai:addr(), path)
end

function testcase.unix_pathname_too_long()
    for _, len in ipairs({
        UNIX_PATH_MAX,
        UNIX_PATH_MAX + 1,
    }) do
        local ai, err = addrinfo.unix(string.rep('x', len))
        assert.is_nil(ai)
        assert.equal(err.type, errno.ENAMETOOLONG)
    end
end

function testcase.unix_abstract_name_boundaries()
    if OS ~= 'Linux' then
        return
    end
    -- An abstract name occupies sun_path without a terminator (the kernel
    -- takes the length from addrlen), so all UNIX_PATH_MAX bytes are usable;
    -- a filesystem pathname needs room for the NUL the library writes, so
    -- its maximum is one byte shorter.
    local abstract = '\0' .. string.rep('x', UNIX_PATH_MAX - 1)
    local ai, err = addrinfo.unix(abstract, {
        socktype = 'stream',
    })
    assert(ai, err)
    assert.equal(ai:addr(), abstract)

    ai, err = addrinfo.unix('\0' .. string.rep('x', UNIX_PATH_MAX))
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

function testcase.unix_port_is_nil()
    -- AF_UNIX addrinfo values do not carry a port; the port() method
    -- returns nil rather than an integer.
    local ai = assert(addrinfo.unix(tmpsock(), {
        socktype = 'stream',
    }))
    assert.is_nil(ai:port())
end

function testcase.unix_addr_via_getsockname_pathname()
    local path = tmpsock()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    local sock = assert(socket.bind_unix(ai))
    -- The bound pathname is preserved by getsockname().
    local got = assert(sock:getsockname())
    assert.equal(got:addr(), path)
    sock:close()
    os.remove(path)
end

function testcase.unix_addr_via_getsockname_abstract()
    if OS ~= 'Linux' then
        return
    end
    -- Linux abstract socket: sun_path[0] == '\0' and the name may embed NULs.
    local name = '\0lua-net-wi07-' .. tostring(os.time())
    local ai = assert(addrinfo.unix(name, {
        socktype = 'stream',
    }))
    local sock = assert(socket.bind_unix(ai))
    local got = assert(sock:getsockname())
    -- ai_addrlen was previously sizeof(sockaddr_un), so the kernel padded
    -- the abstract name with trailing NULs.  With the fix the round-trip
    -- returns the exact binary name the caller passed.
    assert.equal(got:addr(), name)
    sock:close()
end

function testcase.unix_addr_via_getsockname_unnamed()
    local sock = assert(socket.new_unix({
        socktype = 'stream',
    }))
    -- an unbound AF_UNIX socket has ai_addrlen <= offsetof(sun_path); addr()
    -- must return an empty string without reading past the sockaddr region.
    local got = assert(sock:getsockname())
    assert.equal(got:family(), 'unix')
    assert.equal(got:addr(), '')
    sock:close()
end
