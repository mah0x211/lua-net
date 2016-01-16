local Unix = require('net.dgram.unix');

local s = assert( Unix.new({
    path = './example.sock',
}));
local err = s:bind();

if err then
    print( 'bind', err );
else
    local msg, addr, len;

    msg, addr, err = s:recvfrom();
    if err then
        print( 'recvfrom', err );
    else
        len, err = s:sendto( msg, addr );
        if err then
            print( 'sendto', err );
        end
    end
end

s:close();
