require('luacov')
local testcase = require('testcase')
local fork = require('testcase.fork')
local sleep = require('testcase.timer').sleep
local rlimit = require('testcase.rlimit')
local assert = require('assert')
local exec = require('exec').execvp
local error_is = require('error').is
local errno = require('errno')
local errno_eai = require('errno.eai')
local socket = require('net.socket')
local inet = require('net.stream.inet')
local tls_inet = require('net.tls.stream.inet')
local tls_context = require('net.tls.context')
local new_tls_server = require('net.tls.server')
local new_tls_client = require('net.tls.client')

local SERVER_CONFIG
local CLIENT_CONFIG
local TESTFILE

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

    TESTFILE = os.tmpname()
    os.remove(TESTFILE)

    SERVER_CONFIG = {
        cert = 'cert.pem',
        key = 'cert.key',
    }
    CLIENT_CONFIG = {
        noverify_name = true,
        noverify_time = true,
        noverify_cert = true,
    }
end

function testcase.after_all()
    os.remove(TESTFILE)
    os.remove('cert.pem')
    os.remove('cert.key')
    revert_rlimit_nofile()
end

function testcase.after_each()
    revert_rlimit_nofile()
end

function testcase.server_new()
    local host = '127.0.0.1'
    -- test that create new net.stream.inet.Server
    local s, _, ai = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert.match(tostring(s), '^net.tls.stream.inet.Server: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'tcp')
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.greater(ai:port(), 0)
    assert(s:close())

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.server.new('invalid hostname', 0, {
        tlscfg = SERVER_CONFIG,
    })
    assert.not_nil(error_is(err, errno_eai.EAI_NONAME))
    _, err = inet.server.new(host, 'invalid servname', {
        tlscfg = SERVER_CONFIG,
    })
    assert(error_is(err, errno_eai.EAI_SERVICE) or
               error_is(err, errno_eai.EAI_NONAME))

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.server.new(host, 0, {
            tlscfg = 'hello',
        })
    end), 'opts.tlscfg must be table')
end

function testcase.client_new()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    local sai = assert(s:getsockname())
    local port = assert(sai:port())

    -- test that return client
    assert(s:listen())
    local c, err, timeout, ai = assert(inet.client.new(host, port, {
        deadline = 0.1,
        tlscfg = CLIENT_CONFIG,
    }))
    assert(not err, err)
    assert.is_nil(timeout)
    assert.match(tostring(c), '^net.tls.stream.inet.Client: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(c:isnonblock(), 'c.nonblock is not false')
    assert.equal(c:family(), 'inet')
    assert.equal(c:socktype(), 'stream')
    assert.equal(c:protocol(), 'tcp')
    assert(c:close())
    assert(s:close())

    -- test that returns error that refuse
    c, err, timeout = inet.client.new(host, port, {
        deadline = 0.1,
        tlscfg = CLIENT_CONFIG,
    })
    assert.is_nil(c)
    assert.not_nil(error_is(err, errno.ECONNREFUSED))
    assert.is_nil(timeout)

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            tlscfg = '',
        })
    end), 'opts.tlscfg must be table')

    assert.match(assert.throws(function()
        inet.client.new(host, port, {
            deadline = 'foo',
            tlscfg = CLIENT_CONFIG,
        })
    end), 'deadline must be finite number', false)
end

function testcase.accept()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port, {
        tlscfg = CLIENT_CONFIG,
    }))

    -- test that the stream layer wraps an accepted TLS connection as a
    -- net.tls.stream.inet.Socket
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.write_read()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    -- test that communicates with write and read
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = CLIENT_CONFIG,
        }))

        assert(c:write(msg))

        -- the client sees the server certificate after the handshake
        assert.re_match(c:get_peer_cert(), '^-----BEGIN CERTIFICATE')

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    local rcv = assert(peer:read())
    assert.equal(rcv, msg)

    -- the negotiation getters are reachable through the stream socket; the
    -- server sees no peer certificate because the client presented none
    assert.re_match(peer:get_version(), '^TLSv1\\.[23]$')
    assert.re_match(peer:get_cipher(), '^TLS_')
    assert.is_nil(peer:get_peer_cert())

    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.send_recv()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    -- test that communicates with send and recv
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = CLIENT_CONFIG,
        }))

        assert(c:send(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)

    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.sendfile_closes_file_opened_from_path()
    -- sendfile() accepts a path string; the file it opens internally is
    -- owned by the call and must be closed on every return path instead
    -- of waiting for the GC.  An invalid offset makes sendfile return
    -- immediately with EINVAL right after tofile(), so hammering that
    -- path leaks one descriptor per call if the file is left open; a
    -- lowered RLIMIT_NOFILE makes the leak surface as EMFILE quickly.
    local path = os.tmpname()
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
    local cctx = assert(tls_context.connect(client, socks[1]:fd(), nil, true,
                                            false, true, true))
    local c = tls_inet.Client(socks[1], cctx)

    -- lower the soft limit to a small absolute value: existing
    -- descriptors stay valid, only new opens fail.
    stash_rlimit_nofile()
    local leaked = false
    local r = assert(rlimit('nofile', 48))
    collectgarbage('stop')
    for _ = 1, r.cur + 1 do
        local _, err = c:sendfile(path, 1, -1)
        -- the invalid offset must fail as EINVAL; a leaked handle per
        -- call instead surfaces EMFILE once the lowered limit is hit
        -- (tofile failures are wrapped by error.format, which loses the
        -- errno type field, so match the wrapped cause text)
        if err and tostring(err):find('EMFILE', 1, true) then
            leaked = true
            break
        end
    end
    -- restart the GC so the test process can clean up and exit normally
    collectgarbage('restart')
    revert_rlimit_nofile()
    assert.is_false(leaked, 'sendfile must not exhaust the lowered fd limit')

    assert(c:close())
    socks[2]:close()
    os.remove(path)
end

function testcase.sendfile_recv()
    -- create large file
    local f = assert(io.open(TESTFILE, 'w+'))
    local tbl = {}
    math.randomseed(os.time())
    for _ = 1, 65 do
        local tok = tostring(math.random())
        tbl[#tbl + 1] = tok .. string.rep(' ', 1024 - #tok)
    end
    local msg = table.concat(tbl)
    assert(f:write(msg))
    assert(f:flush())
    local fsize = f:seek('end')

    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    -- test that communicates with sendfile and recv
    local p = fork()
    if p:is_child() then
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
        return
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    local total = 0
    tbl = {}
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
    assert(p:wait())
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
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:sendfile(f, nil, offset))
        -- wait for peer to close before shutting down TLS
        c:read()
        c:close()
        return
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
    assert(p:wait())
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
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = CLIENT_CONFIG,
        }))
        -- Request many more bytes than the file actually has.
        local n = assert(c:sendfile(f, 4096, 0))
        assert(n <= #msg,
               'sendfile must not report more bytes than the file holds')
        c:read()
        c:close()
        return
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
    assert(p:wait())
end

function testcase.sendmsg_recvmsg()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    -- test that sendmsg and recvmsg are not supported
    local len, err = c:sendmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = c:recvmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    len, err = peer:sendmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = peer:recvmsg()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.writev_readv()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local c = assert(inet.client.new(host, port, {
        tlscfg = CLIENT_CONFIG,
    }))
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)

    -- test that writev and readv are not supported
    local len, err = c:writev()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = c:readv()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    len, err = peer:writev()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))
    len, err = peer:readv()
    assert.is_nil(len)
    assert.not_nil(error_is(err, errno.EOPNOTSUPP))

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.server_set_sni_callback()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'
    local ncall = 0

    -- test that communicates with SNI callback
    s:set_sni_callback(function(...)
        ncall = ncall + 1
        assert.equal({
            ...,
        }, {
            'foo',
            'bar',
            'baz',
            'www.example.com',
        })
        return assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    end, 'foo', 'bar', 'baz')

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            servername = 'www.example.com',
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:send(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)
    local rcv = assert(peer:recv())
    assert.equal(rcv, msg)
    peer:close()
    assert(p:wait())
    assert.equal(ncall, 1)

    -- test that communicates without SNI callback
    s:set_sni_callback(nil)
    p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            servername = 'www.example.com',
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:send(msg))

        -- wait for peer to close
        c:read()
        c:close()
        return
    end

    peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)
    rcv = assert(peer:recv())
    assert.equal(rcv, msg)
    peer:close()
    assert(p:wait())
    assert.equal(ncall, 1)

    -- test that throws an error that SNI callback is not function
    local err = assert.throws(s.set_sni_callback, s, 'hello')
    assert.match(err, 'function or nil expected')

    s:close()
end

function testcase.write_read_bio()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    -- test that communicates with write and read in BIO mode
    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        -- verify BIO is active on the client side
        assert(c.tls_bio ~= nil, 'BIO not set on client')
        assert(c:write(msg))
        -- wait for peer to close
        c:read()
        c:close()
        return
    end
    local peer = assert(s:accept())
    assert.match(tostring(peer), '^net.tls.stream.inet.Socket: ', false)
    -- verify BIO is active on the server side
    assert(peer.tls_bio ~= nil, 'BIO not set on server peer')

    local rcv = assert(peer:read())
    assert.equal(rcv, msg)
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.client_new_bio_bufcap()
    -- tlscfg.bufcap must be forwarded to net.tls.context.connect/accept:
    -- the empty RX ring of a fresh memory-BIO context reports exactly the
    -- requested capacity on both the client and the accepted peer.
    local host = '127.0.0.1'
    local cap = 1048576
    local s = assert(inet.server.new(host, 0, {
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
            bufcap = cap,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c = assert(inet.client.new(host, port, {
        tlscfg = {
            noverify_name = CLIENT_CONFIG.noverify_name,
            noverify_time = CLIENT_CONFIG.noverify_time,
            noverify_cert = CLIENT_CONFIG.noverify_cert,
            use_bio = true,
            bufcap = cap,
        },
    }))
    assert(c.tls_bio ~= nil, 'BIO not set on client')
    local _, space_len = c.tls_bio:space()
    assert.equal(space_len, cap)

    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')
    _, space_len = peer.tls_bio:space()
    assert.equal(space_len, cap)

    assert(peer:close())
    assert(c:close())
    assert(s:close())
end

function testcase.client_new_bio_bufcap_unallocatable()
    -- an unallocatable tlscfg.bufcap must fail client.new instead of being
    -- silently ignored and falling back to the minimum buffer size
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c, err = inet.client.new(host, port, {
        tlscfg = {
            noverify_name = CLIENT_CONFIG.noverify_name,
            noverify_time = CLIENT_CONFIG.noverify_time,
            noverify_cert = CLIENT_CONFIG.noverify_cert,
            use_bio = true,
            bufcap = 4611686018427387904, -- 2^62
        },
    })
    assert.is_nil(c)
    assert(err, 'client.new must surface the bio allocation failure')

    s:close()
end

function testcase.tlscfg_bufcap_validation()
    -- tlscfg.bufcap must be nil or a non-negative integer
    local host = '127.0.0.1'
    assert.match(assert.throws(function()
        inet.client.new(host, 80, {
            tlscfg = {
                bufcap = 'hello',
            },
        })
    end), 'tlscfg.bufcap must be uint')

    assert.match(assert.throws(function()
        inet.server.new(host, 0, {
            tlscfg = {
                bufcap = -1,
            },
        })
    end), 'tlscfg.bufcap must be uint')
end

function testcase.bio_fill_without_timeout_does_not_crash()
    -- The internal deadline object was nil when Socket:bio_fill was
    -- called without a sec argument, but the EAGAIN path invoked
    -- deadline:is_done() unconditionally.  On a non-blocking socket
    -- that immediately returns EAGAIN the old code raised "attempt to
    -- index a nil value".  Replace tls_bio with a stub whose fill()
    -- reports EAGAIN deterministically (a real peer may deliver EOF
    -- instead of EAGAIN once the client closes, which made the test
    -- racy), and let the stubbed wait_readable prove that a deadline
    -- was materialized (non-nil remaining sec) before waiting.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        c:close()
        return
    end
    local peer = assert(s:accept())
    assert.not_nil(peer.tls_bio)

    local bio = peer.tls_bio
    local again = errno.new('EAGAIN')
    peer.tls_bio = {
        fill = function()
            return nil, again, true
        end,
    }

    -- sentinel only the stubbed wait can produce; the stub also asserts
    -- that the deadline provided a numeric remaining sec.
    local sentinel = errno.new('ECANCELED', 'test-sentinel')
    peer.wait_readable = function(_, sec)
        assert(type(sec) == 'number', 'remaining sec must be a number')
        return false, sentinel
    end

    local ok, err = peer:bio_fill()
    assert.is_false(ok)
    assert.equal(err, sentinel,
                 'bio_fill without deadline must reach wait_readable')

    peer.tls_bio = bio
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.bio_drain_without_timeout_does_not_crash()
    -- Same bug class as bio_fill_without_timeout_does_not_crash: with no sec
    -- argument the internal deadline was nil and the EAGAIN path of
    -- bio_drain crashed on deadline:is_done().  Replace tls_bio with a
    -- stub whose drain() reports EAGAIN, and let the stubbed wait_writable
    -- verify that a deadline was materialized (non-nil remaining sec)
    -- before waiting.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        c:close()
        return
    end
    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')

    local bio = peer.tls_bio
    local again = errno.new('EAGAIN')
    peer.tls_bio = {
        drain = function()
            return nil, again, true
        end,
    }

    -- sentinel only the stubbed wait can produce; the stub also asserts
    -- that the deadline provided a numeric remaining sec.
    local sentinel = errno.new('ECANCELED', 'test-sentinel')
    peer.wait_writable = function(_, sec)
        assert(type(sec) == 'number', 'remaining sec must be a number')
        return false, sentinel
    end

    local ok, err = peer:bio_drain()
    assert.is_false(ok)
    assert.equal(err, sentinel,
                 'bio_drain without deadline must reach wait_writable')

    peer.tls_bio = bio
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.bio_drain_waits_after_partial_drain_eagain()
    -- drain() reports a partial transfer as (n, nil, true): bytes moved,
    -- but the socket would block.  bio_drain must keep waiting instead of
    -- returning success with the remaining ciphertext still in the TX
    -- buffer, otherwise the peer sees a truncated record stream.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert.not_nil(peer.tls_bio)

    local bio = peer.tls_bio
    local ncall = 0
    peer.tls_bio = {
        drain = function()
            ncall = ncall + 1
            if ncall == 1 then
                -- partial drain: some bytes moved, socket now full
                return 4096, nil, true
            end
            -- after wait_writable the rest drains completely
            return 8192
        end,
    }

    local waited = false
    peer.wait_writable = function(_, sec)
        assert(type(sec) == 'number', 'remaining sec must be a number')
        waited = true
        return true
    end

    local ok = peer:bio_drain()
    assert.is_true(ok)
    assert.is_true(waited)

    peer.tls_bio = bio
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.server_sni_selects_alpn_of_target_server()
    -- The SNI callback switches the connection to the returned server's
    -- SSL_CTX; the ALPN protocol must then be selected from that server's
    -- ALPN configuration, and the target must stay referenced for the rest
    -- of the connection (it is only weakly referenced once the callback
    -- returns).
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    s:set_sni_callback(function()
        -- return a fresh server nobody else references
        return assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key, nil,
                                     nil, {
            'h2',
            'http/1.1',
        }))
    end)

    local p = fork()
    if p:is_child() then
        local ok2, err2 = pcall(function()
            s:close()
            local c = assert(inet.client.new(host, port, {
                servername = 'www.example.com',
                tlscfg = {
                    noverify_name = CLIENT_CONFIG.noverify_name,
                    noverify_time = CLIENT_CONFIG.noverify_time,
                    noverify_cert = CLIENT_CONFIG.noverify_cert,
                    alpn = {
                        'h2',
                    },
                },
            }))
            assert(c:send('hello'))
            assert.equal(c:get_alpn(), 'h2')
            c:close()
        end)
        if not ok2 then
            io.stderr:write('child failed: ' .. tostring(err2) .. '\n')
            os.exit(1)
        end
        os.exit(0)
    end

    local peer = assert(s:accept())
    -- drop every Lua-side reference to the target server and collect it
    -- before driving the handshake: the connection context must hold the
    -- target for the rest of the connection
    collectgarbage()
    collectgarbage()
    assert(peer:recv())
    assert.equal(peer:get_alpn(), 'h2')
    peer:close()
    s:close()
    local stat = assert(p:wait())
    assert.equal(stat.exit, 0)
end

function testcase.read_reports_error_on_half_close_without_close_notify()
    -- Socket:read must distinguish how the peer ended the connection: a
    -- peer that shuts its write side down (FIN) without a close_notify
    -- surfaces OpenSSL's unexpected-EOF error instead of a clean EOF.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()

        local c = assert(inet.client.new(host, port, {
            servername = 'www.example.com',
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:send('hello'))
        sleep(0.1)
        assert(c:send('world'))
        -- half-close: FIN without a close_notify
        assert(socket.shutdown(c:fd(), 'wr'))
        sleep(0.3)
        os.exit(0)
    end

    local peer = assert(s:accept())
    -- bound the reads: without the EOF classification the third read would
    -- spin until this deadline and report a bare timeout
    assert(peer:rcvtimeo(1))
    assert.equal(peer:recv(), 'hello')
    assert.equal(peer:recv(), 'world')
    local rv, err = peer:recv()
    assert.is_nil(rv)
    assert.not_nil(err)
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.read_reports_clean_eof_on_close_notify()
    -- A peer that closes gracefully (close_notify via Socket:close, which
    -- shuts the TLS layer down first) reads back as a clean EOF (nil, nil)
    -- on the other end - the counterpart of the half-close error above.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            servername = 'www.example.com',
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        assert(c:send('bye'))
        -- the server closes gracefully; its close_notify must surface as
        -- a clean EOF here, not an error
        assert(c:rcvtimeo(1))
        local rv, err = c:recv()
        assert.is_nil(rv)
        assert.is_nil(err)
        assert(c:close())
        os.exit(0)
    end

    local peer = assert(s:accept())
    assert(peer:rcvtimeo(1))
    assert.equal(peer:recv(), 'bye')
    -- graceful close: close() shuts the TLS layer down (close_notify)
    -- before disposing the fd
    assert(peer:close())
    s:close()
    assert(p:wait())
end

function testcase.poll_wait_without_timeout_does_not_crash()
    -- poll_wait without sec must materialize a deadline from the want
    -- direction (WANT_POLLOUT -> sndtimeo, WANT_POLLIN -> rcvtimeo via
    -- bio_drain) instead of passing nil down to the EAGAIN path.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        c:close()
        return
    end
    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')

    local bio = peer.tls_bio
    local again = errno.new('EAGAIN')
    peer.tls_bio = {
        drain = function()
            return nil, again, true
        end,
    }

    local sentinel = errno.new('ECANCELED', 'test-sentinel')
    peer.wait_writable = function(_, sec)
        assert(type(sec) == 'number', 'remaining sec must be a number')
        return false, sentinel
    end

    -- WANT_POLLOUT takes the bio_drain path directly
    local ok, err = peer:poll_wait(tls_context.WANT_WRITE)
    assert.is_false(ok)
    assert.equal(err, sentinel,
                 'poll_wait(WANT_POLLOUT) without deadline must reach wait_writable')

    -- WANT_POLLIN drains pending record(s) first, so the same stub covers
    -- the recv-direction deadline selection
    ok, err = peer:poll_wait(tls_context.WANT_READ)
    assert.is_false(ok)
    assert.equal(err, sentinel,
                 'poll_wait(WANT_POLLIN) without deadline must reach wait_writable')

    peer.tls_bio = bio
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.read_shares_rcvtimeo_with_first_handshake()
    -- Before the fix, a read that triggered the initial handshake let the
    -- handshake take its own sndtimeo budget instead of respecting the
    -- caller's rcvtimeo.  With rcvtimeo=1s and sndtimeo=5s a handshake
    -- against a silent peer used to block for ~5s; now it must timeout
    -- within rcvtimeo.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local p = fork()
    if p:is_child() then
        s:close()
        -- open a plain TCP socket to the TLS server and never send
        -- anything.  The peer will start the TLS handshake wait; from
        -- the server side we call read() with a short rcvtimeo and a
        -- longer sndtimeo -- read must honour rcvtimeo.
        local plain = require('net.stream.inet')
        local raw = assert(plain.client.new(host, port))
        raw:read(nil, 5) -- keep the connection alive without sending
        raw:close()
        return
    end
    local peer = assert(s:accept())
    assert(peer:rcvtimeo(1))
    assert(peer:sndtimeo(5))

    local gettime = require('time.clock').gettime
    local t0 = gettime()
    local msg, err, timeout = peer:read()
    local elapsed = gettime() - t0

    assert.is_nil(msg)
    assert.is_nil(err)
    assert.is_true(timeout, 'read must surface timeout=true')
    assert(elapsed < 1.5,
           string.format(
               'handshake during read took %.3fs, expected within rcvtimeo' ..
                   ' (1s) plus jitter; bug allowed up to sndtimeo (5s)', elapsed))

    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.write_read_bio_large_payload()
    -- SSL_MODE_ENABLE_PARTIAL_WRITE is enabled on the client SSL_CTX, so a
    -- plaintext payload larger than a single TLS record is delivered in
    -- multiple SSL_write returns.  The client-side write wrapper must loop
    -- on the "partial" indication until every byte reaches the peer.  A
    -- 32 KiB payload spans two records and reliably exercises the partial
    -- path without exhausting the SO_SNDBUF / SO_RCVBUF of the loopback
    -- socket pair.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = string.rep('X', 32 * 1024)

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        assert(c.tls_bio ~= nil, 'BIO not set on client')
        assert(c:write(msg))
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on server peer')

    local buf = {}
    local total = 0
    while total < #msg do
        local chunk = peer:read()
        if not chunk then
            break
        end
        buf[#buf + 1] = chunk
        total = total + #chunk
    end
    peer:close()
    s:close()
    assert(p:wait())
    assert.equal(total, #msg)
    assert.equal(table.concat(buf), msg)
end

function testcase.close_bio_after_peer_close_notify()
    -- Regression: once the peer's close_notify has been received,
    -- SSL_shutdown() completes immediately, but the TX BIO still holds the
    -- final close_notify ciphertext.  close() must drain it to the socket
    -- and succeed instead of failing with EINVAL on the freed BIO.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        assert(c:write(msg))
        -- wait for the server to close first so the peer's close_notify is
        -- already received when we close
        local r = c:read()
        assert.is_nil(r, 'expected EOF before close')
        assert(c:close(), 'close after peer close_notify must succeed')
        return
    end
    local peer = assert(s:accept())
    assert.equal(peer:read(), msg)
    -- the initiator path (SSL_shutdown == 0 -> drain -> retry) must also
    -- succeed
    assert(peer:close(), 'initiator close must succeed')
    s:close()
    assert(p:wait())
end

function testcase.close_bio_idempotent()
    -- close() must be idempotent: the second call disposes nothing extra
    -- and must not touch the already-freed BIO.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c = assert(inet.client.new(host, port, {
        tlscfg = {
            noverify_name = CLIENT_CONFIG.noverify_name,
            noverify_time = CLIENT_CONFIG.noverify_time,
            noverify_cert = CLIENT_CONFIG.noverify_cert,
            use_bio = true,
        },
    }))
    assert(c.tls_bio ~= nil, 'BIO not set on client')
    -- closing before the handshake must also succeed and be idempotent
    assert(c:close())
    assert(c:close())
    s:close()
end

function testcase.server_sni_callback_raises_non_string_error()
    -- A Lua error raised through the SNI callback reaches the C callback
    -- handler as a value of any type; a non-string error must not be
    -- passed to fprintf("%s") as NULL.  The handshake fails with a fatal
    -- alert and the server process must survive.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    s:set_sni_callback(function()
        error({
            code = 42,
        })
    end)

    local p = fork()
    if p:is_child() then
        s:close()
        local c, err = inet.client.new(host, port, {
            servername = 'www.example.com',
            tlscfg = CLIENT_CONFIG,
        })
        -- the handshake must fail with a fatal alert
        assert.is_nil(c)
        assert.match(tostring(err), 'alert|handshake|ssl|certificate', false)
        return
    end

    local peer = s:accept()
    assert(peer, 'server must accept the connection')
    local msg, rerr = peer:read()
    assert.is_nil(msg)
    assert(rerr, 'read must surface the handshake failure')
    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.sni_callback_runs_on_handshake_coroutine()
    -- The SNI callback must execute on the lua_State driving SSL_accept.
    -- Running the accepted peer's handshake from a coroutine leaves the
    -- state that created the server object suspended, so a stale
    -- tls_server_t.L would drive the Lua callback on a suspended state.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        tlscfg = SERVER_CONFIG,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = 'hello'
    local ncall = 0

    s:set_sni_callback(function(name)
        ncall = ncall + 1
        assert.equal(name, 'www.example.com')
        return assert(new_tls_server(SERVER_CONFIG.cert, SERVER_CONFIG.key))
    end)

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            servername = 'www.example.com',
            tlscfg = CLIENT_CONFIG,
        }))
        assert(c:send(msg))
        c:read()
        c:close()
        return
    end

    local peer = assert(s:accept())
    -- drive the handshake and the data transfer from a coroutine
    coroutine.wrap(function()
        assert.equal(peer:recv(), msg)
    end)()
    peer:close()
    s:close()
    assert(p:wait())
    assert.equal(ncall, 1)
end

function testcase.read_returns_data_with_pending_txbuf()
    -- A read() whose SSL_read succeeded must return the received string
    -- even when the TX BIO still holds unsent ciphertext.  Before the
    -- fix, read() called bio_drain() after the successful read and let
    -- its error discard the already-received plaintext.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        sndbuf = 2048,
        rcvbuf = 2048,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local msg = string.rep('hello-', 4000)
    local ping = 'ping'

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            sndbuf = 2048,
            rcvbuf = 2048,
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        -- the client sends a small message and never reads our writes;
        -- the socket buffers saturate and our TX BIO keeps ciphertext.
        assert(c:write(ping))
        sleep(1)
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')
    assert(peer:sndtimeo(3))

    -- saturate the pipe so the writes leave ciphertext pending in txbuf
    for _ = 1, 40 do
        assert(peer:write(msg))
    end

    -- the client's "ping" has already been received; read() must return
    -- it regardless of the pending drain state.
    local got = peer:read()
    assert.is_string(got, 'read must return the received string')
    assert.equal(got, ping)

    peer:close()
    s:close()
    assert(p:wait())
end

function testcase.write_drain_error_keeps_sent()
    -- Go-style contract: when the TX BIO drain fails after OpenSSL
    -- accepted the plaintext, write() must report the accepted byte
    -- count with (sent, err) instead of discarding it with nil —
    -- re-sending accepted plaintext would duplicate it on the wire.
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, {
        reuseaddr = true,
        reuseport = true,
        sndbuf = 2048,
        rcvbuf = 2048,
        tlscfg = {
            cert = SERVER_CONFIG.cert,
            key = SERVER_CONFIG.key,
            use_bio = true,
        },
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()
    local big = string.rep('hello-', 4000)

    local p = fork()
    if p:is_child() then
        s:close()
        local c = assert(inet.client.new(host, port, {
            sndbuf = 2048,
            rcvbuf = 2048,
            tlscfg = {
                noverify_name = CLIENT_CONFIG.noverify_name,
                noverify_time = CLIENT_CONFIG.noverify_time,
                noverify_cert = CLIENT_CONFIG.noverify_cert,
                use_bio = true,
            },
        }))
        -- complete the handshake, then close the connection so the
        -- server's later drains hit EPIPE
        assert(c:write('ping'))
        c:read()
        sleep(1)
        c:close()
        return
    end

    local peer = assert(s:accept())
    assert(peer.tls_bio ~= nil, 'BIO not set on peer')
    assert.equal(peer:read(), 'ping')
    assert(peer:sndtimeo(5))

    -- keep writing until the drain fails; the accepted plaintext count
    -- must survive the failure.
    local failed = false
    for _ = 1, 300 do
        local sent, err, timeout = peer:write(big)
        if err then
            assert.is_nil(timeout)
            -- Go style: the sent count must survive the failure (0 when
            -- nothing had been accepted yet, never nil).
            assert.is_number(sent, 'sent must stay a number on failure')
            assert(sent >= 0)
            assert(err.type == errno.EPIPE or err.type == errno.ECONNRESET,
                   'unexpected drain error: ' .. tostring(err))
            failed = true
            break
        end
    end
    assert.is_true(failed, 'drain must fail within 300 writes')

    peer:close()
    s:close()
    assert(p:wait())
end
