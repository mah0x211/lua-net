local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')
local stream = require('net.stream.inet')
local dgram = require('net.dgram.inet')

local INPUTS = {
    {
        host = '127.0.0.1\0unexpected',
        port = 0,
        argument = 1,
    },
    {
        host = '127.0.0.1',
        port = '0\0unexpected',
        argument = 2,
    },
}
local DGRAM

function testcase.after_each()
    if DGRAM then
        DGRAM:close()
        DGRAM = nil
    end
end

function testcase.socket_bind_inet_rejects_embedded_nul()
    for _, input in ipairs(INPUTS) do
        local err = assert.throws(function()
            socket.bind_inet(input.host, input.port)
        end)
        assert.match(err, 'bad argument #' .. input.argument)
        assert.match(err, 'NUL')
    end
end

function testcase.socket_connect_inet_rejects_embedded_nul()
    for _, input in ipairs(INPUTS) do
        local err = assert.throws(function()
            socket.connect_inet(input.host, input.port)
        end)
        assert.match(err, 'bad argument #' .. input.argument)
        assert.match(err, 'NUL')
    end
end

function testcase.stream_client_new_rejects_embedded_nul()
    for _, input in ipairs(INPUTS) do
        local err = assert.throws(function()
            stream.client.new(input.host, input.port)
        end)
        assert.match(err, 'bad argument #' .. input.argument)
        assert.match(err, 'NUL')
    end
end

function testcase.stream_server_new_rejects_embedded_nul()
    for _, input in ipairs(INPUTS) do
        local err = assert.throws(function()
            stream.server.new(input.host, input.port)
        end)
        assert.match(err, 'bad argument #' .. input.argument)
        assert.match(err, 'NUL')
    end
end

function testcase.dgram_bind_rejects_embedded_nul()
    DGRAM = assert(dgram.new())
    for _, input in ipairs(INPUTS) do
        local err = assert.throws(function()
            DGRAM:bind(input.host, input.port)
        end)
        assert.match(err, 'bad argument #' .. input.argument)
        assert.match(err, 'NUL')
    end
end

function testcase.dgram_connect_rejects_embedded_nul()
    DGRAM = assert(dgram.new())
    for _, input in ipairs(INPUTS) do
        local err = assert.throws(function()
            DGRAM:connect(input.host, input.port)
        end)
        assert.match(err, 'bad argument #' .. input.argument)
        assert.match(err, 'NUL')
    end
end
