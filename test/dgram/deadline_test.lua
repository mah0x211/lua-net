local testcase = require('testcase')
local assert = require('assert')
local inet = require('net.dgram.inet')

local SOCKET

function testcase.after_each()
    if SOCKET then
        SOCKET:close()
        SOCKET = nil
    end
end

function testcase.get_send_deadline_uses_configured_timeout()
    SOCKET = assert(inet.new())
    SOCKET:sndtimeo(5)
    local deadline, sec = SOCKET:get_send_deadline()
    assert.equal(sec, 5)
    assert.is_false(deadline:is_done())
end

function testcase.get_recv_deadline_uses_configured_timeout()
    SOCKET = assert(inet.new())
    SOCKET:rcvtimeo(5)
    local deadline, sec = SOCKET:get_recv_deadline()
    assert.equal(sec, 5)
    assert.is_false(deadline:is_done())
end

function testcase.new_send_deadline_uses_explicit_timeout()
    SOCKET = assert(inet.new())
    SOCKET:sndtimeo(5)
    local deadline, sec = SOCKET:new_send_deadline(10)
    assert.equal(sec, 10)
    assert.greater(deadline:remain(), 5)
    assert.equal(SOCKET:get_sndtimeo(), 5)
end

function testcase.new_recv_deadline_uses_explicit_timeout()
    SOCKET = assert(inet.new())
    SOCKET:rcvtimeo(5)
    local deadline, sec = SOCKET:new_recv_deadline(10)
    assert.equal(sec, 10)
    assert.greater(deadline:remain(), 5)
    assert.equal(SOCKET:get_rcvtimeo(), 5)
end

function testcase.new_send_deadline_uses_configured_timeout_when_omitted()
    SOCKET = assert(inet.new())
    SOCKET:sndtimeo(5)
    local deadline, sec = SOCKET:new_send_deadline()
    assert.equal(sec, 5)
    assert.is_false(deadline:is_done())
end

function testcase.new_recv_deadline_uses_configured_timeout_when_omitted()
    SOCKET = assert(inet.new())
    SOCKET:rcvtimeo(5)
    local deadline, sec = SOCKET:new_recv_deadline()
    assert.equal(sec, 5)
    assert.is_false(deadline:is_done())
end

function testcase.new_send_deadline_preserves_zero_timeout()
    SOCKET = assert(inet.new())
    local deadline, sec = SOCKET:new_send_deadline(0)
    assert.equal(sec, 0)
    assert.is_true(deadline:is_done())
end

function testcase.new_recv_deadline_preserves_zero_timeout()
    SOCKET = assert(inet.new())
    local deadline, sec = SOCKET:new_recv_deadline(0)
    assert.equal(sec, 0)
    assert.is_true(deadline:is_done())
end
