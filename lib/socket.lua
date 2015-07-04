--[[
  
  Copyright (C) 2014 Masatoshi Teruya
 
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
 
  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.
 
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.
  
  
  socket.lua
  lua-net
  Created by Masatoshi Teruya on 14/05/25.
  
--]]
-- assign to local
local cevIo = require('coevent').io;
local bindInet = require('llsocket').inet.bind;
local connectInet = require('llsocket').inet.connect;
local bindUnix = require('llsocket').unix.bind;
local connectUnix = require('llsocket').unix.connect;
local setNodelay = require('llsocket').opt.nodelay;
local close = require('llsocket').close;
local shutdown = require('llsocket').shutdown;

-- internal functions
local function onRecv( self, watcher, hup )
    -- notify hup event
    if hup then
        self:notify( 'hup', self );
    -- notify recv event
    else
        self:notify( 'recv', self );
    end
end


local function onSend( self, watcher, hup )
    -- notify hup event
    if hup then
        self:notify( 'hup', self );
    -- notify send event
    else
        self:notify( 'send', self );
    end
end


local function eventResume( self, evt )
    local err;
    
    if not self.cycle[evt] then
        err = self.evts[evt]:watch( false, self.EVENT_CALLBACKS[evt], self );
        self.cycle[evt] = not err;
    end
    
    return err;
end


local function eventSuspend( self, evt )
    if self.cycle[evt] then
        self.evts[evt]:unwatch();
        self.cycle[evt] = false;
    end
end


-- class
local Socket = require('halo').class.Socket;

Socket.inherits {
    'net.observer.Observer',
    'net.util.Util'
};

Socket:property {
    public = {
        -- list of notifications
        NOTIFICATIONS = {
            ['close'] = true,
            ['recv'] = true,
            ['send'] = true,
            ['hup'] = true
        },
        -- list of event callback functions
        EVENT_CALLBACKS = {
            ['recv'] = onRecv,
            ['send'] = onSend
        },
        -- coevent loop
        loop = false,
        -- internal use
        evts = {
            -- coevent.input instance
            recv = false,
            -- coevent.output instance
            send = false
        },
        -- evts.* status
        cycle = {
            recv = false,
            send = false
        },
        -- descriptor
        fd = false,
        -- socket info
        sock = {
            -- family,      -- inet or unix
            -- type,        -- lls.opt.SOCK_STREAM or lls.opt.SOCK_DGRAM
            --- if family == inet
            -- host,
            -- port
            --- if family == unix
            -- path
        },
        -- socket options
        opts = {
            edge = false
        },
        -- userdata table
        udata = {}
    }
};


--[[
    MARK: Metatable
--]]
function Socket:__gc()
    lls.close( self.fd );
end


function Socket:__newindex( prop )
    error( ('attempt to access unknown property: %q'):format( prop ), 2 );
end


--[[
    MARK: Interface
--]]
--- shutdown
-- @param   fd  descriptor
function Socket:init( fd )
    self.fd = fd;
    
    return self;
end

--- bind
-- @return  errno
function Socket:bind()
    local sock = self.sock;
    local opts = self.opts;
    local err;
    
    if sock.family == 'inet' then
        self.fd, err = bindInet( sock.host, sock.port, sock.type, 
                                 opts.nonblock, opts.reuseaddr );
    elseif sock.family == 'unix' then
        self.fd, err = bindUnix( sock.path, sock.type, opts.nonblock, 
                                 opts.reuseaddr );
    else
        error( ('unsupported protocol family: %q'):format( self.family ), 2 );
    end
    
    -- set nodelay option
    if not err and opts.nodelay then
        err = setNodelay( self.fd, true );
        if err then
            close( self.fd );
        end
    end
    
    return err;
end


--- connect
-- @return  errno
function Socket:connect()
    local sock = self.sock;
    local opts = self.opts;
    local err;
    
    if sock.family == 'inet' then
        self.fd, err = connectInet( sock.host, sock.port, sock.type, 
                                    opts.nonblock );
    elseif sock.family == 'unix' then
        self.fd, err = connectUnix( sock.path, sock.type, opts.nonblock );
    else
        error( ('unsupported protocol family: %q'):format( self.family ), 2 );
    end
    
    if not err then
        -- set nodelay option
        if opts.nodelay then
            err = setNodelay( self.fd, true );
        end
        
        -- create event
        if not err and self.loop then
            err = self:eventCreate( self.loop, self.opts.edge );
        end
        
        if err then
            close( self.fd );
        end
    end
    
    return err;
end


--- shutdown
-- @param   how [net.shut.RD, net.shut.WR, net.shut.RDWR]
-- @return  errno
function Socket:shutdown( how )
    return shutdown( self.fd, how );
end


--- close
-- @param   opt [net.shut.RD, net.shut.WR, net.shut.RDWR]
-- @return  errno
function Socket:close( opt )
    local err = close( self.fd, opt );
    
    self:eventSuspend();
    self:notify( 'close', self, err );
    
    return err;
end


--[[
    MARK: Event Interface
--]]
--- create events
-- @param   loop    coevent loop object
-- @return  errno
function Socket:eventCreate( loop )
    local err;
    
    -- create duplex event
    self.evts.recv, self.evts.send, err = cevIo( loop, self.fd, self.opts.edge );
    self.loop = loop;
    
    return err;
end


-- resume event
function Socket:eventResume()
    eventResume( self, 'recv' );
    eventResume( self, 'send' );
end

function Socket:eventResumeRecv()
    return eventResume( self, 'recv' );
end

function Socket:eventResumeSend()
    return eventResume( self, 'send' );
end


-- suspend event
function Socket:eventSuspend()
    eventSuspend( self, 'recv' );
    eventSuspend( self, 'send' );
end

function Socket:eventSuspendRecv()
    eventSuspend( self, 'recv' );
end

function Socket:eventSuspendSend()
    eventSuspend( self, 'send' );
end


return Socket.exports;

