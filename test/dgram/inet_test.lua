require('luacov')
local testcase = require('testcase')
local errno = require('errno')
local errno_eai = require('errno.eai')
local net = require('net')
local inet = require('net.dgram.inet')

function testcase.new()
    -- test that create new instance of net.dgram.inet.Socket
    local s = assert(inet.new())
    assert.match(tostring(s), '^net.dgram.inet.Socket: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), net.AF_INET)
    assert.equal(s:socktype(), net.SOCK_DGRAM)
    assert.equal(s:protocol(), net.IPPROTO_UDP)
    s:close()
end

function testcase.bind()
    local s = assert(inet.new())
    local host = '127.0.0.1'

    -- test that bind to host and available port
    local _, _, ai = assert(s:bind(host, 0))
    assert.equal(ai:addr(), host)
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.greater(ai:port(), 0)

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.new():bind('invalid hostname', 0)
    assert.equal(err.type, errno_eai.EAI_NONAME)
    _, err = inet.new():bind(host, 'invalid servname')
    assert(err.type == errno_eai.EAI_SERVICE or err.type == errno_eai.EAI_NONAME)

    -- test that returns an error that already in use
    _, err = inet.new():bind(host, ai:port())
    assert.equal(err.type, errno.EADDRINUSE)
    s:close()

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.new():bind(host, 0, {
            reuseaddr = 1,
        })
    end), 'reuseaddr must be boolean', false)

    assert.match(assert.throws(function()
        inet.new():bind(host, 0, {
            reuseport = 'foo',
        })
    end), 'reuseport must be boolean', false)
end

function testcase.connect()
    local s = assert(inet.new())
    local host = '127.0.0.1'
    assert(s:bind(host, 0))
    local port = assert(s:getsockname()):port()

    -- test that connect to peer
    local c = assert(inet.new())
    assert(c:connect(host, port, 100))
    c:close()
    s:close()

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.new():connect(host, 'invalid servname')
    assert(err.type == errno_eai.EAI_SERVICE or err.type == errno_eai.EAI_NONAME)
end

