local Server = require('net.stream.inet').server;

local s = assert( Server.new({
    host = '127.0.0.1';
    port = '5000',
    reuseaddr = true
}));
local err = s:listen();

if err then
    print( 'listen', err );
else
    local c, msg, len;

    c, err = s:accept();
    if err then
        print( 'accept', err );
    else
        msg, err = c:recv();
        if err then
            print( 'recv', err );
        elseif not msg then
            print( 'closed by peer' );
        else
            len, err = c:send( msg );
            if err then
                print( 'send', err );
            end
            c:close()
        end
    end
end

s:close();
