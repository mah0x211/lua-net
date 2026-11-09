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
local close_ep = context_helpers.close_ep
local new_tls_server = support.new_tls_server
local new_tls_client = support.new_tls_client
local free_port = support.free_port
local start_s_server = support.start_s_server
local start_s_client = support.start_s_client
local wait_listen = support.wait_listen
local get_server_config = support.get_server_config
local UNVERIFIED = { verify_name = false, verify_cert = false }

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.accept_s_client_alpn()
    -- ALPN 'h2' negotiation on the server side against s_client.
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

    local proc = start_s_client(port, 'h2')
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key, 'default',
                                         'default', {
        'h2',
    }, 300))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    assert(handshake(ep))
    assert.equal(ep.ctx:get_alpn(), 'h2')
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.accept_s_client_alpn_mismatch_fails_handshake()
    -- RFC 7301 requires the server to abort the handshake with a fatal
    -- no_application_protocol alert when the client and server ALPN
    -- lists share no protocol.
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

    local proc = start_s_client(port, 'h2')
    assert(wait.readable(lsock:fd(), DEADLINE))
    local afd = assert(lsock:acceptfd())
    local asock = assert(socket.wrap(afd))
    socks[#socks + 1] = asock
    local fd = asock:fd()

    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key, 'default',
                                         'default', {
        'http/1.1',
    }, 300))
    local ctx = assert(tls_context.accept(server, fd))
    local ep = new_ep(ctx, 'server', fd)

    local ok, err = handshake(ep)
    assert.is_false(ok)
    assert.not_nil(err)

    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.connect_s_server_alpn()
    -- ALPN 'h2' negotiation on the client side against s_server.
    local port = free_port()
    local proc = start_s_server(port, 'h2')
    local csock = assert(wait_listen(port))
    local socks = {
        csock,
    }
    local fd = csock:fd()

    local client = assert(new_tls_client('default', 'default', {
        'h2',
    }, 0, 0))
    local ctx = assert(tls_context.connect(client, fd, UNVERIFIED))
    local ep = new_ep(ctx, 'client', fd)

    assert(handshake(ep))
    assert.equal(ep.ctx:get_alpn(), 'h2')
    assert(close_ep(ep))
    for _, s in ipairs(socks) do
        s:close()
    end
    proc:close()
end

function testcase.new_server_alpn_invalid()
    local config = get_server_config()
    -- ALPN validation rejects non-string entries and >255-byte protocols.
    assert.throws(function()
        new_tls_server(config.cert, config.key, 'default', 'default', {
            123,
        })
    end)
    assert.throws(function()
        new_tls_server(config.cert, config.key, 'default', 'default', {
            string.rep('x', 256),
        })
    end)
end

function testcase.new_client_alpn_invalid()
    -- ALPN validation rejects non-string entries and >255-byte protocols.
    -- non-string element
    assert.throws(function()
        new_tls_client('default', 'default', {
            123,
        })
    end)
    assert.throws(function()
        new_tls_client('default', 'default', {
            string.rep('x', 256),
        })
    end)
end

function testcase.new_client_alpn_total_length_invalid()
    -- RFC 7301 limits the wire-format ProtocolNameList to 65535 bytes;
    -- each element contributes 1 length byte plus its name, so a list of
    -- 256 elements x 255-byte names reaches 65536 bytes and must be
    -- rejected before it reaches OpenSSL.
    local protos = {}
    for i = 1, 256 do
        protos[i] = string.rep('x', 255)
    end
    assert.throws(function()
        new_tls_client('default', 'default', protos)
    end)
end

function testcase.new_client_alpn_total_length_at_limit()
    -- A list whose wire format totals exactly 65535 bytes stays within
    -- the RFC 7301 limit and must be accepted: 255 elements x 256 bytes
    -- (1 length byte + 255-byte name) plus one 254-byte name.
    local protos = {}
    for i = 1, 255 do
        protos[i] = string.rep('x', 255)
    end
    protos[256] = string.rep('y', 254)
    local ctx, err = new_tls_client('default', 'default', protos)
    assert(ctx, err)
end
