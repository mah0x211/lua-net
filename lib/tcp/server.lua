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
  
  
  interface/server.lua
  lua-net
  Created by Masatoshi Teruya on 14/05/15.
  
--]]
local lls = require('llsocket');
local coevent = require('coevent');
local request = require('net.tcp.request');

local function onConnect( self )
    local req, err = self:accept( true );
    
    if not err then
        err = req:eventCreate( self.loop );
        -- notify connect event
        if not err then
            self:notify( 'connect', req );
        end
    end
    
    if err then
        if req then
            req:close();
        end
        -- notify error event
        self:notify( 'error', 'connect', err );
    end
end


local Server = require('halo').class.Server;

Server.inherits {
    'net.socket.Socket',
    -- remove unused methods
    except = {
        instance = {
            'connect',
            'eventResumeSend'
        }
    }
};

Server:property {
    public = {
        -- list of notifications
        NOTIFICATIONS = {
            ['error'] = true,
            ['connect'] = true
        },
        -- override callbacks
        EVENT_CALLBACKS = {
            ['recv'] = onConnect
        },
        opts = {
            nonblock = true, 
            reuseaddr = true, 
            backlog = 511
        }
    }
};


--[[
    MARK: Interface
--]]
function Server:init( ... )
    local err;
    
    -- check options
    self:checkInit( lls.opt.SOCK_STREAM, ... );
    -- bind
    err = self:bind();
    if not err then
        err = lls.listen( self.fd, self.opts.backlog );
        
        -- got error
        if err then
            lls.close( self.fd );
        end
    end
    
    return self, err;
end

--- accept
-- @param   inherits    boolean (default: true)
-- @return  request object
function Server:accept( inherits )
    local fd, err;
    
    if inherits == false then
        fd, err = lls.accept( self.fd );
    else
        fd, err = lls.acceptInherits( self.fd );
    end
    
    if err then
        return nil, err;
    end
    
    -- create request object
    return request.new( fd );
end


--[[
    MARK: Override Event Interface
--]]
function Server:eventCreate( loop )
    local err;
    
    -- create input event
    self.evts.recv, err = coevent.input( loop, self.fd, self.opts.edge );
    self.loop = loop;
    
    return err;
end


function Server:eventResume()
    return self:eventResumeRecv();
end


return Server.exports;

