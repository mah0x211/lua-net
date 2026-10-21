local fileno = require('io.fileno')
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

function testcase.message_flags_accept_string_names()
    -- Connected stream sockets cover send/recv/sendmsg/recvmsg without
    -- relying on an inet bind.  Receive-side MSG_PEEK leaves the payload for
    -- the following unflagged call, proving that the decoded flags reach the
    -- syscall.  Repeated names and nil gaps exercise the variadic parser.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    assert.equal(assert(a:send('s', 'dontwait', nil, 'dontwait')), 1)
    assert.equal(assert(b:recv(1)), 's')

    assert.equal(assert(b:send('r')), 1)
    assert.equal(assert(a:recv(1, 'peek', nil, 'dontwait', 'peek')), 'r')
    assert.equal(assert(a:recv(1)), 'r')

    assert.equal(assert(a:sendmsg('m', nil, nil, 'dontwait', nil, 'dontwait')),
                 1)
    assert.equal(assert(b:recv(1)), 'm')

    assert.equal(assert(b:sendmsg('g')), 1)
    local msg = assert(a:recvmsg(1, 0, 'peek', nil, 'dontwait', 'peek'))
    assert.equal(msg.data, 'g')
    assert.equal(assert(a:recv(1)), 'g')

    a:close()
    b:close()

    -- sendfd/recvfd consume SCM_RIGHTS messages, so MSG_DONTWAIT is the safe
    -- portable flag for these paths.  Every received descriptor is closed.
    socks = assert(socket.pair({
        socktype = 'stream',
    }))
    a = socks[1]
    b = socks[2]
    local f = assert(io.tmpfile())

    assert.equal(assert(a:sendfd(fileno(f), nil, 'dontwait', nil, 'dontwait')),
                 0)
    local fd = assert(assert(b:recvfd('dontwait', nil, 'dontwait')):get())
    assert(socket.close(fd))

    f:close()
    a:close()
    b:close()

    -- sendto requires an explicit address.  Unix datagram sockets avoid
    -- depending on an available inet interface or port.
    local path_a = tmpname()
    os.remove(path_a)
    local path_b = tmpname()
    os.remove(path_b)
    local ai_a = assert(addrinfo.unix(path_a, {
        socktype = 'dgram',
    }))
    local ai_b = assert(addrinfo.unix(path_b, {
        socktype = 'dgram',
    }))
    local da = assert(socket.bind_unix(ai_a))
    local db = assert(socket.bind_unix(ai_b))

    assert.equal(assert(da:sendto('t', ai_b, 'dontwait', nil, 'dontwait')), 1)
    assert.equal(assert(db:recvfrom(1)), 't')

    da:close()
    db:close()
    os.remove(path_a)
    os.remove(path_b)

    -- A stream socketpair is sufficient for recvfrom's flag path; an
    -- anonymous peer address is an expected result for this socket family.
    socks = assert(socket.pair({
        socktype = 'stream',
    }))
    a = socks[1]
    b = socks[2]
    assert.equal(assert(b:send('f')), 1)
    assert.equal(assert(a:recvfrom(1, 'peek', nil, 'dontwait', 'peek')), 'f')
    assert.equal(assert(a:recv(1)), 'f')
    a:close()
    b:close()
end

function testcase.message_flags_reject_unknown_and_non_string_values()
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local f = assert(io.tmpfile())
    local path = tmpname()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'dgram',
    }))
    local cases = {
        {
            name = 'send',
            argument = 4,
            call = function(value)
                a:send('x', 'dontwait', nil, value)
            end,
        },
        {
            name = 'sendto',
            argument = 5,
            call = function(value)
                a:sendto('x', ai, 'dontwait', nil, value)
            end,
        },
        {
            name = 'sendfd',
            argument = 5,
            call = function(value)
                a:sendfd(fileno(f), nil, 'dontwait', nil, value)
            end,
        },
        {
            name = 'sendmsg',
            argument = 6,
            call = function(value)
                a:sendmsg('x', nil, nil, 'dontwait', nil, value)
            end,
        },
        {
            name = 'recv',
            argument = 4,
            call = function(value)
                a:recv(1, 'peek', nil, value)
            end,
        },
        {
            name = 'recvfrom',
            argument = 4,
            call = function(value)
                a:recvfrom(1, 'peek', nil, value)
            end,
        },
        {
            name = 'recvfd',
            argument = 3,
            call = function(value)
                a:recvfd('dontwait', nil, value)
            end,
        },
        {
            name = 'recvmsg',
            argument = 5,
            call = function(value)
                a:recvmsg(1, 0, 'peek', nil, value)
            end,
        },
    }

    for _, case in ipairs(cases) do
        local err = assert.throws(function()
            case.call('not_a_msg_flag')
        end)
        assert.match(err, 'bad argument #' .. case.argument, false)
        assert.match(err, "to '" .. case.name .. "'", false)
        assert.match(err, "unknown MSG_%* flag: 'not_a_msg_flag'", false)

        err = assert.throws(function()
            case.call(0)
        end)
        assert.match(err, 'bad argument #' .. case.argument, false)
        assert.match(err, "to '" .. case.name .. "'", false)
        assert.match(err, 'flag must be a string', false)
    end

    f:close()
    a:close()
    b:close()
    os.remove(path)
end

function testcase.recv_unknown_message_flag_preserves_64_bytes()
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local s = socks[1]
    local flag = string.rep('x', 64)
    local err = assert.throws(s.recv, s, 1, flag)
    assert.match(err, "unknown MSG_* flag: '" .. flag .. "'")
    assert.not_match(err, '...')
    s:close()
    socks[2]:close()
end

function testcase.recv_unknown_message_flag_truncates_after_64_bytes()
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local s = socks[1]
    local prefix = string.rep('x', 64)
    local err = assert.throws(s.recv, s, 1, prefix .. 'y')
    assert.match(err, "unknown MSG_* flag: '" .. prefix .. "'...")
    assert.not_match(err, prefix .. 'y')
    s:close()
    socks[2]:close()
end

function testcase.recv_unknown_message_flag_bounds_large_input_diagnostic()
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local s = socks[1]
    local prefix = string.rep('x', 64)
    local flag = prefix .. string.rep('y', 1024 * 1024)
    local err = assert.throws(s.recv, s, 1, flag)
    assert.match(err, "unknown MSG_* flag: '" .. prefix .. "'...")
    assert.not_match(err, string.rep('y', 65))
    assert.less(#err, 256)
    s:close()
    socks[2]:close()
end

function testcase.recv_family_rejects_msg_trunc_input_flag()
    -- On Linux datagram, raw, and seqpacket sockets, MSG_TRUNC as a
    -- recv-family input flag makes the syscall return the full original
    -- packet length rather than the number of bytes actually copied into
    -- the caller-provided buffer, which would leak adjacent memory when
    -- Lua later pushed that many bytes as a string.  The MSG_* input-flag
    -- parser therefore rejects "trunc" outright with the standard
    -- unknown-flag argument error on every recv entry point.
    local socks = assert(socket.pair({
        socktype = 'dgram',
    }))
    local a = socks[1]
    local b = socks[2]

    local cases = {
        {
            name = 'recv',
            argument = 2,
            call = function()
                a:recv(1, 'trunc')
            end,
        },
        {
            name = 'recvfrom',
            argument = 2,
            call = function()
                a:recvfrom(1, 'trunc')
            end,
        },
        {
            name = 'recvfd',
            argument = 1,
            call = function()
                a:recvfd('trunc')
            end,
        },
        {
            name = 'recvmsg',
            argument = 3,
            call = function()
                a:recvmsg(1, 0, 'trunc')
            end,
        },
    }

    for _, case in ipairs(cases) do
        local err = assert.throws(function()
            case.call()
        end)
        assert.match(err, 'bad argument #' .. case.argument, false)
        assert.match(err, "to '" .. case.name .. "'", false)
        assert.match(err, "unknown MSG_%* flag: 'trunc'", false)
    end

    a:close()
    b:close()
end

function testcase.rejects_output_only_msg_flags()
    -- MSG_CTRUNC, MSG_HAVEMORE and MSG_RCVMORE are kernel-set output
    -- flags (the msg_flags field that recvmsg(2) fills in), never valid
    -- input flags; accepting them let typos pass silently, so every
    -- flags-accepting entry point must reject them like any unknown
    -- flag name.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local f = assert(io.tmpfile())
    local path = tmpname()
    os.remove(path)
    local ai = assert(addrinfo.unix(path, {
        socktype = 'dgram',
    }))

    local cases = {
        {
            name = 'send',
            argument = 2,
            call = function(flag)
                a:send('x', flag)
            end,
        },
        {
            name = 'sendto',
            argument = 3,
            call = function(flag)
                a:sendto('x', ai, flag)
            end,
        },
        {
            name = 'sendfd',
            argument = 3,
            call = function(flag)
                a:sendfd(fileno(f), nil, flag)
            end,
        },
        {
            name = 'sendmsg',
            argument = 4,
            call = function(flag)
                a:sendmsg('x', nil, nil, flag)
            end,
        },
        {
            name = 'recv',
            argument = 2,
            call = function(flag)
                a:recv(1, flag)
            end,
        },
        {
            name = 'recvfrom',
            argument = 2,
            call = function(flag)
                a:recvfrom(1, flag)
            end,
        },
        {
            name = 'recvfd',
            argument = 1,
            call = function(flag)
                a:recvfd(flag)
            end,
        },
        {
            name = 'recvmsg',
            argument = 3,
            call = function(flag)
                a:recvmsg(1, 0, flag)
            end,
        },
    }

    for _, case in ipairs(cases) do
        for _, flag in ipairs({
            'ctrunc',
            'havemore',
            'rcvmore',
        }) do
            local err = assert.throws(function()
                case.call(flag)
            end)
            assert.match(err, 'bad argument #' .. case.argument, false)
            assert.match(err, "to '" .. case.name .. "'", false)
            assert.match(err, "unknown MSG_%* flag: '" .. flag .. "'", false)
        end
    end

    f:close()
    a:close()
    b:close()
end
