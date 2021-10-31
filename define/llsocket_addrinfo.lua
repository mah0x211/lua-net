--- @class llsocket.addrinfo
local _llsocket_addrinfo = {}

--- create a new addrinfo instance of AF_UNIX
--- @param pathname string
--- @param socktype? integer
--- @param protocol? integer
--- @param flag? integer
--- @vararg integer flags
--- @return llsocket.addrinfo? addrinfo
--- @return string? err
function _llsocket_addrinfo.unix(pathname, socktype, protocol, flag, ...)
end

--- create a new addrinfo instance of AF_INET
--- @param addr? string
--- @param port? integer
--- @param socktype? integer
--- @param protocol? integer
--- @param flag? integer
--- @vararg integer flags
--- @return llsocket.addrinfo? addrinfo
--- @return string? err
function _llsocket_addrinfo.inet(addr, port, socktype, protocol, flag, ...)
end

--- create a new addrinfo instance of AF_INET6
--- @param addr? string
--- @param port? integer
--- @param socktype? integer
--- @param protocol? integer
--- @param flag? integer
--- @vararg integer flags
--- @return llsocket.addrinfo? addrinfo
--- @return string? err
function _llsocket_addrinfo.inet6(addr, port, socktype, protocol, flag, ...)
end

--- get a list of address info of tcp stream socket
--- @param host? string
--- @param port? integer|string
--- @param family? integer
--- @param socktype? integer
--- @param protocol? integer
--- @param flag? integer
--- @vararg integer flags
--- @return llsocket.addrinfo[]? list
--- @return string? err
function _llsocket_addrinfo.getaddrinfo(host, port, family, socktype, protocol,
                                        flag, ...)
end

--- get hostname and service name
--- @param flag? integer
--- @vararg integer
--- @return table<string, string>? nameinfo
--- @return string? err
function _llsocket_addrinfo:getnameinfo(flag, ...)
end

--- get an address
--- @return string? address
function _llsocket_addrinfo:addr()
end

--- get a port
--- @return integer? port
function _llsocket_addrinfo:port()
end

--- get a canonname
--- @return string? canonname
function _llsocket_addrinfo:canonname()
end

--- get a protocol
--- @return integer protocol
function _llsocket_addrinfo:protocol()
end

--- get a socktype
--- @return integer socktype
function _llsocket_addrinfo:socktype()
end

--- get a family
--- @return integer family
function _llsocket_addrinfo:family()
end

