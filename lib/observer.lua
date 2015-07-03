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
  
  
  observer.lua
  lua-net
  Created by Masatoshi Teruya on 14/05/23.
  
--]]

--[[
    MARK: Metatable
--]]
local Observer = require('halo').class.Observer;

Observer:property {
    public = {
        -- set property
        obs = {},
        -- list of notifications
        NOTIFICATIONS = {}
    }
};

--- observe notification
-- @param   name        [error, close, connect]
-- @param   callback    function
-- @param   ctx         anytype
-- @return  self
function Observer:observe( name, callback, ctx )
    if not self.NOTIFICATIONS[name] then
        error( 'unknown notification name: ' .. name );
    elseif type( callback ) ~= 'function' then
        error( 'callback must be type of function' );
    end
    
    self.obs[name] = {
        fn = callback,
        ctx = ctx
    };
    
    return self;
end

--- unobserve notification
-- @param   name
-- @return  self
function Observer:unobserve( name )
    if not self.NOTIFICATIONS[name] then
        error( 'unknown notification name: ' .. name );
    end
    
    self.obs[name] = nil;
    
    return self;
end


function Observer:notify( name, ... )
    if self.obs[name] then
        self.obs[name].fn( self.obs[name].ctx, ... );
    end
end


return Observer.exports;
