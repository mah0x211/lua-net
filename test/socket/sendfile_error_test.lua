local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local errno = require('errno')
local error_is = require('error').is
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local signal = require('testcase.signal')
local signal_mask = require('signal')
local nosigchld = require('testcase.nosigchld')
local getpid = require('testcase.getpid')
local sleep = require('testcase.timer').sleep
local offset_payload = require('test.offset_payload')

local function assert_child(proc)
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendfile_interrupted_without_progress_is_retryable()
    local worker = assert(fork())
    if worker:is_child() then
        run_child(function()
            -- Bound a failed blocking test without changing runner signals.
            assert(signal.sigdefault('SIGALRM'))
            signal.alarm(10)
            assert(nosigchld(true))
            assert(signal_mask.unblock('SIGCHLD'))
            local socks = assert(socket.pair({socktype = 'stream'}))
            local a, b = socks[1], socks[2]
            assert(a:sndbuf(512))
            local filler = string.rep('x', 65536)
            while true do
                local n, err, again = a:send(filler)
                assert.is_nil(err)
                if n == 0 then
                    assert.is_true(again)
                    break
                end
                assert.greater(n, 0)
            end
            assert(a:nonblock(false))
            assert.is_false(a:nonblock())

            local f = assert(io.tmpfile())
            assert(f:write('x'))
            assert(f:flush())
            local control = assert(socket.pair({socktype = 'stream'}))
            local parent_pid = getpid()
            local interrupter = assert(fork())
            if interrupter:is_child() then
                run_child(function()
                    a:close()
                    b:close()
                    f:close()
                    control[1]:close()
                    while true do
                        local done, err, again = control[2]:recv(1)
                        assert.is_nil(err)
                        if done then
                            break
                        end
                        assert.is_true(again)
                        assert(signal.kill('SIGCHLD', parent_pid))
                        sleep(0.01)
                    end
                    control[2]:close()
                end)
            end
            control[2]:close()

            -- Blocking mode, a full buffer, and no receiver: only the real
            -- non-restarting signal can make this call return for retry.
            local sent, err, again = a:sendfile(f, 1, 0)
            assert(signal_mask.block('SIGCHLD'))
            assert.equal(control[1]:send('x'), 1)
            control[1]:close()
            assert_child(interrupter)
            signal.alarm(0)
            assert(nosigchld(false))
            assert.equal(sent, 0)
            assert.is_nil(err)
            assert.is_true(again)
            f:close()
            a:close()
            b:close()
        end)
    end
    assert_child(worker)
end

local function peer_closes_after_progress(wrapped)
    local worker = assert(fork())
    if worker:is_child() then
        run_child(function()
            assert(signal.sigdefault('SIGALRM'))
            signal.alarm(10)
            -- Host-side SIGPIPE handling is required by Linux sendfile.
            assert(signal.sigignore('SIGPIPE'))
            -- The peer's exit must not turn the transfer error into EINTR.
            assert(signal_mask.block('SIGCHLD'))
            local socks = assert(socket.pair({socktype = 'stream'}))
            local a, b = socks[1], socks[2]
            assert(a:sndbuf(512))
            local f = assert(io.tmpfile())
            local data = offset_payload(1024 * 1024)
            assert(f:write(data))
            assert(f:flush())
            local reader = assert(fork())
            if reader:is_child() then
                run_child(function()
                    a:close()
                    f:close()
                    assert(b:nonblock(false))
                    local prefix = assert(b:recv(64))
                    assert.greater(#prefix, 0)
                    assert.equal(prefix, data:sub(1, #prefix))
                    b:close()
                end)
            end
            b:close()
            local writer = a
            if wrapped then
                writer = assert(require('net.stream.unix').wrap(a:unwrap()))
                a = writer.sock
            end
            assert(a:nonblock(false))
            local sent, err, again = 0
            repeat
                local n
                n, err, again = writer:sendfile(f, #data - sent, sent)
                if n then
                    assert.is_int(n)
                    if err and not wrapped then
                        assert.greater(n, 0)
                    end
                    sent = sent + n
                else
                    assert(err)
                    assert.is_nil(again)
                end
                -- Linux may return a successful short transfer before the
                -- next call reports the peer's closure.
            until err or sent == #data or (n == 0 and not again)
            assert_child(reader)
            signal.alarm(0)
            assert.greater(sent, 0)
            assert.less(sent, #data)
            assert(error_is(err, errno.EPIPE, errno.ECONNRESET, errno.ENOTCONN))
            assert.is_nil(again)
            writer:close()
            f:close()
        end)
    end
    assert_child(worker)
end

function testcase.sendfile_preserves_progress_when_peer_closes()
    peer_closes_after_progress(false)
end

function testcase.stream_sendfile_preserves_progress_when_peer_closes()
    peer_closes_after_progress(true)
end
