local support = require('test.tls.stream.inet.helpers').new()
local revert_rlimit_nofile = support.revert_rlimit_nofile
local testcase = require('testcase')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local offset_payload = require('test.offset_payload')
local rlimit = require('testcase.rlimit')
local assert = require('assert')
local error_is = require('error').is
local errno = require('errno')
local socket = require('net.socket')
local inet = require('net.stream.inet')
local tls_inet = require('net.tls.stream.inet')
local tls_context = require('net.tls.context')
local new_tls_client = support.new_tls_client
local tmpname = support.tmpname
local get_server_config = support.get_server_config
local stash_rlimit_nofile = support.stash_rlimit_nofile

local TESTFILE, CLIENT_CONFIG

function testcase.before_all()
    TESTFILE, CLIENT_CONFIG = support.before_all()
end

function testcase.after_all()
    support.after_all()
end

function testcase.after_each()
    support.after_each()
end

function testcase.sendfile_closes_file_opened_from_path()
    -- sendfile() accepts a path string; the file it opens internally is
    -- owned by the call and must be closed on every return path instead
    -- of waiting for the GC.  An invalid offset makes sendfile return
    -- immediately with EINVAL right after tofile(), so hammering that
    -- path leaks one descriptor per call if the file is left open; a
    -- lowered RLIMIT_NOFILE makes the leak surface as EMFILE quickly.
    local path = tmpname()
    local f = assert(io.open(path, 'w'))
    assert(f:write('hello'))
    assert(f:close())

    -- EINVAL returns before any network I/O, so a plain socketpair with
    -- a TLS client wrapper provides the sendfile method without needing
    -- a handshake or a peer reader
    local socks = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local cctx = assert(tls_context.connect(client, socks[1]:fd(), {
        verify_name = false,
        verify_cert = false,
    }))
    local c = tls_inet.Client(socks[1], cctx)

    -- lower the soft limit to a small absolute value: existing
    -- descriptors stay valid, only new opens fail.
    stash_rlimit_nofile()
    local r = assert(rlimit('nofile', 48))
    collectgarbage('stop')
    local ok, err = pcall(function()
        for _ = 1, r.cur + 1 do
            local sent, send_err, timeout = c:sendfile(path, 1, -1)
            assert.is_nil(sent)
            assert.not_nil(error_is(send_err, errno.EINVAL))
            assert.is_nil(timeout)
        end
    end)
    -- Restore process state before reporting an assertion failure.
    collectgarbage('restart')
    revert_rlimit_nofile()
    assert(ok, err)

    assert(c:close())
    socks[2]:close()
    os.remove(path)
end

function testcase.sendfile_recv()
    -- create large file
    local f = assert(io.open(TESTFILE, 'w+'))
    local msg = offset_payload(65 * 1024)
    assert(f:write(msg))
    assert(f:flush())
    local fsize = f:seek('end')

    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = get_server_config(),
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    -- test that communicates with sendfile and recv
    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                tlscfg = CLIENT_CONFIG,
            }))

            -- sendfile
            local remain = fsize
            local offset = 0
            repeat
                local sent, err, timeout = c:sendfile(f, remain, offset)
                assert(not err, err)
                -- update next params
                offset = assert.less_or_equal(offset + sent, fsize)
                remain = assert.greater_or_equal(remain - sent, 0)
            until not timeout

            -- wait for peer to close
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    local total = 0
    local tbl = {}
    while total < fsize do
        local data = assert(peer:recv())
        total = total + #data
        assert.less_or_equal(total, fsize)
        tbl[#tbl + 1] = data
    end
    assert.equal(table.concat(tbl), msg)

    peer:close()
    s:close()
    f:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendfile_recv_with_offset_nil_bytes()
    -- Regression: sendfile(f, nil, offset>0) must transfer only the bytes
    -- from `offset` to end-of-file.  A previous implementation used
    -- stat.size directly and drove pread past EOF for offset > 0.
    local f = assert(io.open(TESTFILE, 'w+'))
    local msg = 'hello world - sendfile offset nil bytes regression'
    assert(f:write(msg))
    assert(f:flush())
    local offset = 6 -- skip "hello "
    local expected = msg:sub(offset + 1)

    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = get_server_config(),
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                tlscfg = CLIENT_CONFIG,
            }))
            local sent, err, timeout = c:sendfile(f, nil, offset)
            assert.equal(sent, #expected)
            assert.is_nil(err)
            assert.is_nil(timeout)
            -- wait for peer to close before shutting down TLS
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    local total = 0
    local chunks = {}
    while total < #expected do
        local data = assert(peer:recv())
        total = total + #data
        chunks[#chunks + 1] = data
    end
    assert.equal(total, #expected)
    assert.equal(table.concat(chunks), expected)

    peer:close()
    s:close()
    f:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.sendfile_stops_at_eof()
    -- Regression: sendfile(f, bytes, offset) with bytes larger than the
    -- remaining file must not spin on pread returning the empty string.
    -- The wrapper stops at EOF and reports what it managed to transfer.
    local f = assert(io.open(TESTFILE, 'w+'))
    local msg = 'short'
    assert(f:write(msg))
    assert(f:flush())

    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = get_server_config(),
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = assert(fork())
    if p:is_child() then
        run_child(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                tlscfg = CLIENT_CONFIG,
            }))
            -- Request many more bytes than the file actually has.
            local n, err, timeout = c:sendfile(f, 4096, 0)
            assert.equal(n, #msg)
            assert.is_nil(err)
            assert.is_nil(timeout)
            c:read()
            c:close()
        end)
    end

    local peer = assert(s:accept())
    local total = 0
    local chunks = {}
    while total < #msg do
        local data = assert(peer:recv())
        total = total + #data
        chunks[#chunks + 1] = data
    end
    assert.equal(table.concat(chunks), msg)

    peer:close()
    s:close()
    f:close()
    local stat = assert(p:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end
