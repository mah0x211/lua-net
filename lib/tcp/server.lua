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
  
  
  tcp/server.lua
  lua-net
  Created by Masatoshi Teruya on 14/05/15.
  
--]]

local lls = require('llsocket');
local request = require('net.tcp.request');

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

-- method implementation
function METHOD:accept( ... )
    return request.accept( self.fd, self.nonblock, ... );
end


function METHOD:shutdown()
    return lls.shutdown( self.fd, lls.opt.SHUT_RDWR );
end


function METHOD:close()
    return lls.close( self.fd );
end


-- interface
local function listen( host, port, nonblock, backlog )
    local ok = false;
    local fd, err;
    
    -- check arguments
    if type( nonblock ) ~= 'boolean' then
        error( 'nonblock must be type of boolean' );
    elseif type( backlog ) ~= 'number' then
        error( 'backlog must be type of number' );
    end
    
    -- bind with passed arguments
    fd, err = lls.inet.bind( host, port, lls.opt.SOCK_STREAM, nonblock );
    if fd then
        ok, err = lls.listen( fd, backlog );
        
        if ok then
            return setmetatable({
                fd = fd,
                host = host,
                port = port,
                nonblock = nonblock,
                backlog = backlog
            }, MT );
        end
        
        -- got error
        lls.close( fd );
    end
    
    return nil, err;
end


return {
    listen = listen;
}

