local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')

-- unpack() moved to table.unpack in Lua 5.2
local unpack = unpack or table.unpack

function testcase.gcfn_callback_referencing_socket_is_collectable()
    -- The gc thread used to be anchored in the Lua registry, so a gc
    -- callback that referenced the socket itself formed a strong chain
    -- (registry -> thread -> closure upvalues -> callback -> socket)
    -- that the collector could never break: the socket leaked forever.
    -- The thread is now bound to the socket userdata itself, making the
    -- cycle collectable.
    local weak = setmetatable({}, {
        __mode = 'v',
    })
    local gced = false
    do
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        weak.sock = s
        assert(s:addgcfn(error, function()
            gced = true
        end, s))
        assert.is_false(gced)
    end
    collectgarbage('collect')
    collectgarbage('collect')
    assert.is_nil(weak.sock)
    assert.is_true(gced)

    -- A wrapped socket must also keep its callback until collection.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local weak2 = setmetatable({}, {
        __mode = 'v',
    })
    gced = false
    do
        local wrapped = assert(socket.wrap(socks[1]:fd()))
        -- Transfer ownership before registering the wrapper's callback.
        socks[1]:unwrap()
        weak2.sock = wrapped
        assert(wrapped:addgcfn(error, function()
            gced = true
        end, wrapped))
        assert.is_false(gced)
    end
    collectgarbage('collect')
    collectgarbage('collect')
    assert.is_nil(weak2.sock)
    assert.is_true(gced)
    socks[2]:close()
end

function testcase.addgcfn()
    -- addgcfn returns a "net.socket.gcfn: 0x..." handle string on success.
    local called = false
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local handle = assert(s:addgcfn(error, function()
        called = true
    end))
    assert.is_string(handle)
    assert.equal(handle:sub(1, 19), 'net.socket.gcfn: 0x')
    assert(s:close())
    assert.is_true(called)

    -- extra arguments passed to addgcfn are forwarded to the callback.
    local received = {}
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(error, function(a, b, c)
        received[1] = a
        received[2] = b
        received[3] = c
    end, 'first', 42, true))
    assert(s:close())
    assert.equal(received[1], 'first')
    assert.equal(received[2], 42)
    assert.equal(received[3], true)

    -- addgcfn on an already-closed socket returns nil + EBADF error.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    local h2, err = s:addgcfn(error, function()
    end)
    assert.is_nil(h2)
    assert.equal(err.type, errno.EBADF)
end

function testcase.delgcfn()
    -- delgcfn(handle) returns true when the handle is currently registered.
    local called = false
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local handle = assert(s:addgcfn(error, function()
        called = true
    end))
    assert.is_true(s:delgcfn(handle))
    assert(s:close())
    assert.is_false(called)

    -- delgcfn can remove a handle from the middle of the registration
    -- stack; the surrounding gcfns still run in LIFO order.
    local order = {}
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 1
    end))
    local h2 = assert(s:addgcfn(error, function()
        order[#order + 1] = 2
    end))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 3
    end))
    assert.is_true(s:delgcfn(h2))
    -- second delete of the same handle returns false.
    assert.is_false(s:delgcfn(h2))
    assert(s:close())
    assert.equal(order, {
        3,
        1,
    })

    -- delgcfn returns false for a well-formed but unknown handle, raises for
    -- an ill-formed prefix, and raises for a bad hex tail.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert.is_false(s:delgcfn('net.socket.gcfn: 0x1'))
    local err = assert.throws(function()
        s:delgcfn('invalid handle')
    end)
    assert.match(err, 'net.socket.gcfn', false)
    err = assert.throws(function()
        s:delgcfn('net.socket.gcfn: nothex')
    end)
    assert.match(err, 'invalid net.socket.gcfn handle', false)
    s:close()

    -- delgcfn on an already-closed socket returns false rather than raising.
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local h3 = assert(s:addgcfn(error, function()
    end))
    assert(s:close())
    assert.is_false(s:delgcfn(h3))
end

function testcase.gcfn_reentrancy_is_guarded()
    -- While the gc callbacks are draining, the drain loop owns the thread
    -- and the fd: a re-entrant addgcfn must fail with EBADF, delgcfn must
    -- report false, and a re-entrant close must no-op so the remaining
    -- callbacks still see a live fd (the outer close disposes it once the
    -- drain finishes).
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local fd_seen = -1
    local fd_after
    local nonblock_after, nonblock_err
    local add_nil, add_err
    local del_rv, close_rv
    assert(s:addgcfn(error, function()
        fd_seen = s:fd()
        add_nil, add_err = s:addgcfn(error, function()
        end)
        del_rv = s:delgcfn('net.socket.gcfn: 0x1')
        close_rv = s:close()
        fd_after = s:fd()
        nonblock_after, nonblock_err = s:nonblock()
    end))
    assert(s:close())

    assert(fd_seen >= 0, 'the fd must be alive during the callbacks')
    assert.equal(fd_after, fd_seen)
    assert.is_true(nonblock_after)
    assert.is_nil(nonblock_err)
    assert.is_nil(add_nil)
    assert.not_nil(add_err)
    assert.equal(add_err.type, errno.EBADF)
    assert.is_false(del_rv)
    assert.is_true(close_rv)
end

function testcase.gcfn()
    -- Multiple registered gcfns run in LIFO order when the socket is closed.
    local order = {}
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 1
    end))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 2
    end))
    assert(s:addgcfn(error, function()
        order[#order + 1] = 3
    end))
    assert(s:close())
    assert.equal(order, {
        3,
        2,
        1,
    })

    -- A second close() is a no-op even after the gc thread has been
    -- released (exercises net_gcthread_close's early return).
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:close())
    assert(s:close())
end

function testcase.gcfn_error_handling()
    -- The user-provided errfn receives failures raised by the gc callback.
    local caught
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(function(err)
        caught = err
    end, function()
        error('boom')
    end))
    assert(s:close())
    assert.match(caught, 'boom', false)

    -- A gc callback without an errfn does not crash close/gc even when the
    -- callback raises: the outer net_gcthread_close catches / discards it.
    local called = false
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(nil, function()
        called = true
        error('should be swallowed')
    end))
    assert(s:close())
    assert.is_true(called)

    -- A gc callback whose errfn ALSO raises still terminates cleanly.
    caught = nil
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(function(err)
        -- Lua 5.1 may invoke a failing error handler again.
        caught = caught or err
        error('errfn also failed: ' .. tostring(err))
    end, function()
        error('boom')
    end))
    assert(s:close())
    assert.match(caught, 'boom', false)

    -- A failure in one gc callback does not prevent the other callbacks
    -- from running.  LIFO order: the last registered callback runs first;
    -- the middle callback raises and must not abort the iteration.
    local order = {}
    local middle_called = false
    s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    assert(s:addgcfn(nil, function()
        order[#order + 1] = 1
    end))
    assert(s:addgcfn(nil, function()
        middle_called = true
        error('middle fails')
    end))
    assert(s:addgcfn(nil, function()
        order[#order + 1] = 3
    end))
    assert(s:close())
    assert.is_true(middle_called)
    assert.equal(order, {
        3,
        1,
    })
end

function testcase.gc_closes_socket()
    -- test that a live socket that never had close() called is closed when
    -- it is garbage-collected.  We drop the only reference in an inner block
    -- and then force a full GC cycle so gc_lua's fd != -1 branch runs.
    local fd
    do
        local s = assert(socket.new_inet({
            socktype = 'stream',
            protocol = 'tcp',
        }))
        fd = s:fd()
        -- do not call s:close(); rely on gc
    end
    collectgarbage('collect')
    collectgarbage('collect')
    -- Do not open another descriptor before checking: it could reuse fd.
    -- This also closes a leaked descriptor before reporting the failure.
    local ok, err = socket.close(fd)
    assert.is_false(ok)
    assert(err)
    assert.equal(err.type, errno.EBADF)
end

function testcase.addgcfn_forwards_many_arguments()
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    local args = {}
    for i = 1, 251 do
        args[i] = i
    end
    -- Three bookkeeping upvalues leave room for 252 callback arguments.
    -- Include a trailing nil so forwarding preserves the argument count.
    local received
    local nargs
    local calls = 0
    assert(s:addgcfn(nil, function(...)
        calls = calls + 1
        nargs = select('#', ...)
        received = {...}
    end, unpack(args, 1, 252)))

    assert(s:close())
    assert.equal(calls, 1)
    assert.equal(nargs, 252)
    assert.equal(received, args)
end

function testcase.addgcfn_rejects_excess_arguments_without_changing_callbacks()
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local calls = {}
    local function callback(id)
        calls[#calls + 1] = id
    end
    assert(s:addgcfn(nil, callback, 'existing'))

    local args = {}
    for i = 1, 253 do
        args[i] = i
    end
    local ok, err = pcall(s.addgcfn, s, nil, callback, unpack(args))
    assert(s:addgcfn(nil, callback, 'later'))
    assert(s:close())

    assert.is_false(ok)
    assert.match(err, 'too many arguments to addgcfn (maximum is 252)')
    assert.equal(calls, {
        'later',
        'existing',
    })
end

function testcase.addgcfn_repeated_registration_runs_once_in_lifo_order()
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))

    -- Retain enough callbacks to grow the GC thread stack, with a fixed
    -- bound instead of waiting for a runtime-dependent stack limit.
    local received = {}
    local function callback(id)
        received[#received + 1] = id
    end
    for i = 1, 64 do
        assert(s:addgcfn(nil, callback, i))
    end

    assert(s:close())
    assert.equal(#received, 64)
    for i = 1, 64 do
        assert.equal(received[i], 65 - i)
    end
    assert(s:close())
    assert.equal(#received, 64)
end
