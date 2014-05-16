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
local buffer = require('buffer');
local DEFAULT_BUFSIZE = 2048;

-- metamethods
local function GC()
    lls.close( self.fd );
    self.buf:free();
end


-- metatable
local METHOD = {};
local MT = {
    __gc = GC,
    __index = METHOD
};


-- method implementaion
function METHOD:read()
    return self.buf:read( self.fd );
end


function METHOD:write( buf, ... )
    return buf:write( self.fd, ... );
end


function METHOD:shutdown()
    return lls.shutdown( self.fd, lls.opt.SHUT_RDWR );
end


function METHOD:close()
    self.buf:free();
    return lls.close( self.fd );
end


-- interfaces
local function accept( fd, nonblock, bufsize )
    local fd, err = lls.accept( fd, nonblock );
    
    if not err then
        local buf;
        -- create buffer
        buf, err = buffer( bufsize or DEFAULT_BUFSIZE );
        if not err then
            -- return instance
            return setmetatable({
                fd = fd,
                buf = buf
            }, MT );
        end
    end
    
    return nil, err;
end

return {
    accept = accept;
}

