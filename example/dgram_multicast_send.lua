local Inet = require('net.dgram.inet');

local s = assert( Inet.new({
    host = '224.0.0.251',
    port = '5000'
}));
local addr, err = s:getsockname();

if err then
    print( err );
else
    _, err = s:mcastif('lo0');
    if err then
        print( err );
    else
        _, err = s:sendto( 'hello', addr );
        if err then
            print( 'sendto', err );
        end
    end
end

s:close();
