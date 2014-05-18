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
  
  
  tcp/request.lua
  lua-net
  Created by Masatoshi Teruya on 14/05/15.
  
--]]

local lls = require('llsocket');
local coevent = require('coevent');
-- list of notifications
local NOTIFICATION = {
    ['close'] = true,
    ['read'] = true,
    ['write'] = true,
    ['hup'] = true
};

-- metamethods
local function GC()
    lls.close( self.fd );
end


-- metatable
local METHOD = {};
local MT = {
    __gc = GC,
    __index = METHOD
};


-- method implementaion
function METHOD:shutdown()
    return lls.shutdown( self.fd, lls.opt.SHUT_RDWR );
end

function METHOD:shutdownRD()
    self:unwatchRead();
    return lls.shutdown( self.fd, lls.opt.SHUT_RD );
end

function METHOD:shutdownWR()
    self:unwatchWrite();
    return lls.shutdown( self.fd, lls.opt.SHUT_WR );
end


function METHOD:close()
    local err;
    
    self:unwatch();
    err = lls.close( self.fd );
    self:notify( 'close', self, err );
    
    return err;
end


-- event methods
local function onRead( self, watcher, hup )
    -- notify hup event
    if hup then
        self:notify( 'hup', self );
        self:unwatch();
    -- notify read event
    else
        self:notify( 'read', self );
    end
end

function METHOD:watchRead( oneshot, edgeTrigger )
    return self.read_ev:watch( oneshot, edgeTrigger, onRead, self );
end

function METHOD:unwatchRead()
    if self.read_ev then
        return self.read_ev:unwatch();
    end
end


local function onWrite( self, watcher, hup )
    -- notify hup event
    if hup then
        self:notify( 'write hup', self );
        self:unwatch();
    -- notify write event
    else
        self:notify( 'write', self );
    end
end

function METHOD:watchWrite( oneshot, edgeTrigger )
    return self.write_ev:watch( oneshot, edgeTrigger, onWrite, self );
end

function METHOD:unwatchWrite()
    if self.write_ev then
        return self.write_ev:unwatch();
    end
end


function METHOD:unwatch()
    self:unwatchRead();
    self:unwatchWrite();
end


function METHOD:observe( name, callback, ctx )
    if type( name ) ~= 'string' then
        error( 'name must be type of string' );
    elseif not NOTIFICATION[name] then
        error( 'unknown notification name: ' .. name );
    elseif type( callback ) ~= 'function' then
        error( 'callback must be type of function' );
    else
        self.obs[name] = {
            fn = callback,
            ctx = ctx
        };
    end
    
    return self;
end


function METHOD:unobserve( name )
    if type( name ) ~= 'string' then
        error( 'name must be type of string' );
    elseif not NOTIFICATION[name] then
        error( 'unknown notification name: ' .. name );
    else
        self.obs[name] = nil;
    end
    
    return self;
end


function METHOD:notify( name, ... )
    local obs = self.obs[name];
    
    if obs then
        obs.fn( obs.ctx, ... );
    end
end


-- interfaces
local function create( fd )
    return setmetatable({
        fd = fd,
        obs = {}
    }, MT );
end


local function createWithEventLoop( fd, loop )
    local req = create( fd );
    local err;
    
    -- create read event
    req.read_ev, err = coevent.reader( loop, fd );
    -- create write event
    if not err then
        req.write_ev, err = coevent.writer( loop, fd );
    end
    
    -- dispose
    if err and req then
        req:close();
    end
    
    return req, err;
end

return {
    create = create,
    createWithEventLoop = createWithEventLoop
}

