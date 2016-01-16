local Unix = require('net.dgram.unix');

local c = assert( Unix.new({
    path = './example2.sock'
}));
local err = c:bind();

if err then
    print( 'bind', err );
else
    err = c:connect({
        path = './example.sock'
    });

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
end

c:close();
