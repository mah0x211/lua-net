local testcase = require('testcase')
local assert = require('assert')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')

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

function testcase.bind_unix_from_ai()
    -- bind_unix accepts a pre-built addrinfo userdata.
    local path = tmpname()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    local s = assert(socket.bind_unix(ai))
    local bound = assert(s:getsockname())
    assert.equal(bound:family(), 'unix')
    assert.equal(bound:addr(), path)
    s:close()
    os.remove(path)
end

function testcase.connect_unix_from_ai()
    -- connect_unix(ai) connects to a listening unix peer.
    local path = tmpname()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'stream',
    }))
    local server = assert(socket.bind_unix(ai))
    assert(server:listen(0))

    local c, err = socket.connect_unix(ai)
    assert(c ~= nil, err)
    assert.is_nil(err)
    local peer = assert(server:accept())
    c:close()
    peer:close()

    -- Also drive connect_lua's synchronous success path (connect() == 0)
    -- via the socket-method form: `sock:connect(ai)` to a listening
    -- unix peer.
    local c2 = assert(socket.new_unix({
        socktype = 'stream',
    }))
    local ok, cerr = c2:connect(ai)
    assert.is_true(ok)
    assert.is_nil(cerr)
    local peer_ai = assert(c2:getpeername())
    assert.equal(peer_ai:family(), 'unix')
    assert.equal(peer_ai:addr(), path)
    c2:close()

    server:close()
    os.remove(path)
end
