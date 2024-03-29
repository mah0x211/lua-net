package = "net"
version = "0.37.0-1"
source = {
    url = "git+https://github.com/mah0x211/lua-net.git",
    tag = "v0.37.0",
}
description = {
    summary = "net module",
    homepage = "https://github.com/mah0x211/lua-net",
    license = "MIT/X11",
    maintainer = "Masatoshi Fukunaga",
}
dependencies = {
    "lua >= 5.1",
    "errno >= 0.3.0",
    "error >= 0.8.0",
    "gpoll >= 0.8",
    "metamodule >= 0.3.3",
    "llsocket >= 0.16.0",
    "io-isfile >= 0.1.0",
    "io-fopen >= 0.1.3",
    "iovec >= 0.3",
    "isa >= 0.2.1",
    "libtls >= 3.4.1",
    "time-clock >= 0.4",
}
build = {
    type = "builtin",
    modules = {
        net = "net.lua",
        ["net.addrinfo"] = "lib/addrinfo.lua",
        ["net.cmsghdr"] = "lib/cmsghdr.lua",
        ["net.device"] = "lib/device.lua",
        ["net.env"] = "lib/env.lua",
        ["net.msghdr"] = "lib/msghdr.lua",
        ["net.socket"] = "lib/socket.lua",
        ["net.unix"] = "lib/unix.lua",
        ["net.stream"] = "lib/stream.lua",
        ["net.stream.unix"] = "lib/stream/unix.lua",
        ["net.stream.inet"] = "lib/stream/inet.lua",
        ["net.dgram"] = "lib/dgram.lua",
        ["net.dgram.inet"] = "lib/dgram/inet.lua",
        ["net.dgram.unix"] = "lib/dgram/unix.lua",
        ["net.tls"] = "lib/tls.lua",
        ["net.tls.config"] = "lib/tls/config.lua",
        ["net.tls.unix"] = "lib/tls/unix.lua",
        ["net.tls.stream"] = "lib/tls/stream.lua",
        ["net.tls.stream.inet"] = "lib/tls/stream/inet.lua",
        ["net.tls.stream.unix"] = "lib/tls/stream/unix.lua",
    },
}
