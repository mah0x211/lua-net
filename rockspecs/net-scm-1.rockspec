rockspec_format = "3.0"
package = "net"
version = "scm-1"
source = {
    url = "git+https://github.com/mah0x211/lua-net.git",
}
description = {
    summary = "net module",
    homepage = "https://github.com/mah0x211/lua-net",
    license = "MIT/X11",
    maintainer = "Masatoshi Fukunaga",
}
dependencies = {
    "lua >= 5.1",
    "configh >= 0.3.0",
    "errno >= 0.3.0",
    "error >= 0.8.0",
    "fstat >= 0.2.3",
    "gpoll >= 0.8",
    "metamodule >= 0.3.3",
    "lauxhlib >= 0.6.2",
    "llsocket >= 0.16.0",
    "io-isfile >= 0.1.0",
    "io-fopen >= 0.1.3",
    "io-pread >= 0.1.0",
    "iovec >= 0.3",
    "time-clock >= 0.5.0",
}
external_dependencies = {
    -- external_dependencies field must be defined to preventing luarocks
    -- autodetecting dependencies and causing build failure when the
    -- dependencies are not found.
}
build_dependencies = {
    "luarocks-build-hooks >= 0.8.0",
}
build = {
    type = "hooks",
    before_build = {
        "$(pkgconfig)",
        "$(extra-vars)",
        "$(configh)",
    },
    pkgconfig_dependencies = {
        ["OPENSSL"] = {
            header = "openssl/ssl.h",
            library = "ssl",
        },
    },
    extra_variables = {
        CFLAGS = "-Wall -Wno-trigraphs -Wmissing-field-initializers -Wreturn-type -Wmissing-braces -Wparentheses -Wno-switch -Wunused-function -Wunused-label -Wunused-parameter -Wunused-variable -Wunused-value -Wuninitialized -Wunknown-pragmas -Wshadow -Wsign-compare",
    },
    conditional_variables = {
        NET_COVERAGE = {
            CFLAGS = "--coverage",
            LIBFLAG = "--coverage",
        },
    },
    modules = {
        net = "net.lua",
        ["net.addrinfo"] = {
            sources = {
                "src/addrinfo.c",
                "src/constants.c",
            },
            incdirs = {
                "src",
                "$(DEP_ERROR_INCDIR)",
                "$(DEP_LAUXHLIB_INCDIR)",
            },
            configh = {
                output = "src/config.h",
                output_status = true,
                cc = "$(CC)",
                features = {
                    "_GNU_SOURCE",
                },
                members = {
                    ["sys/socket.h"] = {
                        ["struct sockaddr"] = {
                            "sa_len",
                        },
                    },
                },
            },
        },
        ["net.device"] = "lib/device.lua",
        ["net.env"] = "lib/env.lua",
        ["net.socket"] = {
            sources = {
                "src/socket.c",
                "src/socket_constants.c",
                "src/cmsghdr.c",
                "src/gcthread.c",
            },
            incdirs = {
                "src",
                "$(DEP_ERROR_INCDIR)",
                "$(DEP_LAUXHLIB_INCDIR)",
                "$(DEP_ERRNO_INCDIR)",
            },
            configh = {
                output = "src/config.h",
                output_status = true,
                cc = "$(CC)",
                features = {
                    "_GNU_SOURCE",
                },
                funcs = {
                    ["sys/socket.h"] = {
                        "accept4",
                    },
                    ["sys/sendfile.h"] = {
                        "sendfile",
                    },
                },
                members = {
                    ["sys/socket.h"] = {
                        ["struct sockaddr"] = {
                            "sa_len",
                        },
                    },
                },
            },
        },
        ["net.unix"] = "lib/unix.lua",
        ["net.stream"] = "lib/stream.lua",
        ["net.stream.unix"] = "lib/stream/unix.lua",
        ["net.stream.inet"] = "lib/stream/inet.lua",
        ["net.dgram"] = "lib/dgram.lua",
        ["net.dgram.inet"] = "lib/dgram/inet.lua",
        ["net.dgram.unix"] = "lib/dgram/unix.lua",
        ["net.tls"] = "lib/tls.lua",
        ["net.tls.unix"] = "lib/tls/unix.lua",
        ["net.tls.stream"] = "lib/tls/stream.lua",
        ["net.tls.stream.inet"] = "lib/tls/stream/inet.lua",
        ["net.tls.stream.unix"] = "lib/tls/stream/unix.lua",
        ["net.tls.context"] = {
            sources = {
                "src/tls_context.c",
                "src/tls_bio.c",
            },
            incdirs = {
                "$(DEP_ERROR_INCDIR)",
                "$(DEP_LAUXHLIB_INCDIR)",
                "$(OPENSSL_INCDIR)",
            },
            libdirs = {
                "$(OPENSSL_LIBDIR)",
            },
            libraries = {
                "$(OPENSSL_LIB)",
            },
        },
        ["net.tls.client"] = {
            sources = "src/tls_client.c",
            incdirs = {
                "$(DEP_ERROR_INCDIR)",
                "$(DEP_LAUXHLIB_INCDIR)",
                "$(OPENSSL_INCDIR)",
            },
            libdirs = {
                "$(OPENSSL_LIBDIR)",
            },
            libraries = {
                "$(OPENSSL_LIB)",
            },
        },
        ["net.tls.server"] = {
            sources = "src/tls_server.c",
            incdirs = {
                "$(DEP_ERROR_INCDIR)",
                "$(DEP_LAUXHLIB_INCDIR)",
                "$(OPENSSL_INCDIR)",
            },
            libdirs = {
                "$(OPENSSL_LIBDIR)",
            },
            libraries = {
                "$(OPENSSL_LIB)",
            },
        },
    },
}
