local Inet = require('net.dgram.inet');

local s = assert( Inet.new({
    port = '5000',
    passive = true
}));
local err = s:bind();

if err then
    print( 'bind', err );
else
    err = s:mcastjoin( '224.0.0.251', 'lo0' );
    if err then
        print( 'mcastjoin', err );
    else
        local msg;

        msg, err = s:recv();
        if err then
            print( 'recvfrom', err );
        end

    end
end

s:close();
