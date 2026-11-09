local assert = require('assert')
local gpoll = require('gpoll')
local inet = require('net.stream.inet')
local socket_close = require('net.socket').close

-- Resource state is owned by one test file.
local function new()
    local HOST = '127.0.0.1'
    local SERVER, CLIENT, PEER
    local TESTFILE
    local ACCEPTED_FD

    local TMPPATHS = {}

    --- Tracked tmpname(): the path is removed by after_each even when a
    --- test fails midway, so no unix socket or temp file is left behind.
    --- @return string path
    local function tmpname()
        local path = os.tmpname()
        TMPPATHS[#TMPPATHS + 1] = path
        return path
    end

    local function before_each()
        TESTFILE = tmpname()
        os.remove(TESTFILE)
        return TESTFILE
    end

    local function after_each(accepted_fd)
        ACCEPTED_FD = accepted_fd
        if ACCEPTED_FD then
            socket_close(ACCEPTED_FD)
            ACCEPTED_FD = nil
        end
        for i = #TMPPATHS, 1, -1 do
            os.remove(TMPPATHS[i])
            TMPPATHS[i] = nil
        end

        if PEER then
            PEER:close()
            PEER = nil
        end
        if CLIENT then
            CLIENT:close()
            CLIENT = nil
        end
        if SERVER then
            SERVER:close()
            SERVER = nil
        end
        os.remove(TESTFILE)
        gpoll.set_poller()
    end

    -- open_pair sets SERVER, CLIENT, PEER so after_each closes them.  The
    -- caller may still close explicitly to observe close-side errors.
    local function open_pair()
        SERVER = assert(inet.server.new(HOST, 0, {
            reuseaddr = true,
            reuseport = true,
        }))
        assert(SERVER:listen())
        local port = assert(SERVER:getsockname()):port()
        CLIENT = assert(inet.client.new(HOST, port))
        PEER = assert(SERVER:accept())
        return SERVER, CLIENT, PEER
    end

    return {
        HOST = HOST,
        open_pair = open_pair,
        before_each = before_each,
        after_each = after_each,
    }
end

return { new = new }
