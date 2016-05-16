package = "net"
version = "0.1.0-1"
source = {
    url = "git://github.com/mah0x211/lua-net.git",
    tag = "v0.1.0"
}
description = {
    summary = "net module",
    homepage = "https://github.com/mah0x211/lua-net",
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "halo >= 1.1.8",
    "llsocket"
}
build = {
    type = "builtin",
    modules = {
        net = "net.lua",
        ['net.stream'] = "lib/stream.lua",
        ['net.stream.addrinfo'] = "lib/stream/addrinfo.lua",
        ['net.stream.pair'] = "lib/stream/pair.lua",
        ['net.stream.inet.client'] = "lib/stream/inet/client.lua",
        ['net.stream.inet.server'] = "lib/stream/inet/server.lua",
        ['net.stream.unix.client'] = "lib/stream/unix/client.lua",
        ['net.stream.unix.server'] = "lib/stream/unix/server.lua",
        ['net.dgram'] = "lib/dgram.lua",
        ['net.dgram.addrinfo'] = "lib/dgram/addrinfo.lua",
        ['net.dgram.pair'] = "lib/dgram/pair.lua",
        ['net.dgram.inet'] = "lib/dgram/inet.lua",
        ['net.dgram.unix'] = "lib/dgram/unix.lua"
    }
}

