local inspect = require('util').inspect;
local process = require('process');
local signal = require('signal');
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


local function connect( loop, host, opts )
    -- create event-loop
    local cli, err;
    
    print( 'connect', host );
    -- create tcp client
    cli, err = tcp.client.new( 'unix', opts, host );
    die( err );
    -- create buffer with client fd
    cli.udata.buf, err = buffer( 256, cli.fd );
    die( err );
    -- set message
    die( cli.udata.buf:set( 'hello world' ) );
    -- create event
    die( cli:eventCreate( loop ) );
    -- observe client events
    cli:observe( 'close', onClose )
       :observe( 'hup', onHup )
       :observe( 'recv', onRecv )
       :observe( 'send', onSend );
    -- resume send event
    die( cli:eventResumeSend() );
end


local function onException( ctx, watcher, info )
    print( 'got exception', watcher, inspect( info ) );
    print( inspect( ctx ) );
end


local host = './example.sock';
local loop, err;

-- create loop
loop, err =coevent.loop( nil, onException );
die( err );
print( 'start client' );
connect( loop, host, { nonblock = true } );
die( loop:run( 1000 ) );
print( 'end client' );
print( 'client terminate' );

