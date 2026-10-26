local fileno = require('io.fileno')
local testcase = require('testcase')
local offset_payload = require('test.offset_payload')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local error_is = require('error').is
local newstate = require('newstate')

function testcase.sendfile_keeps_temporary_file_alive_during_buffer_allocation()
    local L = assert(newstate.new())
    assert(L:loadstring([[
        local socket = require('net.socket')
        local socks = assert(socket.pair({socktype = 'stream'}))
        local weak = setmetatable({}, {__mode = 'v'})
        local observed = false
        local file_alive = false
        local function observe()
            observed = true
            file_alive = io.type(weak[1]) == 'file'
        end
        local function new_probe()
            if newproxy then
                local probe = newproxy(true)
                getmetatable(probe).__gc = observe
                return probe
            end
            return setmetatable({}, {__gc = observe})
        end
        local function arm()
            local file = assert(io.tmpfile())
            assert(file:write('x'))
            assert(file:flush())
            weak[1] = file
            collectgarbage('restart')
            return file
        end
        collectgarbage('collect')
        collectgarbage('stop')
        collectgarbage('setpause', 0)
        -- The fallback has only one Lua allocation; let that single GC
        -- step finish the isolated state's collection and finalizers.
        collectgarbage('setstepmul', 1000000)
        new_probe()
        local sent, err = socks[1]:sendfile(arm(), 1, 0)
        collectgarbage('stop')
        -- The fallback allocates a Lua staging buffer. Native sendfile
        -- paths need not run GC, so only check the observation if it ran.
        local observed_during_send = observed
        local alive_during_send = file_alive
        local file = weak[1]
        if file and io.type(file) == 'file' then
            file:close()
        end
        local data
        if sent == 1 then
            data = socks[2]:recv(1)
        end
        socks[1]:close()
        socks[2]:close()
        collectgarbage('restart')
        assert(sent == 1, tostring(err))
        assert(data == 'x')
        assert(not observed_during_send or alive_during_send)
        return true
    ]]))
    local ok, result = L:run()
    assert(ok, result)
    assert.is_true(result)
end

-- receive everything the socket currently holds, concatenated
local function recv_all(sock)
    local acc = {}
    while true do
        local chunk, err, again = sock:recv(65536)
        assert.is_nil(err)
        if not chunk then
            assert.is_true(again)
            return table.concat(acc)
        end
        assert.greater(#chunk, 0)
        acc[#acc + 1] = chunk
    end
end

function testcase.sendfile_partial_and_short()
    -- Exercise sendfile_lua with a variety of file offsets and byte
    -- counts. Allow partial writes, but require the received bytes to
    -- match the reported file range on every platform.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())
    local data = offset_payload(4096)
    assert(f:write(data))
    assert(f:flush())

    -- full send
    local sent, err = a:sendfile(f, #data, 0)
    assert.is_nil(err)
    assert.is_int(sent)
    assert.greater(sent, 0)
    assert.less_or_equal(sent, #data)
    assert.equal(recv_all(b), data:sub(1, sent))
    -- send with offset
    sent, err = a:sendfile(f, 128, 512)
    assert.is_nil(err)
    assert.is_int(sent)
    assert.greater(sent, 0)
    assert.less_or_equal(sent, 128)
    assert.equal(recv_all(b), data:sub(513, 512 + sent))
    f:close()
    a:close()
    b:close()
end

function testcase.sendfile_after_peer_close()
    -- A closed Unix peer produces a connection error. Native sendfile may
    -- report ENOTCONN rather than the send(2) EPIPE / ECONNRESET errors.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(b:close())

    local f = assert(io.tmpfile())
    assert(f:write(string.rep('S', 4096)))
    assert(f:flush())

    local rv, err, again = a:sendfile(f, 4096, 0)
    assert.is_nil(rv)
    assert(error_is(err, errno.EPIPE, errno.ECONNRESET, errno.ENOTCONN))
    assert.is_nil(again)

    f:close()
    a:close()
end

function testcase.sendfile_eof()
    -- An offset beyond EOF returns zero without requesting a retry.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())
    assert(f:write('abc'))
    assert(f:flush())

    local rv, err, again = a:sendfile(f, 4, 100)
    assert.equal(rv, 0)
    assert.is_nil(err)
    assert.is_nil(again)

    f:close()
    a:close()
    b:close()
end

function testcase.sendfile_zero_length()
    -- Requesting zero bytes should be rejected with EINVAL inside
    -- sendfile_lua.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())
    assert(f:write('abc'))
    assert(f:flush())

    local rv, err = a:sendfile(f, 0, 0)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    f:close()
    a:close()
    b:close()
end

function testcase.sendfile_rejects_negative_size_and_offset()
    -- lauxh_checkinteger accepts negative values.  Casting them straight
    -- to size_t / off_t turned -1 into SIZE_MAX and a negative offset
    -- into an out-of-range file position.  Both must be rejected with
    -- EINVAL before the platform-specific sendfile branch runs.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    local f = assert(io.tmpfile())
    assert(f:write('abc'))
    assert(f:flush())

    local rv, err = a:sendfile(f, -1, 0)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    rv, err = a:sendfile(f, 8, -1)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    f:close()
    a:close()
    b:close()
end

function testcase.sendfile_clamps_to_file()
    -- A request beyond EOF transfers only the bytes left in the file.
    local f = assert(io.tmpfile())
    local data = string.rep('x', 100 * 1024)
    assert(f:write(data))
    assert(f:flush())

    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a, b = socks[1], socks[2]
    assert(a:sndbuf(1024 * 1024))
    local sent, err = a:sendfile(f, #data * 2, 0)
    assert.is_nil(err)
    assert.equal(sent, #data)
    assert.equal(recv_all(b), data)
    f:close()
    a:close()
    b:close()
end

function testcase.sendfile_bad_fd()
    -- Passing a closed file descriptor surfaces EBADF; every internal
    -- failure of the sendfile method reports the "sendfile" op regardless
    -- of which platform variant is compiled.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())
    assert(f:write('abc'))
    assert(f:flush())
    local badfd = fileno(f)
    assert(f:close())

    local rv, err = a:sendfile(badfd, 8, 0)
    assert.is_nil(rv)
    assert(err)
    assert.equal(err.type, errno.EBADF)
    assert.equal(err.op, 'sendfile')

    a:close()
    b:close()
end

function testcase.sendfile_on_closed_socket()
    -- test that sendfile surfaces EBADF when the socket has been closed.
    local s = assert(socket.new_inet({
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local f = assert(io.tmpfile())
    assert(f:write('data'))
    assert(f:flush())
    assert(s:close())

    local rv, err, again = s:sendfile(f, 4, 0)
    assert.is_nil(rv)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(again)

    f:close()
end

function testcase.sendfile_again()
    -- A small send buffer makes this transfer partial. Drain the peer and
    -- resume at the reported offset, verifying the received prefix rather
    -- than assuming a fixed number of calls completes the whole file.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]
    assert(a:sndbuf(512))

    local f = assert(io.tmpfile())
    local data = offset_payload(100 * 1024)
    assert(f:write(data))
    assert(f:flush())

    -- fill the send buffer: the first call stops with "again" while the
    -- file still has bytes left
    local sent, err, again = a:sendfile(f, #data, 0)
    assert.is_nil(err)
    assert.is_int(sent)
    assert.greater(sent, 0)
    assert.less(sent, #data)
    assert.is_true(again)

    -- resume at the reported offset: draining the peer frees buffer
    -- space, the resumed call transfers more bytes, and everything
    -- received so far matches the file prefix
    local got1 = recv_all(b)
    assert.equal(#got1, sent)
    assert.equal(got1, data:sub(1, sent))
    local sent2, err2 = a:sendfile(f, #data - sent, sent)
    assert.is_nil(err2)
    assert.is_int(sent2)
    assert.greater(sent2, 0)
    assert.less_or_equal(sent2, #data - sent)
    local got2 = recv_all(b)

    assert.equal(#got1 + #got2, sent + sent2)
    assert.equal(got1 .. got2, data:sub(1, sent + sent2))

    f:close()
    a:close()
    b:close()
end

function testcase.sendfile_stream_pair()
    -- Round-trip a file through sendfile() on a connected stream pair.
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local a = socks[1]
    local b = socks[2]

    local f = assert(io.tmpfile())
    assert(f:write('filedata'))
    assert(f:flush())
    local sent, err, again = a:sendfile(f, 8, 0)
    assert.equal(sent, 8)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(assert(b:recv(8)), 'filedata')
    sent, err, again = a:sendfile(fileno(f), 8, 0)
    assert.equal(sent, 8)
    assert.is_nil(err)
    assert.is_nil(again)
    assert.equal(assert(b:recv(8)), 'filedata')
    f:close()

    a:close()
    b:close()
end
