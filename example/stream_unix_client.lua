local Client = require('net.stream.unix').client;

local c = assert( Client.new({
    path = './example.sock'
}));
local msg = 'hello';
local len, err = c:send( msg );

if err then
    print( 'send', err );
elseif not len then
    print( 'closed by server' );
else
    msg, err = c:recv();
    if err then
        print( 'recv', err );
    end
end

c:close();
