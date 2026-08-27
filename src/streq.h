/**
 *  Copyright (C) 2026 Masatoshi Fukunaga
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a
 *  copy of this software and associated documentation files (the "Software"),
 *  to deal in the Software without restriction, including without limitation
 *  the rights to use, copy, modify, merge, publish, distribute, sublicense,
 *  and/or sell copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 *  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *  DEALINGS IN THE SOFTWARE.
 *
 */

#ifndef net_streq_h
#define net_streq_h

#include <stddef.h>
#include <string.h>

/*
 * Lua strings are byte sequences that may contain embedded NULs, while
 * strcmp() stops at the first NUL and would match "keepalive\0x" against
 * "keepalive".  Compare the full lengths instead.
 *
 * Each buffer is immediately followed by its length; STR_EQ_LITERAL()
 * keeps that order and takes the C string literal last.  sizeof(lit)
 * counts the terminating NUL, so compare sizeof(lit) - 1 bytes against
 * the Lua string length, which never counts a terminator.
 */
#define STR_EQ(a, alen, b, blen)                                               \
    ((alen) == (blen) && memcmp((a), (b), (alen)) == 0)

#define STR_EQ_LITERAL(s, slen, lit)                                           \
    (sizeof(lit) - 1 == (slen) && memcmp((s), (lit), sizeof(lit) - 1) == 0)

#endif // net_streq_h
