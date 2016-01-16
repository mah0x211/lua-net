local Inet = require('net.dgram.inet');

local c = assert( Inet.new({
    host = '127.0.0.1';
    port = '5000',
}));
local err = c:connect();

if err then
    print( 'connect', err );
else
    local msg = 'hello';
    local len;

    len, err = c:send( msg );
    if err then
        print( 'send', err );
    else
        msg, err = c:recv();
        if err then
            print( 'recv', err );
        end
    end
end

c:close();
