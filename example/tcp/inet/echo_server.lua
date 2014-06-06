local process = require('process');
local coevent = require('coevent');
local buffer = require('buffer');
local tcp = require('net.tcp');
-- default buffer size
local BUFSIZE = 256;


local function onSend( ctx, req )
    local len, total, err = req.udata.buf:flush();
    
    if len < 1 then
        if err then
            print( process.strerror( err ) );
        end
        req:close();
    end
end


local function onRecv( ctx, req, ... )
    local len, err = req.udata.buf:read();
    
    if len < 1 then
        if err then
            print( 'recv', process.strerror( err ) );
        end
        req:close();
    else
        onSend( nil, req );
    end
end


local function onHUP( ctx, req, ... )
    req:close();
end


local function onClose( ctx, req, ... )
    req.udata.buf:free();
end


local function onConnect( server, req )
    local udata = req.udata;
    local err;
    
    -- create buffers
    udata.buf, err = buffer( BUFSIZE, req.fd );
    if not err then
        req:observe( 'close', onClose )
           :observe( 'hup', onHUP )
           :observe( 'recv', onRecv )
           :observe( 'send', onSend );
        
        err = req:eventResumeRecv();
    end
    
    if err then
        req:close();
    end
end

local function onException( sock, watcher, info )
    print( 'got exception', watcher, inspect( info ) );
    print( inspect( sock ) );
end


local function die( err )
    if err then
        error( process.strerror(), 2 );
    end
end


local host, port = '127.0.0.1', '5000';
local loop, server, err;

-- create loop
loop, err = coevent.loop( nil, onException );
die( err );

server, err = tcp.server.new( 'inet', nil, host, port );
die( err );

server:observe( 'connect', onConnect, server );
die( server:eventCreate( loop ) );
die( server:eventResume() );

print( 'start server: ', host, port );
die( loop:run( 1000 ) );
print( 'end server' );
print( 'server terminate' );

