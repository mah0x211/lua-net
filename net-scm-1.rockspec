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
    "coevent"
}
build = {
    type = "builtin",
    modules = {
        net = "net.lua",
        ['net.tcp'] = "lib/tcp.lua",
        ['net.tcp.server'] = "lib/tcp/server.lua",
        ['net.tcp.request'] = "lib/tcp/request.lua",
    }
}

