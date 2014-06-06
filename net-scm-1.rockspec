package = "net"
version = "scm-1"
source = {
    url = "git://github.com/mah0x211/lua-net.git"
}
description = {
    summary = "net module",
    detailed = [[]],
    homepage = "https://github.com/mah0x211/lua-net", 
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "llsocket",
    "coevent",
    "halo"
}
build = {
    type = "builtin",
    modules = {
        net = "net.lua",
        ['net.util'] = "lib/util.lua",
        ['net.observer'] = "lib/observer.lua",
        ['net.socket'] = "lib/socket.lua",
        ['net.tcp'] = "lib/tcp.lua",
        ['net.tcp.server'] = "lib/tcp/server.lua",
        ['net.tcp.request'] = "lib/tcp/request.lua",
        ['net.tcp.client'] = "lib/tcp/client.lua",
    }
}

