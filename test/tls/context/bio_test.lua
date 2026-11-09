local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local fork = require('testcase.fork')
local run_child = require('test.fork_helpers')
local signal = require('testcase.signal')
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local wait = require('io.wait')
local tls_context = require('net.tls.context')
local DEADLINE = context_helpers.DEADLINE
local new_ep = context_helpers.new_ep
local make_loopback_pair = context_helpers.make_loopback_pair
local handshake = context_helpers.handshake
local close_ep = context_helpers.close_ep
local new_tls_server = support.new_tls_server
local new_tls_client = support.new_tls_client
local free_port = support.free_port
local start_s_server = support.start_s_server
local wait_listen = support.wait_listen
local get_server_config = support.get_server_config
local UNVERIFIED = { verify_name = false, verify_cert = false }

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.connect_bio_bufcap_too_large()
    -- unreasonable bufcap makes BUF_MEM_grow fail; the fix must return
    -- (nil, error) rather than double-free abort.
    local client = assert(new_tls_client())
    for _, bufcap in ipairs({
        2147483000, -- just below INT_MAX
        2147483648, -- INT_MAX + 1
        4611686018427387904, -- 2^62
    }) do
        local sp = assert(socket.pair({
            socktype = 'stream',
        }))
        -- huge bufcap makes BUF_MEM_grow fail; before the fix this aborted
        -- with a double free, after the fix connect returns (nil, error).
        local ctx, err = tls_context.connect(client, sp[1]:fd(), {
            verify_name = false,
            verify_cert = false,
            bufcap = bufcap,
        })
        assert.is_nil(ctx)
        assert(err, 'connect must surface the bio_buf_init failure')
        sp[1]:close()
        sp[2]:close()
    end
end

function testcase.connect_bio_bufcap_no_int_truncation()
    -- 2^32 + 1000 used to narrow to int 1000 in tls_bio_new() and silently
    -- create undersized buffers; the unallocatable request must surface as
    -- (nil, error) instead.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx, err = tls_context.connect(client, sp[1]:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 4294968296,
    })
    assert.is_nil(ctx)
    assert(err, 'connect must surface the unallocatable bufcap as an error')
    sp[1]:close()
    sp[2]:close()
end

function testcase.accept_bio_bufcap_no_int_truncation()
    -- accept() shares tls_bio_new() with connect(); the same narrowing
    -- regression must not silently create undersized buffers there either.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local ctx, err = tls_context.accept(server, sp[1]:fd(), {
        bufcap = 4294968296,
    })
    assert.is_nil(ctx)
    assert(err, 'accept must surface the unallocatable bufcap as an error')
    sp[1]:close()
    sp[2]:close()
end

function testcase.connect_bio_bufcap_exact()
    -- a representable bufcap above the minimum is honoured as-is: the empty
    -- ring reports exactly the requested writable space.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local cap = 1048576
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = cap,
    }))
    local bio = assert(ctx:get_bio())
    local _, space_len = bio:space()
    assert.equal(space_len, cap)
    sp[1]:close()
    sp[2]:close()
end

function testcase.bio_fill_returns_total_when_rxbuf_full()
    -- fill() must return the byte count when the ring saturates, not 0;
    -- the buggy loop retried into NULL and read(fd, NULL, 0) == 0 spelt EOF.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local csock, ssock = sp[1], sp[2]
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())
    local _, space_len = bio:space()
    assert.greater(space_len, 0)

    -- peer sends more than bufcap so a single fill() saturates the ring.
    local payload = string.rep('X', space_len + 100)
    assert(ssock:sndbuf(#payload))
    assert(csock:rcvbuf(#payload))
    assert.equal(ssock:write(payload), #payload)
    -- The fill() call must read the entire rxbuf capacity, not EOF.
    local total, err, again = bio:fill()
    assert.equal(total, space_len)
    assert.is_nil(err)
    assert.is_nil(again)

    csock:close()
    ssock:close()
end

function testcase.bio_userdata_methods()
    -- Inspect RX space and the empty TX buffer without a handshake.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local csock, ssock = sp[1], sp[2]
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())

    -- space() exposes the writable RX region before fill() receives data.
    local space_ptr, space_len = bio:space()
    assert.not_nil(space_ptr)
    assert.greater(space_len, 0)

    assert.equal(ssock:write('AB'), 2)
    local n = assert(bio:fill())
    assert.greater(n, 0)

    -- peek reveals the readable region without consuming; peek on an
    -- empty tx buffer returns nil / 0.
    local tx_ptr, tx_len = bio:peek()
    assert.is_nil(tx_ptr)
    assert.equal(tx_len, 0)

    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.bio_consume_and_commit_reject_negative_offsets()
    -- consume/commit build their error message via snprintf + lua_error
    -- because lua_pushvfstring on Lua 5.3+ refuses %lld.  Passing a
    -- negative offset must therefore raise with the formatted message
    -- intact rather than an "invalid option '%l'" pushfstring error.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())

    local cerr = assert.throws(function()
        bio:consume(-1)
    end)
    assert.match(cerr, 'consume(-1): out of range', true)

    local merr = assert.throws(function()
        bio:commit(-1)
    end)
    assert.match(merr, 'commit(-1): out of range', true)

    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.bio_fill_returns_eagain_on_empty_socket()
    -- fill on an idle socket must surface EAGAIN via the (nil, nil, again)
    -- return convention.  This drives tls_bio.c's RETRY / EAGAIN branch.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())

    local n, err, again = bio:fill()
    assert.is_nil(n)
    assert.is_nil(err)
    assert.is_true(again)

    ctx:close()
    csock:close()
    ssock:close()
end

function testcase.bio_peek_returns_data_after_ssl_write()
    -- After a full BIO handshake and SSL_write, the tx ring holds
    -- ciphertext; peek() must return a lightuserdata pointer and length.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local ep = new_ep(ctx, 'client', fd)
    assert(handshake(ep))

    -- SSL_write pushes ciphertext into txbuf; drain() has not run yet
    -- inside our helper because we call write() directly on the ctx.
    local bio = assert(ctx:get_bio())
    assert(ctx:write('hi'))
    local ptr, len = bio:peek()
    assert.not_nil(ptr)
    assert.greater(len, 0)

    -- drain so proc doesn't block on the next iteration
    assert(bio:drain())

    assert(close_ep(ep))
    csock:close()
    proc:close()
end

function testcase.drain_survives_sigpipe_after_shutdown_wr()
    -- Draining the TX ring after the local write direction is shut down
    -- must surface EPIPE as a Lua error object, not kill the process with
    -- SIGPIPE.  The child runs with SIGPIPE at its default disposition so
    -- the runner's SIGPIPE ignore cannot mask the behaviour; the parent
    -- detects a SIGPIPE death via the wait status.
    local proc = assert(fork())
    if proc:is_child() then
        run_child(function()
            assert(signal.sigdefault('SIGPIPE'))

            -- the first handshake call emits the ClientHello into the TX ring
            -- and then reports WANT_READ; shutting down the write direction
            -- makes the subsequent drain() fail deterministically
            local socks = assert(socket.pair({
                socktype = 'stream',
            }))
            local client = assert(new_tls_client())
            local ctx = assert(tls_context.connect(client, socks[1]:fd(), {
                verify_name = false,
                verify_cert = false,
                bufcap = 1,
            }))
            local bio = assert(ctx:get_bio())
            local ok = ctx:handshake()
            assert(not ok, 'handshake must not complete without a TLS peer')

            assert(socks[1]:shutdown('wr'))
            local n, derr = bio:drain()
            assert.is_nil(n)
            assert.equal(derr.type, errno.EPIPE)
        end)
    end
    local stat = assert(proc:wait())
    assert.is_nil(stat.sigterm)
    assert.equal(stat.exit, 0)
end

function testcase.bio_space_returns_nil_when_rxbuf_full()
    -- After fill saturates the rx ring, space() must expose the "no room"
    -- return (nil, 0) branch instead of a valid pointer.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local csock, ssock = sp[1], sp[2]
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())
    local _, space_len = bio:space()
    local payload = string.rep('X', space_len + 100)
    assert(ssock:sndbuf(#payload))
    assert(csock:rcvbuf(#payload))
    assert.equal(ssock:write(payload), #payload)
    local total = assert(bio:fill())
    assert.equal(total, space_len)

    local ptr, len = bio:space()
    assert.is_nil(ptr)
    assert.equal(len, 0)

    csock:close()
    ssock:close()
end

function testcase.bio_fill_and_drain_after_close_return_einval()
    -- Once ctx:close() releases the BIO, its fd is set to -1; fill/drain
    -- must surface EINVAL through the fd<0 gate.
    local csock, ssock = make_loopback_pair()
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, csock:fd(), {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local bio = assert(ctx:get_bio())
    assert(ctx:close())

    local n, ferr = bio:fill()
    assert.is_nil(n)
    assert.equal(ferr.type, errno.EINVAL)

    local d, derr = bio:drain()
    assert.is_nil(d)
    assert.equal(derr.type, errno.EINVAL)

    csock:close()
    ssock:close()
end

function testcase.bio_methods_reusable_across_many_connections()
    -- BIO_METHOD objects are created per connection; the composed type is
    -- cached and shared so that BIO_get_new_index()'s small budget is not
    -- drained.  Creating many sequential connections must keep succeeding
    -- (a per-connection index would exhaust the budget at ~64).
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
    }))
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()
    local client = assert(new_tls_client())

    for _ = 1, 70 do
        local csock = assert(socket.connect_inet('127.0.0.1', port, {
            socktype = 'stream',
            protocol = 'tcp',
        }))
        assert(wait.readable(lsock:fd(), DEADLINE))
        local ssock = assert(lsock:accept())
        local ctx, err = tls_context.connect(client, csock:fd(), UNVERIFIED)
        assert(ctx, err and tostring(err) or
                   'connect must keep succeeding across 70 connections')
        assert(ctx:get_bio())
        assert(ctx:close())
        assert(ctx:shutdown())
        csock:close()
        ssock:close()
    end
    lsock:close()
end

function testcase.bio_methods_after_ctx_close()
    -- get_bio() exposes the BIO userdata to Lua; after ctx:close() freed the
    -- BUF_MEM backing, space()/peek() used to hand out lightuserdata into
    -- the freed region (use-after-free).  Every method must report EINVAL
    -- on the freed BIO instead.
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), UNVERIFIED))
    local bio = assert(ctx:get_bio())

    assert(ctx:close())

    -- space() / peek() must not return a lightuserdata into freed memory
    local sptr, slen = bio:space()
    assert.is_nil(sptr)
    assert.equal(slen.type, errno.EINVAL)
    local pptr, plen = bio:peek()
    assert.is_nil(pptr)
    assert.equal(plen.type, errno.EINVAL)

    -- commit() / consume() / fill() / drain() must report EINVAL
    local ok, cerr = bio:commit(0)
    assert.is_nil(ok)
    assert.equal(cerr.type, errno.EINVAL)
    ok, cerr = bio:consume(0)
    assert.is_nil(ok)
    assert.equal(cerr.type, errno.EINVAL)
    local n, ferr = bio:fill()
    assert.is_nil(n)
    assert.equal(ferr.type, errno.EINVAL)
    n, ferr = bio:drain()
    assert.is_nil(n)
    assert.equal(ferr.type, errno.EINVAL)

    sp[1]:close()
    sp[2]:close()
end
