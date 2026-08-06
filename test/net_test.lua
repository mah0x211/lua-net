require('luacov')
local testcase = require('testcase')
local net = require('net')

function testcase.does_not_export_llsocket_constants()
    assert.is_nil(net.AF_INET)
    assert.is_nil(net.SOCK_STREAM)
    assert.is_nil(net.IPPROTO_TCP)
    assert.is_nil(net.MSG_PEEK)
    assert.is_nil(net.SHUT_RDWR)
end
