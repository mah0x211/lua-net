require('luacov')
local testcase = require('testcase')
local assert = require('assert')
local exec = require('exec').execvp
local socket = require('net.socket._compat')
local gpoll = require('gpoll')
local sleep = require('time.sleep')
local tls_context = require('net.tls.context')
local new_tls_server = require('net.tls.server')
local new_tls_client = require('net.tls.client')

local SERVER_CONFIG

-- per-operation I/O timeout (seconds); each WANT wait may take up to this long.
local DEADLINE = 10

function testcase.before_all()
    local p = assert(exec('openssl', {
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-x509',
        '-days',
        '1',
        '-keyout',
        'cert.key',
        '-out',
        'cert.pem',
        '-subj',
        '/C=US/CN=www.example.com',
    }))

    for line in p.stderr:lines() do
        print(line)
    end

    local res = assert(p:close())
    if res.exit ~= 0 then
        error('failed to generate cert files')
    end

    SERVER_CONFIG = {
        cert = 'cert.pem',
        key = 'cert.key',
    }
end

function testcase.after_all()
    os.remove('cert.pem')
    os.remove('cert.key')
end

function testcase.encrypted_length()
    assert.equal(tls_context.encrypted_length('default'), 17749)
    assert.equal(tls_context.encrypted_length('tlsv1'), 17749)
    assert.equal(tls_context.encrypted_length('tlsv1.0'), 17689)
    assert.equal(tls_context.encrypted_length('tlsv1.1'), 17705)
    assert.equal(tls_context.encrypted_length('tlsv1.2'), 17749)
    assert.equal(tls_context.encrypted_length('tlsv1.3'), 16645)
end

-- WANT_READ / WANT_WRITE indicate a retryable SSL condition
local WANT = {
    [tls_context.WANT_READ] = true,
    [tls_context.WANT_WRITE] = true,
}

--- endpoint: wraps a TLS context, its fd and optional memory BIO.
--- @param ctx net.tls.context
--- @param name string
--- @param fd integer
--- @return table ep
local function new_ep(ctx, name, fd)
    return {
        ctx = ctx,
        name = name,
        fd = fd,
        bio = ctx:get_bio(),
        closed = false,
    }
end

--- Single-side bio pump: flush TX buffer to fd, then fill RX buffer from fd.
--- No-op when the endpoint has no memory BIO (socket-BIO mode) or is closed.
--- @param ep table
local function pump(ep)
    if ep.closed or not ep.bio then
        return
    end
    local _, err = ep.bio:drain()
    assert(not err, ep.name .. ':bio:drain: ' .. tostring(err))
    _, err = ep.bio:fill()
    assert(not err, ep.name .. ':bio:fill: ' .. tostring(err))
end

--- Wait for a retryable SSL condition on the endpoint.
--- With BIO: pump the buffers (the peer is a separate process).
--- Without BIO: wait until the fd becomes readable / writable.
--- @param ep table
--- @param want integer tls_context.WANT_READ / WANT_WRITE
--- @return boolean ok
--- @return any err
local function waitio(ep, want)
    if ep.bio then
        pump(ep)
        return true
    end
    if want == tls_context.WANT_READ then
        return gpoll.wait_readable(ep.fd, DEADLINE)
    elseif want == tls_context.WANT_WRITE then
        return gpoll.wait_writable(ep.fd, DEADLINE)
    end
    return false, 'unknown want: ' .. tostring(want)
end

--- Drive the endpoint handshake to completion.
--- @param ep table
--- @return boolean ok
--- @return any err
local function handshake(ep)
    while true do
        local ok, err, want = ep.ctx:handshake()
        if ok then
            -- with BIO, flush the final handshake flight to the fd
            pump(ep)
            return true
        elseif want and WANT[want] then
            local ok2, err2 = waitio(ep, want)
            if not ok2 then
                return false, ep.name .. ':handshake:waitio: ' .. tostring(err2)
            end
        elseif err then
            return false, ep.name .. ':handshake: ' .. tostring(err)
        else
            -- ZERO_RETURN: peer closed before handshake completed
            return false, ep.name .. ':handshake: peer closed'
        end
    end
end

--- Verify a write from the endpoint: pump the ciphertext out, then read back
--- exactly #payload bytes from the peer process' stdout.
--- @param ep table
--- @param proc exec.process the peer (its stdout receives our plaintext)
--- @param payload string
--- @return boolean ok
--- @return any err
local function transfer_write(ep, proc, payload)
    local sent = 0
    while sent < #payload do
        local n, err, want = ep.ctx:write(payload:sub(sent + 1))
        if n then
            pump(ep)
            sent = sent + n
        elseif want and WANT[want] then
            local ok, err2 = waitio(ep, want)
            if not ok then
                return false, ep.name .. ':write:waitio: ' .. tostring(err2)
            end
        elseif err then
            return false, ep.name .. ':write: ' .. tostring(err)
        else
            return false, ep.name .. ':write: peer closed'
        end
    end

    proc.stdout:set_timeout(DEADLINE)
    local got, err = proc.stdout:readn(#payload)
    if got ~= payload then
        return false,
               ep.name .. ':write verify failed (got=' .. tostring(got) ..
                   ', err=' .. tostring(err) .. ')'
    end
    return true
end

--- Verify a read on the endpoint: feed the peer process' stdin (it encrypts and
--- sends to us), then read until #payload bytes are decrypted.
--- @param ep table
--- @param proc exec.process the peer (its stdin feeds plaintext to us)
--- @param payload string
--- @return boolean ok
--- @return any err
local function transfer_read(ep, proc, payload)
    proc.stdin:set_timeout(DEADLINE)
    local ok, err = proc.stdin:write(payload)
    if not ok then
        return false, 'peer stdin:write: ' .. tostring(err)
    end

    local chunks, total = {}, 0
    while total < #payload do
        local s, err2, want = ep.ctx:read(#payload - total)
        if s then
            pump(ep)
            total = total + #s
            chunks[#chunks + 1] = s
        elseif want and WANT[want] then
            local ok2, err3 = waitio(ep, want)
            if not ok2 then
                return false, ep.name .. ':read:waitio: ' .. tostring(err3)
            end
        elseif err2 then
            return false, ep.name .. ':read: ' .. tostring(err2)
        else
            return false, ep.name .. ':read: peer closed at ' .. total .. '/' ..
                       #payload
        end
    end

    if table.concat(chunks) ~= payload then
        return false, ep.name .. ':read verify mismatch'
    end
    return true
end

--- Close the endpoint, draining any remaining BIO ciphertext.
--- @param ep table
--- @return boolean ok
--- @return any err
local function close_ep(ep)
    while true do
        local ok, err, want = ep.ctx:close()
        if ok then
            ep.closed = true
            return true
        elseif want and WANT[want] then
            local ok2, err2 = waitio(ep, want)
            if not ok2 then
                return false, ep.name .. ':close:waitio: ' .. tostring(err2)
            end
        elseif err then
            return false, ep.name .. ':close: ' .. tostring(err)
        else
            ep.closed = true
            return true
        end
    end
end

--- Find a free TCP port on 127.0.0.1 (probe socket is closed immediately).
--- @return integer port
local function free_port()
    local s = assert(socket.bind_inet_stream('127.0.0.1', 0, true, true))
    local port = assert(s:getsockname()):port()
    s:close()
    return port
end

--- Start `openssl s_server` bound to 127.0.0.1:port; it exits after 1 client.
--- @param port integer
--- @return exec.process proc
local function start_s_server(port, alpn)
    local args = {
        's_server',
        '-accept',
        '127.0.0.1:' .. tostring(port),
        '-cert',
        'cert.pem',
        '-key',
        'cert.key',
        '-quiet',
        '-naccept',
        '1',
    }
    if alpn then
        args[#args + 1] = '-alpn'
        args[#args + 1] = alpn
    end
    return exec('openssl', args)
end

--- Start `openssl s_client` connecting to 127.0.0.1:port.
--- -quiet enables -ign_eof and -nocommands (arbitrary payload is safe).
--- @param port integer
--- @return exec.process proc
local function start_s_client(port, alpn)
    local args = {
        's_client',
        '-connect',
        '127.0.0.1:' .. tostring(port),
        '-quiet',
        '-noservername',
    }
    if alpn then
        args[#args + 1] = '-alpn'
        args[#args + 1] = alpn
    end
    return exec('openssl', args)
end

--- Wait until a server is listening on 127.0.0.1:port.
--- @param port integer
--- @return net.socket sock connected socket
--- @return any err
local function wait_listen(port)
    for _ = 1, 200 do
        local sock = socket.connect_inet_stream('127.0.0.1', port, DEADLINE)
        if sock then
            return sock
        end
        -- ECONNREFUSED: server not ready yet; back off and retry
        sleep(0.05)
    end
    return nil, 's_server did not start listening on port ' .. tostring(port)
end

--- Dispose of state (ctx, sockets, peer process) best-effort.
--- @param state table
local function cleanup(state)
    if state.ctx then
        pcall(function()
            state.ctx:close()
        end)
    end
    for _, s in ipairs(state.socks or {}) do
        pcall(function()
            s:close()
        end)
    end
    if state.proc then
        pcall(function()
            state.proc:kill()
        end)
        pcall(function()
            state.proc:close()
        end)
    end
end

--- accept_s_client: tls_context.accept (server side, socket-BIO mode) vs s_client.
function testcase.accept_s_client()
    local state = {}
    local ok, err = pcall(function()
        local lsock =
            assert(socket.bind_inet_stream('127.0.0.1', 0, true, true))
        state.socks = {
            lsock,
        }
        assert(lsock:listen())
        local port = assert(lsock:getsockname()):port()

        state.proc = start_s_client(port)
        assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        -- wrap() guarantees non-blocking on platforms where accept() does not
        -- inherit O_NONBLOCK from the listening socket. Keep the wrapper
        -- alive so its __gc does not close the fd while the TLS context
        -- still uses it.
        local asock = assert(socket.wrap(afd))
        state.socks[#state.socks + 1] = asock
        local fd = asock:fd()

        local server = assert(new_tls_server(SERVER_CONFIG.cert,
                                             SERVER_CONFIG.key))
        state.ctx = assert(tls_context.accept(server, fd, false))
        local ep = new_ep(state.ctx, 'server', fd)

        assert(handshake(ep))
        assert(transfer_read(ep, state.proc, 'hello from client'))
        assert(transfer_write(ep, state.proc, 'hello from server'))
        assert(close_ep(ep))
    end)
    cleanup(state)
    if not ok then
        error(err)
    end
end

--- accept_s_client_bio: tls_context.accept (server side, memory BIO) vs s_client.
function testcase.accept_s_client_bio()
    local state = {}
    local ok, err = pcall(function()
        local lsock =
            assert(socket.bind_inet_stream('127.0.0.1', 0, true, true))
        state.socks = {
            lsock,
        }
        assert(lsock:listen())
        local port = assert(lsock:getsockname()):port()

        state.proc = start_s_client(port)
        assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        -- Keep the wrapper alive so its __gc does not close the fd while
        -- the TLS context still uses it.
        local asock = assert(socket.wrap(afd))
        state.socks[#state.socks + 1] = asock
        local fd = asock:fd()

        local server = assert(new_tls_server(SERVER_CONFIG.cert,
                                             SERVER_CONFIG.key))
        state.ctx = assert(tls_context.accept(server, fd, true, 1))
        local ep = new_ep(state.ctx, 'server', fd)
        assert(ep.bio, 'BIO not set on server context')
        assert.match(tostring(ep.bio), '^net.tls.bio: ', false)

        assert(handshake(ep))
        -- 'A' avoids s_server/s_client connected-command characters
        assert(transfer_read(ep, state.proc, string.rep('A', 4096)))
        assert(transfer_write(ep, state.proc, string.rep('A', 4096)))
        assert(close_ep(ep))
    end)
    cleanup(state)
    if not ok then
        error(err)
    end
end

--- connect_s_server: tls_context.connect (client side, socket-BIO mode) vs s_server.
function testcase.connect_s_server()
    local state = {}
    local ok, err = pcall(function()
        local port = free_port()
        state.proc = start_s_server(port)
        local csock = assert(wait_listen(port))
        state.socks = {
            csock,
        }
        local fd = csock:fd()

        local client = assert(new_tls_client())
        state.ctx = assert(tls_context.connect(client, fd, nil, false, false,
                                               true, false))
        local ep = new_ep(state.ctx, 'client', fd)

        assert(handshake(ep))
        assert(transfer_write(ep, state.proc, 'hello from client'))
        assert(transfer_read(ep, state.proc, 'hello from server'))
        assert(close_ep(ep))
    end)
    cleanup(state)
    if not ok then
        error(err)
    end
end

--- connect_s_server_bio: tls_context.connect (client side, memory BIO) vs s_server.
function testcase.connect_s_server_bio()
    local state = {}
    local ok, err = pcall(function()
        local port = free_port()
        state.proc = start_s_server(port)
        local csock = assert(wait_listen(port))
        state.socks = {
            csock,
        }
        local fd = csock:fd()

        local client = assert(new_tls_client())
        state.ctx = assert(tls_context.connect(client, fd, nil, false, false,
                                               true, true, 1))
        local ep = new_ep(state.ctx, 'client', fd)
        assert(ep.bio, 'BIO not set on client context')

        assert(handshake(ep))
        assert(transfer_write(ep, state.proc, string.rep('A', 4096)))
        assert(transfer_read(ep, state.proc, string.rep('A', 4096)))
        assert(close_ep(ep))
    end)
    cleanup(state)
    if not ok then
        error(err)
    end
end

--- accept_s_client_alpn: ALPN negotiation on the server side vs s_client.
function testcase.accept_s_client_alpn()
    local state = {}
    local ok, err = pcall(function()
        local lsock =
            assert(socket.bind_inet_stream('127.0.0.1', 0, true, true))
        state.socks = {
            lsock,
        }
        assert(lsock:listen())
        local port = assert(lsock:getsockname()):port()

        state.proc = start_s_client(port, 'h2')
        assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
        local afd = assert(lsock:acceptfd())
        local asock = assert(socket.wrap(afd))
        state.socks[#state.socks + 1] = asock
        local fd = asock:fd()

        local server = assert(new_tls_server(SERVER_CONFIG.cert,
                                             SERVER_CONFIG.key, 'default',
                                             'default', {
            'h2',
        }, 300, 512))
        state.ctx = assert(tls_context.accept(server, fd, false))
        local ep = new_ep(state.ctx, 'server', fd)

        assert(handshake(ep))
        assert.equal(ep.ctx:get_alpn(), 'h2')
        assert(close_ep(ep))
    end)
    cleanup(state)
    if not ok then
        error(err)
    end
end

--- connect_s_server_alpn: ALPN negotiation on the client side vs s_server.
function testcase.connect_s_server_alpn()
    local state = {}
    local ok, err = pcall(function()
        local port = free_port()
        state.proc = start_s_server(port, 'h2')
        local csock = assert(wait_listen(port))
        state.socks = {
            csock,
        }
        local fd = csock:fd()

        local client = assert(new_tls_client('default', 'default', {
            'h2',
        }, 0, 0, false))
        state.ctx = assert(tls_context.connect(client, fd, nil, false, false,
                                               true, false))
        local ep = new_ep(state.ctx, 'client', fd)

        assert(handshake(ep))
        assert.equal(ep.ctx:get_alpn(), 'h2')
        assert(close_ep(ep))
    end)
    cleanup(state)
    if not ok then
        error(err)
    end
end

--- new_server_alpn_invalid: invalid ALPN tables must be rejected.
function testcase.new_server_alpn_invalid()
    -- non-string element
    local ctx, err = new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                                     'default', 'default', {123})
    assert(ctx == nil, 'should reject non-string ALPN element')
    assert(err, 'should return error')

    -- protocol name exceeding 255 bytes
    ctx, err = new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key,
                              'default', 'default',
                              {string.rep('x', 256)})
    assert(ctx == nil, 'should reject >255 byte ALPN protocol')
    assert(err, 'should return error')
end

--- new_client_alpn_invalid: invalid ALPN tables must be rejected.
function testcase.new_client_alpn_invalid()
    -- non-string element
    local ctx, err = new_tls_client('default', 'default', {123})
    assert(ctx == nil, 'should reject non-string ALPN element')
    assert(err, 'should return error')

    -- protocol name exceeding 255 bytes
    ctx, err = new_tls_client('default', 'default',
                              {string.rep('x', 256)})
    assert(ctx == nil, 'should reject >255 byte ALPN protocol')
    assert(err, 'should return error')
end
