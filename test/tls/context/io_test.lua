local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local errno = require('errno')
local error_is = require('error').is
local socket = require('net.socket')
local tls_context = require('net.tls.context')
local tls_inet = require('net.tls.stream.inet')
local new_ep = context_helpers.new_ep
local make_loopback_pair = context_helpers.make_loopback_pair
local handshake_pair = context_helpers.handshake_pair
local exec = support.exec
local new_tls_server = support.new_tls_server
local new_tls_client = support.new_tls_client
local free_port = support.free_port
local wait_listen = support.wait_listen
local get_server_config = support.get_server_config
local UNVERIFIED = { verify_name = false, verify_cert = false }

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.read_receives_data_after_many_tls13_tickets()
    for _, num_tickets in ipairs({
        2,
        20,
    }) do
        local port = free_port()
        local proc = assert(exec('openssl', {
            's_server',
            '-accept',
            '127.0.0.1:' .. tostring(port),
            '-cert',
            get_server_config().cert,
            '-key',
            get_server_config().key,
            '-quiet',
            '-naccept',
            '1',
            '-tls1_3',
            '-num_tickets',
            tostring(num_tickets),
        }))
        local sock = assert(wait_listen(port))
        local client = assert(new_tls_client('tlsv1.3'))
        local ctx = assert(tls_context.connect(client, sock:fd(), UNVERIFIED))
        local peer = tls_inet.Client(sock, ctx)
        assert(peer:rcvtimeo(1))
        assert(peer:sndtimeo(1))
        assert(peer:handshake())

        local message = 'hello after tickets\n'
        assert(proc.stdin:write(message))
        local data, err, timeout = peer:read()

        -- Keep the server input open until read completes: neither another
        -- record nor EOF should be needed to deliver the buffered message.
        peer:close()
        local closed = assert(proc:close())
        assert.equal(closed.exit, 0)
        assert.is_nil(err)
        assert.is_nil(timeout)
        assert.equal(data, message)
    end
end

function testcase.read_times_out_without_data_and_with_incomplete_record()
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client('tlsv1.3'))
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key, 'tlsv1.3'))
    local cctx = assert(tls_context.connect(client, csock:fd(), UNVERIFIED))
    local sctx = assert(tls_context.accept(server, ssock:fd()))
    assert(handshake_pair(new_ep(cctx, 'client', csock:fd()),
                          new_ep(sctx, 'server', ssock:fd())))
    local peer = tls_inet.Client(csock, cctx)
    assert(peer:rcvtimeo(0.05))
    assert(peer:handshake())

    local data, err, timeout = peer:read()
    assert.is_nil(data)
    assert.is_nil(err)
    assert.is_true(timeout)

    -- A TLS application-data header declaring five bytes of ciphertext,
    -- followed by only one byte: read must wait for the missing bytes.
    assert.equal(ssock:write('\23\3\3\0\5\0'), 6)
    data, err, timeout = peer:read()
    assert.is_nil(data)
    assert.is_nil(err)
    assert.is_true(timeout)

    cctx:close()
    peer:close()
    sctx:close()
    ssock:close()
end

function testcase.write_read_edge_lengths()
    -- write of an empty string is rejected like the plain socket write
    -- and never reaches SSL_write. A non-positive read size is also rejected.
    -- Neither branch needs a completed handshake; using a
    -- not-yet-handshaked ctx keeps the test self-contained.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), UNVERIFIED))

    -- empty payload: the write is rejected with EINVAL before SSL_write
    -- is invoked, matching the plain socket write.
    local n, werr = ctx:write('')
    assert.is_nil(n)
    assert.not_nil(error_is(werr, errno.EINVAL))

    -- a non-positive bufsiz is rejected with EINVAL like the plain
    -- socket read; passing 0 through to SSL_read made the retry loop
    -- block until the receive deadline.
    local s, rerr = ctx:read(0)
    assert.is_nil(s)
    assert.not_nil(error_is(rerr, errno.EINVAL))
    s, rerr = ctx:read(-1)
    assert.is_nil(s)
    assert.not_nil(error_is(rerr, errno.EINVAL))

    ctx:close()
    sp[1]:close()
    sp[2]:close()
end
