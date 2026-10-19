local testcase = require('testcase')
local rlimit = require('testcase.rlimit')
local assert = require('assert')
local errno = require('errno')
local addrinfo = require('net.addrinfo')
local socket = require('net.socket')

local RLIMIT_NOFILE

local function revert_rlimit_nofile()
    if RLIMIT_NOFILE then
        assert(rlimit('nofile', RLIMIT_NOFILE.cur, RLIMIT_NOFILE.max))
        RLIMIT_NOFILE = nil
    end
end

local function stash_rlimit_nofile()
    revert_rlimit_nofile()
    RLIMIT_NOFILE = assert(rlimit('nofile'))
end

function testcase.bind_inet_from_ai()
    -- bind_inet accepts a pre-built addrinfo userdata; also verifies empty
    -- opts and the reuseaddr shortcut.
    local ai = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local s = assert(socket.bind_inet(ai))
    local bound = assert(s:getsockname())
    assert.equal(bound:addr(), ai:addr())
    assert.greater(bound:port(), 0)
    s:close()

    s = assert(socket.bind_inet(ai, {}))
    bound = assert(s:getsockname())
    assert.equal(bound:addr(), ai:addr())
    assert.greater(bound:port(), 0)
    s:close()
    s = assert(socket.bind_inet(ai, {
        reuseaddr = true,
    }))
    assert.is_true(s:reuseaddr())
    bound = assert(s:getsockname())
    assert.equal(bound:addr(), ai:addr())
    assert.greater(bound:port(), 0)
    s:close()
end

function testcase.bind_inet_from_host_port()
    -- bind_inet(host, port) resolves via getaddrinfo, iterates the list,
    -- and binds the first candidate that yields a working socket.
    local s = assert(socket.bind_inet('127.0.0.1', 0))
    local ai = assert(s:getsockname())
    assert.equal(ai:family(), 'inet')
    assert.equal(ai:addr(), '127.0.0.1')
    assert.greater(ai:port(), 0)
    s:close()
end

function testcase.bind_inet_bad_host()
    -- Invalid hostname surfaces the addrinfo resolver error as (nil, err).
    local s, err = socket.bind_inet('..!!not-a-host!!..', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    })
    assert.is_nil(s)
    assert(err)
end

function testcase.bind_inet_address_in_use()
    -- Bind a socket to a random port, then try to bind another one to the
    -- same port without reuseaddr set.  new_net_socket's OP_BIND_INET
    -- branch falls through to the "close and try next addrinfo" cleanup
    -- path and ultimately returns nil + EADDRINUSE.
    local first = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local port = assert(first:getsockname()):port()

    local second, err = socket.bind_inet('127.0.0.1', port, {
        socktype = 'stream',
        protocol = 'tcp',
    })
    assert.is_nil(second)
    assert(err)
    assert.equal(err.type, errno.EADDRINUSE)

    first:close()
end

function testcase.connect_inet_from_host_port()
    -- connect_inet(host, port) resolves via getaddrinfo, iterates the list,
    -- and connects the first candidate socket to a listening peer.
    -- Depending on kernel timing the connect may complete synchronously or
    -- surface EINPROGRESS (again == true); either outcome is acceptable.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(0))
    local ai = assert(server:getsockname())

    local c, err, again = socket.connect_inet('127.0.0.1', ai:port())
    assert(c, err)
    assert.is_nil(err)
    assert(again == true or again == nil)
    assert(c:sendable(1))
    local pending_err, get_err = c:error()
    assert.is_nil(pending_err)
    assert.is_nil(get_err)
    local peer = assert(c:getpeername())
    assert.equal(peer:family(), ai:family())
    assert.equal(peer:addr(), ai:addr())
    assert.equal(peer:port(), ai:port())
    c:close()
    server:close()

    -- Release an ephemeral port before connecting. This assumes no other
    -- process binds that port in between; refusal must be ECONNREFUSED.
    local target = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local target_ai = assert(target:getsockname())
    assert(target:close())
    c, err, again = socket.connect_inet('127.0.0.1', target_ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    })
    if c then
        assert.is_nil(err)
        assert.is_true(again)
        assert(c:sendable(1))
        err, get_err = c:error()
        assert.is_nil(get_err)
    end
    assert(err)
    assert.equal(err.type, errno.ECONNREFUSED)
    if c then
        c:close()
    end
end

function testcase.connect_inet_bad_host()
    -- Invalid hostname surfaces the addrinfo resolver error as (nil, err).
    local s, err = socket.connect_inet('..!!not-a-host!!..', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    })
    assert.is_nil(s)
    assert(err)
end

function testcase.error()
    -- error() reports the current pending socket error via SO_ERROR:
    --  * nil    when the socket has no pending error (SO_ERROR = 0)
    --  * errobj when a prior asynchronous operation completed with an error
    --
    -- The Lua binding wraps sockopt_int_lua(SOL_SOCKET, SO_ERROR) and
    -- promotes the returned integer errno to an errobj via lua_errno.

    -- Fresh socket: nothing to report.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local pending_err, get_err = s:error()
    assert.is_nil(pending_err)
    assert.is_nil(get_err)
    s:close()

    -- Release an ephemeral port before connecting. This assumes no other
    -- process binds that port between close() and connect().
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local port = assert(server:getsockname()):port()
    assert(server:close())

    -- An asynchronous refusal is reported through SO_ERROR after the
    -- socket becomes writable. An immediate refusal comes from connect().
    local ai = assert(addrinfo.inet('127.0.0.1', port, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local c = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local connected, cerr, again = c:connect(ai)
    assert.is_false(connected)
    if again then
        assert.is_true(again)
        assert.is_nil(cerr)
        assert(c:sendable(1))
        cerr, get_err = c:error()
        assert.is_nil(get_err)
    else
        assert.is_nil(again)
    end
    assert(cerr)
    assert.equal(cerr.type, errno.ECONNREFUSED)
    c:close()
end

function testcase.bind()
    -- bind() associates a fresh socket with a local address.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    local ai = assert(addrinfo.inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:bind(ai))
    local bound = assert(s:getsockname())
    assert.equal(bound:addr(), ai:addr())
    assert.greater(bound:port(), 0)
    s:close()

    -- bind() on a closed socket returns (false, err) via EBADF.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local ok, err = s:bind(ai)
    assert.is_false(ok)
    assert(err)
end

function testcase.connect()
    -- connect() method drives a fresh socket into a three-way handshake
    -- with a listening peer.  On loopback the handshake either completes
    -- synchronously (ok == true) or reports EINPROGRESS via again == true.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(0))
    local ai = assert(server:getsockname())
    local ai_client = assert(addrinfo.inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local c = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local ok, err, again = c:connect(ai_client)
    assert.is_nil(err)
    if again then
        assert.is_false(ok)
        assert.is_true(again)
        assert(c:sendable(1))
    else
        assert.is_true(ok)
        assert.is_nil(again)
    end
    local pending_err, get_err = c:error()
    assert.is_nil(pending_err)
    assert.is_nil(get_err)
    local peer = assert(c:getpeername())
    assert.equal(peer:family(), ai_client:family())
    assert.equal(peer:addr(), ai_client:addr())
    assert.equal(peer:port(), ai_client:port())
    c:close()
    server:close()

    -- connect() on a closed socket returns (false, err).
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    ok, err = s:connect(ai_client)
    assert.is_false(ok)
    assert(err)
end

function testcase.connect_returns_again_when_previous_connect_pending()
    local sockets = {}
    local ok, err = pcall(function()
        local server = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
        }))
        sockets[#sockets + 1] = server
        assert(server:listen(1))
        local ai = assert(server:getsockname())
        local pending

        -- Fill the accept queue without accepting. Linux and macOS allow
        -- different numbers of completed connections for listen(1).
        for _ = 1, 4 do
            local c = assert(socket.new_inet({
                socktype = 'stream',
                protocol = 'tcp',
            }))
            sockets[#sockets + 1] = c
            local connected, cerr, again = c:connect(ai)
            assert.is_nil(cerr)
            -- Wait for ordinary loopback connects to finish before
            -- identifying the connection blocked by the full queue.
            local ready, perr = c:sendable(1)
            assert.is_nil(perr)
            if not ready then
                assert.is_false(connected)
                assert.is_true(again)
                pending = c
                break
            end
            assert.is_nil(c:error())
        end
        local c = assert(pending, 'listener queue must leave a connect pending')

        -- Keep the queue full until both paths have checked EALREADY.
        local connected, cerr, again = c:connect(ai)
        assert.is_false(connected)
        assert.is_nil(cerr)
        assert.is_true(again)

        c, cerr, again = socket.connect_inet(ai, {
            socktype = 'stream',
            protocol = 'tcp',
        })
        assert(c, cerr)
        sockets[#sockets + 1] = c
        assert.is_nil(cerr)
        assert.is_true(again)

        connected, cerr, again = c:connect(ai)
        assert.is_false(connected)
        assert.is_nil(cerr)
        assert.is_true(again)
    end)
    for i = #sockets, 1, -1 do
        sockets[i]:close()
    end
    assert(ok, err)
end

function testcase.connect_returns_ok_when_already_connected()
    -- Once the three-way handshake has finished, calling connect() again on
    -- the same socket causes the kernel to fail with EISCONN.  connect_lua
    -- must treat EISCONN as success (already connected) and return
    -- (true), rather than surfacing the errno as a terminal error.  Prior
    -- to the fix, EISCONN fell through to the error path and the second
    -- connect() returned (false, err).
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(32))
    local ai = assert(server:getsockname())
    local ai_client = assert(addrinfo.inet('127.0.0.1', ai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local c = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    -- The first call may complete immediately or start a non-blocking
    -- connect. Both paths must reach a completed, error-free connection.
    local ok, err, again = c:connect(ai_client)
    assert.is_nil(err)
    assert((ok == true and again == nil) or (ok == false and again == true))

    -- Wait for the kernel to complete the three-way handshake on
    -- loopback: poll writability instead of sleeping a fixed interval,
    -- so a slow runner cannot observe a still-pending connect.
    assert(c:sendable(1), 'the loopback handshake did not complete')
    local pending_err, get_err = c:error()
    assert.is_nil(pending_err)
    assert.is_nil(get_err)

    -- Second connect() on the now-connected socket surfaces EISCONN,
    -- which connect_lua must report as (true, nil, nil).
    ok, err, again = c:connect(ai_client)
    assert.is_true(ok)
    assert.is_nil(err)
    assert.is_nil(again)

    c:close()
    server:close()
end

function testcase.listen()
    -- listen() marks a bound socket as accepting incoming connections.
    local s = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(s:listen(0))
    s:close()

    -- listen() on a closed socket returns (false, err).
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local ok, err = s:listen()
    assert.is_false(ok)
    assert(err)
end

function testcase.getsockname()
    -- getsockname() reports the socket's local address after bind().
    local s = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    local ai = assert(s:getsockname())
    assert.equal(ai:family(), 'inet')
    assert.equal(ai:addr(), '127.0.0.1')
    assert.greater(ai:port(), 0)
    s:close()

    -- getsockname() on a closed socket returns (nil, err).
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local rv, err = s:getsockname()
    assert.is_nil(rv)
    assert(err)
end

function testcase.bind_inet_preserves_emfile_from_new_socket()
    -- new_net_socket() iterates candidate addrinfos and calls new_socket()
    -- for each.  If new_socket() itself fails (EMFILE / ENFILE /
    -- EPROTONOSUPPORT / ...) that errno used to be dropped and the
    -- caller saw EADDRNOTAVAIL instead, masking capacity failures as
    -- address failures.  Lower the soft fd limit to the next free fd
    -- number so the following socket() fails with EMFILE; the probe
    -- descriptor stays valid and nothing is hoarded.
    stash_rlimit_nofile()
    local probe = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(rlimit('nofile', probe:fd()))

    local success, ok, err = pcall(socket.bind_inet, '127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    })

    probe:close()
    revert_rlimit_nofile()

    assert(success, ok)
    assert.is_nil(ok)
    assert(err)
    assert(err.type == errno.EMFILE or err.type == errno.ENFILE,
           'expected EMFILE/ENFILE, got ' .. tostring(err.type))
    assert.not_equal(err.type, errno.EADDRNOTAVAIL)
end

function testcase.getpeername_unconnected()
    -- getpeername() on an unconnected socket surfaces ENOTCONN.  The
    -- close() method is also idempotent -- calling it twice succeeds.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    local ai, err = s:getpeername()
    assert.is_nil(ai)
    assert(err)
    assert(s:close())
    assert(s:close())
end

function testcase.getpeername()
    -- getpeername() reports the remote address of a connected socket.
    local server = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(server:listen(0))
    local sai = assert(server:getsockname())
    local client = assert(socket.connect_inet('127.0.0.1', sai:port(), {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    -- ensure the handshake completes before probing peername.
    assert(client:sendable(1))
    local pending_err, get_err = client:error()
    assert.is_nil(pending_err)
    assert.is_nil(get_err)
    local peer = assert(client:getpeername())
    assert.equal(peer:family(), sai:family())
    assert.equal(peer:addr(), sai:addr())
    assert.equal(peer:port(), sai:port())
    client:close()
    server:close()
end
