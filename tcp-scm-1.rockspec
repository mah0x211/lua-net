package = "tcp"
version = "scm-1"
source = {
    url = "git://github.com/mah0x211/lua-tcp.git"
}
description = {
    summary = "tcp module",
    detailed = [[]],
    homepage = "https://github.com/mah0x211/lua-tcp", 
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
    "llsocket",
    "buffer"
}
build = {
    type = "builtin",
    modules = {
        tcp = "lib/tcp.lua",
        ['tcp.server'] = "lib/server.lua",
        ['tcp.request'] = "lib/request.lua",
    }
}

