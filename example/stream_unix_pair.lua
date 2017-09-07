local Unix = require('net.stream.unix');

local s = assert( Unix.pair() );
local msg = 'hello';
local len, err = s[1]:send( msg );

if err then
    print( 'send', err );
else
    msg, err = s[2]:recv();
    if err then
        print( 'recv', err );
    elseif not msg then
        print( 'closed by peer' );
    end
end

s[1]:close();
s[2]:close();
