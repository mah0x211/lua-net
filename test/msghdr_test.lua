require('luacov')
local addrinfo = require('net.addrinfo')
local msghdr = require('net.msghdr')
local testcase = require('testcase')

function testcase.new()
    -- test that returns instance of net.msghdr.MsgHdr
    local mh = msghdr.new()
    assert.match(tostring(mh), '^net.msghdr.MsgHdr: ', false)
    -- confirm that all properties are nil
    assert.is_nil(mh:name())
    assert.equal(mh:bytes(), 0)
    assert.equal(mh:consume(1), 0)
    assert.equal(mh:concat(), '')
    assert.is_nil(mh:get(1))
    assert.is_nil(mh:del(1))
end

function testcase.name()
    local mh = msghdr.new()
    local ai = addrinfo.new_inet_stream('127.0.0.1', 8080)

    -- test that replace addrinfo
    assert.is_nil(mh:name(ai))
    assert.equal(mh:name(), ai)
    assert.equal(mh:name(nil), ai)
    assert.is_nil(mh:name())

    -- test that throw an error with invalid arguments
    local err = assert.throws(function()
        mh:name({})
    end)
    assert.match(err, '#1 .+ [(]llsocket.addrinfo expected, got table', false)
end

function testcase.control()
    local mh = msghdr.new()

    -- test that create new cmsghdrs
    local cmhs = assert(mh:control())
    assert.match(tostring(cmhs), '^llsocket.cmsghdrs: ', false)
    assert.equal(mh:control(), cmhs)
end

function testcase.add()
    local mh = msghdr.new()

    -- test that add string
    local idx = assert(mh:add('foo/bar'))
    assert.equal(idx, 1)
    assert.equal(mh:bytes(), 7)
end

function testcase.addn()
    local mh = msghdr.new()

    -- test that add n byte of space
    local idx = assert(mh:addn(125))
    assert.equal(idx, 1)
    assert.equal(mh:bytes(), 125)
    local s = assert(mh:get(idx))
    assert.equal(#s, 125)
    assert.equal(s, string.rep(' ', #s))
end

function testcase.get()
    local mh = msghdr.new()
    local i1 = assert(mh:add('foo/bar'))
    local i2 = assert(mh:addn(125))
    local i3 = assert(mh:add('qux/quux'))

    -- test that get a string by index
    local s = assert(mh:get(i1))
    assert.equal(s, 'foo/bar')
    s = assert(mh:get(i2))
    assert.equal(#s, 125)
    assert.equal(s, string.rep(' ', #s))
    s = assert(mh:get(i3))
    assert.equal(s, 'qux/quux')
end

function testcase.del()
    local mh = msghdr.new()
    local i1 = assert(mh:add('foo/bar'))
    local i2 = assert(mh:addn(125))
    local i3 = assert(mh:add('qux/quux'))

    -- test that delete a string at index
    local s = assert(mh:del(i1))
    assert.equal(s, 'foo/bar')
    assert.equal(mh:bytes(), 125 + 8)

    s = assert(mh:get(i2 - 1))
    assert.equal(#s, 125)
    assert.equal(s, string.rep(' ', #s))
    s = assert(mh:get(i3 - 1))
    assert.equal(s, 'qux/quux')
    assert.is_nil(mh:get(i3))
end

function testcase.concat()
    local mh = msghdr.new()
    assert(mh:add('foo/bar'))
    assert(mh:addn(125))
    assert(mh:add('qux/quux'))

    -- test that returns a concatenated string of all the held strings
    assert.equal(mh:concat(), 'foo/bar' .. string.rep(' ', 125) .. 'qux/quux')
end

function testcase.consume()
    local mh = msghdr.new()
    assert(mh:add('foo/bar'))
    assert(mh:addn(125))
    assert(mh:add('qux/quux'))

    -- test that remove specified number of bytes string from the first index
    -- and returns the remaining number of bytes
    assert.equal(mh:consume(7 + 25), 100 + 8)

    -- test that remove held strings and returns the remaining number of bytes
    assert.equal(mh:consume(200), 0)
end

