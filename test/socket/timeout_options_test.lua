local testcase = require('testcase')
local assert = require('assert')
local socket = require('net.socket')

function testcase.native_socket_has_no_timeout_methods()
    local sock = assert(socket.new_inet({ socktype = 'stream', protocol = 'tcp' }))
    local recv, send = sock.rcvtimeo, sock.sndtimeo
    sock:close()
    assert.is_nil(recv)
    assert.is_nil(send)
end

function testcase.native_timeout_options_are_unrecognized()
    -- Unknown options are ignored by the native constructor option parser.
    for _, new in ipairs({ socket.new_inet, socket.new_inet6, socket.new_unix }) do
        local sock = assert(new({
            socktype = 'dgram',
            rcvtimeo = 'not a timeout option',
            sndtimeo = {},
        }))
        sock:close()
    end
end
