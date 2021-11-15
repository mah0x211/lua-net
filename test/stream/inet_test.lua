require('luacov')
require('nosigpipe')
local assert = require('assertex')
local testcase = require('testcase')
local net = require('net')
local inet = require('net.stream.inet')

function testcase.server_new()
    local host = '127.0.0.1'

    -- test that create new net.stream.inet.Server
    local s, _, ai = assert(inet.server.new(host, 0, true, true))
    assert.match(tostring(s), '^net.stream.inet.Server: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(not s.nonblock, 'nonblocking mode')
    assert.equal(s:family(), net.AF_INET)
    assert.equal(s:socktype(), net.SOCK_STREAM)
    assert.equal(s:protocol(), net.IPPROTO_TCP)
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.greater(ai:port(), 0)
    s:close()

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.server.new('invalid hostname', 0)
    assert.match(err, 'not known')
    _, err = inet.server.new(host, 'invalid servname')
    assert(err, 'server created with invalid servname')

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.server.new(host, 0, {})
    end), 'reuseaddr must be boolean', false)

    assert.match(assert.throws(function()
        inet.server.new(host, 0, nil, {})
    end), 'reuseport must be boolean', false)
end

function testcase.client_new()
    local host = '127.0.0.1'
    local s = assert(inet.server.new(host, 0, true, true))
    local sai = assert(s:getsockname())
    local port = assert(sai:port())

    -- NOTE: it returns a connection refused error on linux platform
    -- test that timedout
    -- local c, err, timeout, ai = inet.client.new(host, port, 100)
    -- assert.is_nil(c)
    -- assert.is_true(timeout)
    -- assert.is_nil(err)
    -- assert.is_nil(ai)

    -- test that return client
    assert(s:listen())
    local c, err, timeout, ai = assert(inet.client.new(host, port, 100))
    assert.match(tostring(c), '^net.stream.inet.Client: ', false)
    assert.match(tostring(ai), '^llsocket.addrinfo: ', false)
    assert(not c.nonblock, 'c.nonblock is not false')
    assert.equal(c:family(), net.AF_INET)
    assert.equal(c:socktype(), net.SOCK_STREAM)
    assert.equal(c:protocol(), net.IPPROTO_TCP)
    c:close()
    s:close()

    -- test that returns error that refuse
    c, err, timeout = inet.client.new(host, port, 100)
    assert.is_nil(c)
    assert.match(err, 'refused')
    assert.is_nil(timeout)

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.client.new(host, port, {})
    end), 'conndeadl must be uint', false)
end
