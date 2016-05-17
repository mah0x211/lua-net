local Client = require('net.stream.inet').client;

local c = assert( Client.new({
    host = '127.0.0.1';
    port = '5000',
}));
local msg = 'hello';
local len;

len, err = c:send( msg );
if err then
    print( 'send', err );
elseif not len then
    print( 'closed by peer' );
else
    msg, err = c:recv();
    if err then
        print( 'recv', err );
    elseif not msg then
        print( 'closed by server' );
    end
end

c:close();

