local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local context_helpers = require('test.tls.context.helpers')
local assert = require('assert')
local socket = require('net.socket')
local wait = require('io.wait')
local tls_context = require('net.tls.context')
local DEADLINE = context_helpers.DEADLINE
local new_ep = context_helpers.new_ep
local handshake = context_helpers.handshake
local transfer_write = context_helpers.transfer_write
local transfer_read = context_helpers.transfer_read
local close_ep = context_helpers.close_ep
local new_tls_server = support.new_tls_server
local new_tls_client = support.new_tls_client
local free_port = support.free_port
local start_s_server = support.start_s_server
local start_s_client = support.start_s_client
local start_s_client_with_ca = support.start_s_client_with_ca
local wait_listen = support.wait_listen
local get_server_config = support.get_server_config
local get_chain_fixture_dir = support.get_chain_fixture_dir

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.accept_s_client()
    -- Memory-BIO server accept against openssl s_client: verify
    -- SSL_accept handshake plus bidirectional plaintext transfer.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client(port)
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    -- wrap() guarantees non-blocking on platforms where accept() does not
    -- inherit O_NONBLOCK from the listening socket. Keep the wrapper alive
    -- so its __gc does not close the fd while the TLS context still uses it.
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local ctx = assert(tls_context.accept(server, fd, {
        bufcap = 1,
    }))
    local ep = new_ep(ctx, 'server', fd)
    assert(ep.bio, 'BIO not set on server context')
    assert.match(tostring(ep.bio), '^net.tls.bio: ', false)

    assert(handshake(ep))
    -- 'A' avoids the CLI's connected-command characters.
    assert(transfer_read(ep, proc, string.rep('A', 4096)))
    assert(transfer_write(ep, proc, string.rep('A', 4096)))
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.connect_s_server()
    -- Memory-BIO client connect against openssl s_server: verify
    -- SSL_connect handshake plus bidirectional transfer.
    local port = free_port()
    local proc = start_s_server(port)
    local csock = assert(wait_listen(port))
    local socks = {
        csock,
    }
    local fd = csock:fd()

    local client = assert(new_tls_client())
    local ctx = assert(tls_context.connect(client, fd, {
        verify_name = false,
        verify_cert = false,
        bufcap = 1,
    }))
    local ep = new_ep(ctx, 'client', fd)
    assert(ep.bio, 'BIO not set on client context')

    assert(handshake(ep))
    assert(transfer_write(ep, proc, string.rep('A', 4096)))
    assert(transfer_read(ep, proc, string.rep('A', 4096)))
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.accept_s_client_fullchain()
    -- socket-BIO server accept: the server loads fullchain.pem (leaf +
    -- intermediate) while s_client trusts the root CA only, so the
    -- handshake verifies only when the intermediate is actually sent.
    local lsock = assert(socket.bind_inet('127.0.0.1', 0, {
        socktype = 'stream',
        protocol = 'tcp',
        reuseaddr = true,
        reuseport = true,
    }))
    local socks = {
        lsock,
    }
    assert(lsock:listen())
    local port = assert(lsock:getsockname()):port()

    local proc = start_s_client_with_ca(port,
                                        get_chain_fixture_dir() .. '/root.crt')
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    -- wrap() guarantees non-blocking; keep the wrapper alive so its __gc
    -- does not close the fd while the TLS context still uses it.
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(
                              get_chain_fixture_dir() .. '/fullchain.pem',
                              get_chain_fixture_dir() .. '/leaf.key'))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert(transfer_read(ep, proc, 'hello from client'))
    assert(transfer_write(ep, proc, 'hello from server'))
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end
