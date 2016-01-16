local Inet = require('net.dgram.inet');

local s = assert( Inet.new({
    host = '127.0.0.1';
    port = '5000',
    reuseaddr = true
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
