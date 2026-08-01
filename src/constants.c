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
#include "constants.h"

#include <netdb.h>
#include <netinet/in.h>
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
    {NULL,      0        },
};

static const net_constant_t SOCKTYPE_MAP[] = {
    {"unspec",    0             },
    {"stream",    SOCK_STREAM   },
    {"dgram",     SOCK_DGRAM    },
    {"seqpacket", SOCK_SEQPACKET},
    {NULL,         0             },
};

static const net_constant_t PROTOCOL_MAP[] = {
    {"auto", 0          },
    {"tcp",  IPPROTO_TCP},
    {"udp",  IPPROTO_UDP},
    {NULL,    0          },
};

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
    {NULL,                        0                          },
};

static const net_constant_t NAMEINFO_FLAG_MAP[] = {
    {"numerichost", NI_NUMERICHOST},
    {"numericserv", NI_NUMERICSERV},
    {"nofqdn",      NI_NOFQDN     },
    {"namereqd",    NI_NAMEREQD   },
    {"dgram",       NI_DGRAM      },
    {NULL,           0             },
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

int net_addrinfo_flag_value(const char *name, int *value)
{
    return name2value(ADDRINFO_FLAG_MAP, name, value);
}

int net_nameinfo_flag_value(const char *name, int *value)
{
    return name2value(NAMEINFO_FLAG_MAP, name, value);
}
