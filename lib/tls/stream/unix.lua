--
-- Copyright (C) 2021-2022 Masatoshi Fukunaga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
--- @class net.tls.stream.unix.Socket : net.tls.stream.Socket, net.tls.unix.Socket
local Socket = require('metamodule').new.Socket({}, 'net.tls.stream.Socket',
                                                'net.tls.unix.Socket')

--- @class net.tls.stream.unix.Client : net.tls.stream.unix.Socket
local Client = require('metamodule').new
                   .Client({}, 'net.tls.stream.unix.Socket')

--- @class net.tls.stream.unix.Server : net.tls.stream.Server
local Server = {}

--- new_connection
--- @param sock socket
--- @param nonblock boolean
--- @return net.tls.stream.Socket? sock
--- @return any err
function Server:new_connection(sock, nonblock)
    local tls, err = self.tls:accept_socket(sock:fd())

    if err then
        sock:close()
        return nil, err
    end

    return Socket(sock, nonblock, tls)
end

--- close
--- @return boolean ok
--- @return any err
function Server:close()
    self:unwait()

    -- non server-connection (TLS_SERVER_CONN) should not be closed
    -- self:tls_close()

    return self.sock:close()
end

Server = require('metamodule').new.Server(Server, 'net.tls.stream.Server')

return {
    Client = Client,
    Server = Server,
}

