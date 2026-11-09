local testcase = require('testcase')
local support = require('test.tls.context.support').new()
local assert = require('assert')
local errno = require('errno')
local socket = require('net.socket')
local tls_context = require('net.tls.context')
local new_tls_server = support.new_tls_server
local new_tls_client = support.new_tls_client
local get_server_config = support.get_server_config

function testcase.after_each()
    support.after_each()
end

function testcase.after_all()
    support.after_all()
end

function testcase.accept_rejects_out_of_range_fd()
    -- accept() used to cast the lua_Integer fd straight to int, so an
    -- out-of-range value could wrap onto an unrelated fd number and be
    -- handed to OpenSSL.  It must fail with EINVAL instead.
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))

    local ctx, err = tls_context.accept(server, 2147483648)
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    ctx, err = tls_context.accept(server, -1)
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)
end

function testcase.connect_rejects_out_of_range_fd()
    -- connect() has the same lua_Integer-to-int truncation hazard as
    -- accept(); out-of-range fds must fail with EINVAL.
    local client = assert(new_tls_client())

    local ctx, err = tls_context.connect(client, 2147483648)
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)

    ctx, err = tls_context.connect(client, -1)
    assert.is_nil(ctx)
    assert(err)
    assert.equal(err.type, errno.EINVAL)
end

function testcase.accept_rejects_invalid_options()
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    for _, opts in ipairs({
        1,
        {
            bufcap = 'invalid',
        },
        {
            bufcap = '1',
        },
        {
            [1] = 1,
        },
    }) do
        assert.throws(function()
            tls_context.accept(server, -1, opts)
        end)
    end
end

function testcase.connect_rejects_invalid_options()
    local client = assert(new_tls_client())
    for _, opts in ipairs({
        'server.example',
        {
            host = 123,
        },
        {
            port = {},
        },
        {
            port = -1,
        },
        {
            port = 1.5,
        },
        {
            port = 65536,
        },
        {
            servername = {},
        },
        {
            servername = 123,
        },
        {
            verify_name = 'false',
        },
        {
            verify_time = 'false',
        },
        {
            verify_cert = 'false',
        },
        {
            bufcap = 'invalid',
        },
        {
            bufcap = '1',
        },
        {
            [1] = 1,
        },
    }) do
        assert.throws(function()
            tls_context.connect(client, -1, opts)
        end)
    end
end

function testcase.connect_options_ignore_index_metamethod()
    local client = assert(new_tls_client())
    local opts = setmetatable({}, {
        __index = function()
            error('__index must not be called')
        end,
    })
    local ctx, err = tls_context.connect(client, -1, opts)
    assert.is_nil(ctx)
    assert.equal(err.type, errno.EINVAL)
end

function testcase.accept_options_ignore_index_metamethod()
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local opts = setmetatable({}, {
        __index = function()
            error('__index must not be called')
        end,
    })
    local ctx, err = tls_context.accept(server, -1, opts)
    assert.is_nil(ctx)
    assert.equal(err.type, errno.EINVAL)
end

function testcase.connect_options_table()
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local client = assert(new_tls_client())
    local cap = 1048576
    local ctx = assert(tls_context.connect(client, sp[1]:fd(), {
        verify_name = false,
        verify_time = true,
        verify_cert = false,
        bufcap = cap,
    }))
    local _, space_len = assert(ctx:get_bio()):space()
    assert.equal(space_len, cap)
    assert(ctx:close())
    sp[1]:close()
    sp[2]:close()
end

function testcase.accept_options_table()
    local sp = assert(socket.pair({
        socktype = 'stream',
    }))
    local server = assert(new_tls_server(get_server_config().cert,
                                         get_server_config().key))
    local cap = 1048576
    local ctx = assert(tls_context.accept(server, sp[1]:fd(), {
        bufcap = cap,
    }))
    local _, space_len = assert(ctx:get_bio()):space()
    assert.equal(space_len, cap)
    assert(ctx:close())
    sp[1]:close()
    sp[2]:close()
end
