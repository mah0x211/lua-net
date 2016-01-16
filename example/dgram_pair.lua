local Pair = require('net.dgram.pair');

local s = assert( Pair.new() );
local msg = 'hello';
local len, err = s[1]:send( msg );

if err then
    print( 'send', err );
else
    msg, err = s[2]:recv();
    if err then
        print( 'recv', err );
    end
end

s[1]:close();
s[2]:close();
