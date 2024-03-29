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
-- assign to local
local accept = require('net.tls.context').accept

--- @class net.tls.stream.inet.Socket : net.tls.stream.Socket
local Socket = require('metamodule').new.Socket({}, 'net.tls.stream.Socket')

--- @class net.tls.stream.inet.Client : net.tls.stream.inet.Socket
local Client = require('metamodule').new
                   .Client({}, 'net.tls.stream.inet.Socket')

--- @class net.tls.stream.inet.Server : net.tls.stream.Server
local Server = {}

--- new_connection
--- @param sock socket
--- @return net.tls.stream.Socket? sock
--- @return any err
function Server:new_connection(sock)
    local tls, err = accept(self.tls, sock:fd())

    if not tls then
        sock:close()
        return nil, err
    end

    return Socket(sock, tls)
end

Server = require('metamodule').new.Server(Server, 'net.tls.stream.Server')

return {
    Client = Client,
    Server = Server,
}

