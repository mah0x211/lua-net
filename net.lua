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


  net.lua
  lua-net
  Created by Masatoshi Teruya on 14/05/16.

--]]

--- assign to local
local waitrecv = require('net.poll').waitrecv;
local waitsend = require('net.poll').waitsend;
local recvsync = require('net.poll').recvsync;
local sendsync = require('net.poll').sendsync;
local msghdr = require('llsocket.msghdr');
local iovec = require('llsocket.iovec');
local cmsghdrs = require('llsocket.cmsghdrs');
local floor = math.floor;
--- constants
local INFINITE = math.huge;
local SHUT_RD = require('llsocket').SHUT_RD;
local SHUT_WR = require('llsocket').SHUT_WR;
local SHUT_RDWR = require('llsocket').SHUT_RDWR;


--- isuint
-- @param v
-- @return ok
local function isuint( v )
    return type( v ) == 'number' and v < INFINITE and v >= 0 and floor( v ) == v;
end



-- MARK: class MsgHdr
local MsgHdr = require('halo').class.MsgHdr;


--- init
-- @param nvec
-- @return self
function MsgHdr:init( nvec )
    local err;

    self.msg, err = msghdr.new();
    if err then
        return nil, err;
    -- create iovec
    elseif nvec then
        self.iov, err = iovec.new( nvec );
        if not self.iov then
            return nil, err;
        end

        self.msg:iov( self.iov );
    end

    return self;
end


--- name
-- @param ai
-- @return ai
function MsgHdr:name( ai )
    return self.msg:name( ai );
end


--- control
-- @return cmsgs
function MsgHdr:control()
    local cmsgs = self.msg:control();

    if cmsgs then
        return cmsgs;
    else
        local err;

        cmsgs, err = cmsghdrs.new();
        if err then
            return nil, err;
        end

        return self.msg:control( cmsgs );
    end
end


--- bytes
-- @return bytes
function MsgHdr:bytes()
    local iov = self.iov;

    if iov then
        return iov:bytes();
    end

    return 0;
end


--- consume
-- @param bytes
-- @return bytes
function MsgHdr:consume( bytes )
    local iov = self.iov;

    if iov then
        return iov:consume( bytes );
    end

    return 0;
end


--- concat
-- @return str
function MsgHdr:concat()
    local iov = self.iov;

    if iov then
        return iov:concat();
    end

    return '';
end


--- add
-- @param str
-- @return used
-- @return err
function MsgHdr:add( str )
    local iov = self.iov;
    local err;

    -- create new iovec
    if not iov then
        iov, err = iovec.new();
        if not iov then
            return nil, err;
        end

        self.iov = self.msg:iov( iov );
    end

    return iov:add( str );
end


--- addn
-- @param bytes
-- @return used
-- @return err
function MsgHdr:addn( bytes )
    local iov = self.iov;
    local err;

    -- create new iovec
    if not iov then
        iov, err = iovec.new();
        if not iov then
            return nil, err;
        end

        self.iov = self.msg:iov( iov );
    end

    return iov:addn( bytes );
end


--- get
-- @param idx
-- @return str
function MsgHdr:get( idx )
    local iov = self.iov;

    if iov then
        return iov:get( idx );
    end

    return nil;
end


--- del
-- @param idx
-- @return str
-- @return midx
function MsgHdr:del( idx )
    local iov = self.iov;

    if iov then
        return iov:del( idx );
    end

    return nil;
end



MsgHdr = MsgHdr.exports;



-- MARK: class Socket
local Socket = require('halo').class.Socket;


--[[
function Socket:__newindex( prop )
    error( ('attempt to access unknown property: %q'):format( prop ), 2 );
end
--]]


--- init
-- @param sock
-- @param nonblock
-- @param tls
-- @return self
function Socket:init( sock, nonblock, tls )
    self.sock = sock;
    self.nonblock = nonblock == true;
    self.tls = tls;
    return self;
end


--- deadlines
-- @param rcvdeadl
-- @param snddeadl
-- @return rcvdeadl
-- @return snddeadl
function Socket:deadlines( rcvdeadl, snddeadl )
    -- set socket timeout
    if not self.nonblock then
        rcvdeadl = assert( self:rcvtimeo( rcvdeadl ) );
        snddeadl = assert( self:sndtimeo( snddeadl ) );

        return rcvdeadl, snddeadl;
    end

    -- set to rcvdeadl and snddeadl properties if non-blocking mode
    if rcvdeadl ~= nil then
        assert( isuint( rcvdeadl ), 'rcvdeadl must be unsigned integer' );
        -- disable recv deadline
        if rcvdeadl == 0 then
            self.rcvdeadl = nil;
        else
            self.rcvdeadl = rcvdeadl;
        end
    end

    if snddeadl ~= nil then
        assert( isuint( snddeadl ), 'snddeadl must be unsigned integer' );
        -- disable send deadline
        if snddeadl == 0 then
            self.snddeadl = nil;
        else
            self.snddeadl = snddeadl;
        end
    end

    return self.rcvdeadl, self.snddeadl;
end


--- onwaithook
-- @param name
-- @param fn
-- @param ctx
-- @return fn
-- @return err
local function onwaithook( self, name, fn, ctx )
    local oldfn = self[name];

    if fn == nil then
        self[name] = nil;
        self[name .. 'ctx'] = nil;
    elseif type( fn ) == 'function' then
        self[name] = fn;
        self[name .. 'ctx'] = ctx;
    else
        return nil, 'fn must be nil or function';
    end

    return oldfn;
end


--- onwaitrecv
-- @param fn
-- @param ctx
-- @return fn
-- @return err
function Socket:onwaitrecv( fn, ctx )
    return onwaithook( self, 'rcvhook', fn, ctx );
end


--- onwaitsend
-- @param fn
-- @param ctx
-- @return fn
-- @return err
function Socket:onwaitsend( fn, ctx )
    return onwaithook( self, 'sndhook', fn, ctx );
end


--- fd
-- @return fd
function Socket:fd()
    return self.sock:fd();
end


--- family
-- @return af
function Socket:family()
    return self.sock:family();
end


--- sockname
-- @return addr
-- @return err
function Socket:getsockname()
    return self.sock:getsockname();
end


--- peername
-- @return addr
-- @return err
function Socket:getpeername()
    return self.sock:getpeername();
end


--- closer
-- @return err
function Socket:closer()
    return self.sock:shutdown( SHUT_RD );
end


--- closew
-- @return err
function Socket:closew()
    return self.sock:shutdown( SHUT_WR );
end


--- close
-- @param shutrd
-- @param shutwr
-- @return err
function Socket:close( shutrd, shutwr )
    local sock = self.sock;
    local tls = self.tls;

    self.sock = nil;
    self.tls = nil;

    if tls then
        return tls:close();
    elseif shutrd == true and shutwr == true then
        return sock:close( SHUT_RDWR );
    elseif shutrd == true then
        return sock:close( SHUT_RD );
    elseif shutwr == true then
        return sock:close( SHUT_WR );
    end

    return sock:close();
end


--- atmark
-- @return bool
-- @return err
function Socket:atmark()
    return self.sock:atmark();
end


--- cloexec
-- @param bool
-- @return bool
-- @return err
function Socket:cloexec( bool )
    return self.sock:cloexec( bool );
end


--- isnonblock
-- @return bool
function Socket:isnonblock()
    return self.nonblock;
end


--- socktype
-- @return socktype
-- @return err
function Socket:socktype()
    return self.sock:socktype();
end


--- protocol
-- @return proto
function Socket:protocol()
    return self.sock:protocol();
end


--- error
-- @return errno
-- @return err
function Socket:error()
    return self.sock:error();
end


--- reuseport
-- @param bool
-- @return bool
-- @return err
function Socket:reuseport( bool )
    return self.sock:reuseport( bool );
end


--- reuseaddr
-- @param bool
-- @return bool
-- @return err
function Socket:reuseaddr( bool )
    return self.sock:reuseaddr( bool );
end


--- debug
-- @param bool
-- @return bool
-- @return err
function Socket:debug( bool )
    return self.sock:debug( bool );
end


--- dontroute
-- @param bool
-- @return bool
-- @return err
function Socket:dontroute( bool )
    return self.sock:dontroute( bool );
end


--- timestamp
-- @param bool
-- @return bool
-- @return err
function Socket:timestamp( bool )
    return self.sock:timestamp( bool );
end


--- rcvbuf
-- @param bytes
-- @return bytes
-- @return err
function Socket:rcvbuf( bytes )
    return self.sock:rcvbuf( bytes );
end


--- rcvlowat
-- @param bytes
-- @return bytes
-- @return err
function Socket:rcvlowat( bytes )
    return self.sock:rcvlowat( bytes );
end


--- sndbuf
-- @param bytes
-- @return bytes
-- @return err
function Socket:sndbuf( bytes )
    return self.sock:sndbuf( bytes );
end


--- sndlowat
-- @param bytes
-- @return bytes
-- @return err
function Socket:sndlowat( bytes )
    return self.sock:sndlowat( bytes );
end


--- rcvtimeo
-- @param sec
-- @return sec
-- @return err
function Socket:rcvtimeo( sec )
    return self.sock:rcvtimeo( sec );
end


--- sndtimeo
-- @param sec
-- @return sec
-- @return err
function Socket:sndtimeo( sec )
    return self.sock:sndtimeo( sec );
end


--- linger
-- @param sec
-- @return sec
-- @return err
function Socket:linger( sec )
    return self.sock:linger( sec );
end


--- recv
-- @param bufsize
-- @return str
-- @return err
-- @return timeout
function Socket:recv( bufsize )
    local sock, fn;

    if self.tls then
        sock, fn = self.tls, self.tls.read;
    else
        sock, fn = self.sock, self.sock.recv;
    end

    while true do
        local str, err, again = fn( sock, bufsize );

        if not again or not self.nonblock then
            return str, err, again;
        -- wait until readable
        else
            local ok, perr, timeout = waitrecv( self:fd(), self.rcvdeadl,
                                                self.rcvhook, self.rcvhookctx );

            if not ok then
                return nil, perr, timeout;
            end
        end
    end
end


--- recvsync
-- @param bufsize
-- @return str
-- @return err
-- @return timeout
function Socket:recvsync( ... )
    return recvsync( self, self.recv, ... );
end


--- recvmsg
-- @param msg
-- @return len
-- @return err
-- @return timeout
function Socket:recvmsg( msg )
    if self.tls then
        -- currently, does not support recvmsg on tls connection
        -- EOPNOTSUPP: Operation not supported on socket
        return nil, 'Operation not supported on socket';
    end

    while true do
        local len, err, again = self.sock:recvmsg( msg.msg );

        if not again or not self.nonblock then
            return len, err, again;
        -- wait until readable
        else
            local ok, perr, timeout = waitrecv( self:fd(), self.rcvdeadl,
                                                self.rcvhook, self.rcvhookctx );

            if not ok then
                return nil, perr, timeout;
            end
        end
    end
end


--- recvmsgsync
-- @param msg
-- @return str
-- @return err
-- @return timeout
function Socket:recvmsgsync( ... )
    return recvsync( self, self.recvmsg, ... );
end


--- send
-- @param str
-- @return len
-- @return err
-- @return timeout
function Socket:send( str )
    local sent = 0;
    local sock, fn;

    if self.tls then
        sock, fn = self.tls, self.tls.write;
    else
        sock, fn = self.sock, self.sock.send;
    end

    while true do
        local len, err, again = fn( sock, str );

        if not len then
            return nil, err;
        end

        -- update a bytes sent
        sent = sent + len;

        if not again or not self.nonblock then
            return sent, err, again;
        -- wait until writable
        else
            local ok, perr, timeout = waitsend( self:fd(), self.snddeadl,
                                                self.sndhook, self.sndhookctx );

            if not ok then
                return sent, perr, timeout;
            end

            str = str:sub( len + 1 );
        end
    end
end


--- sendsync
-- @param str
-- @return len
-- @return err
-- @return timeout
function Socket:sendsync( ... )
    return sendsync( self, self.send, ... );
end


--- sendmsg
-- @param msg
-- @return len
-- @return err
-- @return timeout
function Socket:sendmsg( msg )
    if self.tls then
        -- currently, does not support sendmsg on tls connection
        -- EOPNOTSUPP: Operation not supported on socket
        return nil, 'Operation not supported on socket';
    else
        local iov = msg.iov;
        local sent = 0;

        while true do
            local len, err, again = self.sock:sendmsg( msg.msg );

            if not len then
                return nil, err;
            -- update a bytes sent
            elseif len > 0 then
                sent = sent + len;
                iov:consume( len );
            end

            if not again or not self.nonblock then
                return sent, err, again;
            -- wait until writable
            else
                local ok, perr, timeout = waitsend( self:fd(), self.snddeadl,
                                                    self.sndhook,
                                                    self.sndhookctx );

                if not ok then
                    return sent, perr, timeout;
                end
            end
        end
    end
end


--- sendmsgsync
-- @param str
-- @return len
-- @return err
-- @return timeout
function Socket:sendmsgsync( ... )
    return sendsync( self, self.sendmsg, ... );
end


Socket = Socket.exports;


--- net module table
local Module = {
    close = require('llsocket.socket').close,
    cmsghdr = require('llsocket.cmsghdr'),
    msghdr = MsgHdr,
    shutdown = require('llsocket.socket').shutdown,
};

-- exports llsocket constants
do
    local llsocket = require('llsocket');

    for k, v in pairs( llsocket ) do
        if k:find( '^%u+' ) and type( v ) == 'number' then
            Module[k] = v;
        end
    end
end


return Module;


