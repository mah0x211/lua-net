local inspect = require('util').inspect;
local process = require('process');
local coevent = require('coevent');
local buffer = require('buffer');
local tcp = require('net.tcp');

local function onSend( ctx, cli )
    print( 'send', cli.udata.buf );
    local len, total, err, again = cli.udata.buf:flush();
    
    if not again then
        if len == total then
            cli:eventSuspendSend();
            cli:eventResumeRecv();
        elseif len < 1 then
            if err then
                print( process.strerror( err ) );
            end
            cli:close();
        end
    end
end


local function onRecv( ctx, cli )
    local len, err, again;
    
    repeat
        len, err, again = cli.udata.buf:read();
        if again then
            coroutine.yield();
        end
    until again ~= true;
    
    if len > 0 then
        print( 'recv', cli.udata.buf );
        cli:eventSuspendRecv();
    elseif len < 1 then
        if err then
            print( 'recv', process.strerror( err ) );
        end
        cli:close();
    end
end


local function onHup( ctx, cli )
    cli:close();
end


local function onClose( ctx, cli )
    cli.udata.buf:free();
end


local function die( err )
    if err then
        error( process.strerror(), 2 );
    end
end


local function connect( loop, host, port, opts )
    -- create event-loop
    local cli, err;
    
    print( 'connect', host, port );
    -- create tcp client
    cli, err = tcp.client.new( 'inet', opts, host, port );
    die( err );
    -- create buffer with client fd
    cli.udata.buf, err = buffer( 256, cli.fd );
    die( err );
    -- set message
    die( cli.udata.buf:set( 'hello world' ) );
    -- create event
    die( cli:eventCreate( loop ) );
    -- observe client events
    cli:on( 'close', onClose )
       :on( 'hup', onHup )
       :on( 'recv', onRecv )
       :on( 'send', onSend );
    -- resume send event
    die( cli:eventResumeSend() );
end


local function onException( ctx, watcher, info )
    print( 'got exception', watcher, inspect( info ) );
    print( inspect( ctx ) );
end


local host, port = '127.0.0.1', '5000';
local loop, err;

-- create loop
loop, err =coevent.loop( nil, onException );
die( err );
print( 'start client' );
connect( loop, host, port, { nonblock = true } );
die( loop:run( 1000 ) );
print( 'end client' );
print( 'client terminate' );

