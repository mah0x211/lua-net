local assert = require('assert')
local errno = require('errno')
local exec = require('exec').execvp
local gpoll = require('gpoll')
local socket = require('net.socket')
local tls_context = require('net.tls.context')

-- per-operation I/O timeout (seconds); each WANT wait may take up to this long.
local DEADLINE = 10

-- WANT_READ / WANT_WRITE indicate a retryable SSL condition
local WANT = {
    [tls_context.WANT_READ] = true,
    [tls_context.WANT_WRITE] = true,
}

--- endpoint: wraps a TLS context, its fd and optional memory BIO.
--- @param ctx net.tls.context
--- @param name string
--- @param fd integer
--- @param sock net.socket? socket owned by the endpoint
--- @return table ep
local function new_ep(ctx, name, fd, sock)
    return {
        ctx = ctx,
        name = name,
        fd = fd,
        sock = sock,
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
    if err and (err.type == errno.ECONNRESET or err.type == errno.EPIPE) then
        -- the peer vanished (e.g. an abrupt reconnect); record it so the
        -- shutdown loop in close_ep() can dispose instead of waiting for
        -- a close_notify that never comes
        ep.dead = true
        return
    end
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

--- Close the endpoint: run the graceful TLS shutdown (pumping any
--- remaining BIO ciphertext, including the final close_notify), then
--- dispose the context.
--- @param ep table
--- @return boolean ok
--- @return any err
local function close_ep(ep)
    local function dispose()
        assert(ep.ctx:close())
        if ep.sock then
            assert(ep.sock:close())
            ep.sock = nil
        end
        ep.closed = true
    end

    while true do
        local ok, err, want = ep.ctx:shutdown()
        if ok then
            -- flush the final close_notify ciphertext to the fd; do not
            -- fill — the peer may already be gone (abrupt reconnect /
            -- RST), which would surface ECONNRESET here
            local _, ferr = ep.bio:drain()
            assert(not ferr, ep.name .. ':bio:drain: ' .. tostring(ferr))
            dispose()
            return true
        elseif want and WANT[want] then
            local ok2, err2 = waitio(ep, want)
            if not ok2 then
                return false, ep.name .. ':close:waitio: ' .. tostring(err2)
            end
            if ep.dead then
                -- the peer vanished mid-shutdown; the bidirectional
                -- close_notify cannot complete, so dispose and finish
                dispose()
                return true
            end
        else
            -- shutdown failed; dispose the context before reporting
            dispose()
            return false, ep.name .. ':close: ' .. tostring(err)
        end
    end
end

-- s_client -reconnect does not wait for TLS 1.3 post-handshake tickets.
-- Use a session file and exchange application data before shutting down.
local function new_ticket_connection(trace_path)
    return function(lsock, server, protocol, session, resume, client_opts)
        local args = {
            's_client',
            '-connect',
            '127.0.0.1:' .. tostring(assert(lsock:getsockname()):port()),
            protocol,
            '-quiet',
            '-no_ign_eof',
            '-msg',
            '-msgfile',
            trace_path,
        }
        if client_opts and client_opts.servername then
            args[#args + 1] = '-servername'
            args[#args + 1] = client_opts.servername
        else
            args[#args + 1] = '-noservername'
        end
        if client_opts and client_opts.cert then
            args[#args + 1] = '-cert'
            args[#args + 1] = client_opts.cert
            args[#args + 1] = '-key'
            args[#args + 1] = client_opts.key
        end
        if client_opts and client_opts.groups then
            args[#args + 1] = '-groups'
            args[#args + 1] = client_opts.groups
        end
        if session then
            args[#args + 1] = '-sess_out'
            args[#args + 1] = session
        end
        if resume then
            args[#args + 1] = '-sess_in'
            args[#args + 1] = session
        end
        local proc = assert(exec('openssl', args))
        assert(gpoll.wait_readable(lsock:fd(), DEADLINE))
        local sock = assert(socket.wrap(assert(lsock:acceptfd())))
        local ctx = assert(tls_context.accept(server, sock:fd()))
        local ep = new_ep(ctx, 'server', sock:fd(), sock)
        local ok, err = handshake(ep)
        if not ok then
            ctx:close()
            sock:close()
            proc:close(0)
            error(err)
        end
        assert(transfer_read(ep, proc, 'A\n'))
        assert(transfer_write(ep, proc, 'A\n'))
        assert(close_ep(ep))

        proc.stdout:set_timeout(DEADLINE)
        for _ in proc.stdout:lines() do
        end
        for _ in proc.stderr:lines() do
        end
        assert.equal(assert(proc:close()).exit, 0)
        local trace_file = assert(io.open(trace_path))
        local trace = trace_file:read('*a')
        trace_file:close()
        assert.is_true(trace:find('ServerHello', 1, true) ~= nil)
        -- Both protocols omit the server Certificate flight on resumption.
        local reused = not trace:find('], Certificate\n', 1, true)
        local ticket = false
        local file = session and io.open(session)
        if file then
            file:close()
            local info = assert(exec('openssl', {
                'sess_id',
                '-in',
                session,
                '-text',
                '-noout',
            }))
            for line in info.stdout:lines() do
                ticket = ticket or line:match('TLS session ticket:') ~= nil
            end
            assert.equal(assert(info:close()).exit, 0)
        end
        return reused, ticket, trace
    end
end

return {
    DEADLINE = DEADLINE,
    WANT = WANT,
    new_ep = new_ep,
    pump = pump,
    handshake = handshake,
    transfer_write = transfer_write,
    transfer_read = transfer_read,
    close_ep = close_ep,
    new_ticket_connection = new_ticket_connection,
}
