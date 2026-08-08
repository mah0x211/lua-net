/**
 * Copyright (C) 2026 Masatoshi Fukunaga
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */

#define _GNU_SOURCE
#if defined(__APPLE__) && !defined(__APPLE_USE_RFC_3542)
# define __APPLE_USE_RFC_3542
#endif
#include "constants.h"

#include <netdb.h>
#include <netinet/in.h>
#include <netinet/ip6.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>

typedef struct {
    const char *name;
    int value;
} net_constant_t;

static int name2value(const net_constant_t *map, const char *name, int *value)
{
    for (const net_constant_t *entry = map; entry->name; entry++) {
        if (strcmp(entry->name, name) == 0) {
            *value = entry->value;
            return 1;
        }
    }
    return 0;
}

static const char *value2name(const net_constant_t *map, int value)
{
    for (const net_constant_t *entry = map; entry->name; entry++) {
        if (entry->value == value) {
            return entry->name;
        }
    }
    return NULL;
}

static const net_constant_t FAMILY_MAP[] = {
    {"unspec", AF_UNSPEC},
    {"unix",   AF_UNIX  },
    {"inet",   AF_INET  },
    {"inet6",  AF_INET6 },
#ifdef AF_PACKET
    {"packet", AF_PACKET},
#endif
#ifdef AF_ROUTE
    {"route",  AF_ROUTE },
#endif
#ifdef AF_LINK
    {"link",   AF_LINK  },
#endif
    {NULL,     0        },
};

static const net_constant_t SOCKTYPE_MAP[] = {
    {"unspec",    0             },
    {"stream",    SOCK_STREAM   },
    {"dgram",     SOCK_DGRAM    },
    {"seqpacket", SOCK_SEQPACKET},
#ifdef SOCK_RAW
    {"raw",       SOCK_RAW      },
#endif
#ifdef SOCK_RDM
    {"rdm",       SOCK_RDM      },
#endif
    {NULL,        0             },
};

static const net_constant_t PROTOCOL_MAP[] = {
    {"auto",   0             },
#ifdef IPPROTO_ICMP
    {"icmp",   IPPROTO_ICMP  },
#endif
#ifdef IPPROTO_IGMP
    {"igmp",   IPPROTO_IGMP  },
#endif
    {"tcp",    IPPROTO_TCP   },
    {"udp",    IPPROTO_UDP   },
#ifdef IPPROTO_IPV6
    {"ipv6",   IPPROTO_IPV6  },
#endif
#ifdef IPPROTO_RAW
    {"raw",    IPPROTO_RAW   },
#endif
#ifdef IPPROTO_ICMPV6
    {"icmpv6", IPPROTO_ICMPV6},
#endif
#ifdef IPPROTO_SCTP
    {"sctp",   IPPROTO_SCTP  },
#endif
    {NULL,     0             },
};

static const net_constant_t SHUTDOWN_MAP[] = {
    {"rd",   SHUT_RD  },
    {"wr",   SHUT_WR  },
    {"rdwr", SHUT_RDWR},
    {NULL,   0        },
};

static const net_constant_t MSGFLAG_MAP[] = {
#ifdef MSG_BATCH
    {"batch",        MSG_BATCH       },
#endif
#ifdef MSG_CMSG_CLOEXEC
    {"cmsg_cloexec", MSG_CMSG_CLOEXEC},
#endif
#ifdef MSG_CONFIRM
    {"confirm",      MSG_CONFIRM     },
#endif
#ifdef MSG_CTRUNC
    {"ctrunc",       MSG_CTRUNC      },
#endif
#ifdef MSG_DONTROUTE
    {"dontroute",    MSG_DONTROUTE   },
#endif
#ifdef MSG_DONTWAIT
    {"dontwait",     MSG_DONTWAIT    },
#endif
#ifdef MSG_EOF
    {"eof",          MSG_EOF         },
#endif
#ifdef MSG_EOR
    {"eor",          MSG_EOR         },
#endif
#ifdef MSG_ERRQUEUE
    {"errqueue",     MSG_ERRQUEUE    },
#endif
#ifdef MSG_FASTOPEN
    {"fastopen",     MSG_FASTOPEN    },
#endif
#ifdef MSG_FLUSH
    {"flush",        MSG_FLUSH       },
#endif
#ifdef MSG_HAVEMORE
    {"havemore",     MSG_HAVEMORE    },
#endif
#ifdef MSG_HOLD
    {"hold",         MSG_HOLD        },
#endif
#ifdef MSG_MORE
    {"more",         MSG_MORE        },
#endif
#ifdef MSG_NEEDSA
    {"needsa",       MSG_NEEDSA      },
#endif
#ifdef MSG_NOSIGNAL
    {"nosignal",     MSG_NOSIGNAL    },
#endif
#ifdef MSG_OOB
    {"oob",          MSG_OOB         },
#endif
#ifdef MSG_PEEK
    {"peek",         MSG_PEEK        },
#endif
#ifdef MSG_PROBE
    {"probe",        MSG_PROBE       },
#endif
#ifdef MSG_RCVMORE
    {"rcvmore",      MSG_RCVMORE     },
#endif
#ifdef MSG_SEND
    {"send",         MSG_SEND        },
#endif
// MSG_TRUNC is intentionally omitted from the input-flag map.  On
// Linux datagram, raw, and seqpacket sockets, MSG_TRUNC as a recv-
// family input makes the syscall return the full original packet
// length rather than the number of bytes actually copied into the
// caller buffer, which would otherwise leak adjacent memory when the
// buffer is pushed to Lua as a string.  Callers observe MSG_TRUNC
// only via the msg_flags field surfaced by recvmsg().
#ifdef MSG_TRYHARD
    {"tryhard",      MSG_TRYHARD     },
#endif
#ifdef MSG_WAITALL
    {"waitall",      MSG_WAITALL     },
#endif
#ifdef MSG_WAITFORONE
    {"waitforone",   MSG_WAITFORONE  },
#endif
#ifdef MSG_WAITSTREAM
    {"waitstream",   MSG_WAITSTREAM  },
#endif
    {NULL,           0               },
};

static const net_constant_t CMSG_LEVEL_MAP[] = {
    {"socket", SOL_SOCKET  },
    {"ip",     IPPROTO_IP  },
    {"ipv6",   IPPROTO_IPV6},
    {"tcp",    IPPROTO_TCP },
    {"udp",    IPPROTO_UDP },
    {NULL,     0           },
};

static const net_constant_t CMSG_SOCKET_TYPE_MAP[] = {
    {"rights",      SCM_RIGHTS     },
#ifdef SCM_TIMESTAMP
    {"timestamp",   SCM_TIMESTAMP  },
#endif
#if defined(SCM_CREDENTIALS)
    {"credentials", SCM_CREDENTIALS},
#elif defined(SCM_CREDS)
    {"credentials", SCM_CREDS},
#endif
    {NULL,          0              },
};

static const net_constant_t CMSG_IP_TYPE_MAP[] = {
    {"ttl", IP_TTL},
    {"tos", IP_TOS},
    {NULL,  0     },
};

static const net_constant_t CMSG_IPV6_TYPE_MAP[] = {
    {"pktinfo",  IPV6_PKTINFO },
    {"hoplimit", IPV6_HOPLIMIT},
    {"tclass",   IPV6_TCLASS  },
    {"hopopts",  IPV6_HOPOPTS },
    {"dstopts",  IPV6_DSTOPTS },
    {"rthdr",    IPV6_RTHDR   },
    {NULL,       0            },
};

static const net_constant_t *cmsg_type_map(int level)
{
    switch (level) {
    case SOL_SOCKET:
        return CMSG_SOCKET_TYPE_MAP;
    case IPPROTO_IP:
        return CMSG_IP_TYPE_MAP;
    case IPPROTO_IPV6:
        return CMSG_IPV6_TYPE_MAP;
    default:
        return NULL;
    }
}

static const net_constant_t ADDRINFO_FLAG_MAP[] = {
    {"numerichost",              AI_NUMERICHOST             },
    {"numericserv",              AI_NUMERICSERV             },
    {"passive",                  AI_PASSIVE                 },
    {"canonname",                AI_CANONNAME               },
    {"addrconfig",               AI_ADDRCONFIG              },
    {"v4mapped",                 AI_V4MAPPED                },
    {"all",                      AI_ALL                     },
#ifdef AI_IDN
    {"idn",                      AI_IDN                     },
#endif
#ifdef AI_CANONIDN
    {"canonidn",                 AI_CANONIDN                },
#endif
#ifdef AI_IDN_ALLOW_UNASSIGNED
    {"idn_allow_unassigned",     AI_IDN_ALLOW_UNASSIGNED    },
#endif
#ifdef AI_IDN_USE_STD3_ASCII_RULES
    {"idn_use_std3_ascii_rules", AI_IDN_USE_STD3_ASCII_RULES},
#endif
#ifdef AI_FQDN
    {"fqdn",                     AI_FQDN                    },
#endif
    {NULL,                       0                          },
};

static const net_constant_t NAMEINFO_FLAG_MAP[] = {
    {"numerichost", NI_NUMERICHOST},
    {"numericserv", NI_NUMERICSERV},
    {"nofqdn",      NI_NOFQDN     },
    {"namereqd",    NI_NAMEREQD   },
    {"dgram",       NI_DGRAM      },
    {NULL,          0             },
};

const char *net_family_name(int value)
{
    return value2name(FAMILY_MAP, value);
}

int net_family_value(const char *name, int *value)
{
    return name2value(FAMILY_MAP, name, value);
}

const char *net_socktype_name(int value)
{
    return value2name(SOCKTYPE_MAP, value);
}

int net_socktype_value(const char *name, int *value)
{
    return name2value(SOCKTYPE_MAP, name, value);
}

const char *net_protocol_name(int value)
{
    return value2name(PROTOCOL_MAP, value);
}

int net_protocol_value(const char *name, int *value)
{
    return name2value(PROTOCOL_MAP, name, value);
}

int net_shutdown_value(const char *name, int *value)
{
    return name2value(SHUTDOWN_MAP, name, value);
}

int net_msgflag_value(const char *name, int *value)
{
    return name2value(MSGFLAG_MAP, name, value);
}

const char *net_cmsg_level_name(int value)
{
    return value2name(CMSG_LEVEL_MAP, value);
}

int net_cmsg_level_value(const char *name, int *value)
{
    return name2value(CMSG_LEVEL_MAP, name, value);
}

const char *net_cmsg_type_name(int level, int value)
{
    const net_constant_t *map = cmsg_type_map(level);
    return map ? value2name(map, value) : NULL;
}

int net_cmsg_type_value(int level, const char *name, int *value)
{
    const net_constant_t *map = cmsg_type_map(level);
    return map ? name2value(map, name, value) : 0;
}

int net_addrinfo_flag_value(const char *name, int *value)
{
    return name2value(ADDRINFO_FLAG_MAP, name, value);
}

int net_nameinfo_flag_value(const char *name, int *value)
{
    return name2value(NAMEINFO_FLAG_MAP, name, value);
}
