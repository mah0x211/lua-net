/*
 *  Copyright (C) 2026 Masatoshi Fukunaga
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to
 *  deal in the Software without restriction, including without limitation the
 *  rights to use, copy, modify, merge, publish, distribute, sublicense,
 *  and/or sell copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *  DEALINGS IN THE SOFTWARE.
 */
#include "tls_bio.h"
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/socket.h>

#include "lua_errno.h"

/**
 * @brief Called by OpenSSL when a BIO is created.  We use this to initialize
 * the BIO's data pointer to NULL, and set the init flag to 1.  The BIO will be
 * associated with a tls_bio_buf_t later when we set up the BIOs for a
 * tls_ctx_t.
 *
 * @param bio The BIO being created.  The BIO's data pointer will be initialized
 * to NULL, and the init flag will be set to 1.
 * @return int Always returns 1 to indicate success.  OpenSSL ignores the return
 * value of this callback, so it doesn't matter what we return.
 */
static int bio_create(BIO *bio)
{
    BIO_set_init(bio, 1);
    return 1;
}

/**
 * @brief Called by OpenSSL when a BIO is freed.  We clear the data pointer and
 * reset the init flag.  The associated tls_bio_buf_t is a Lua userdata managed
 * by Lua's GC and must not be freed here.
 *
 * @param bio The BIO being freed.
 * @return int Always returns 1 to indicate success.
 */
static int bio_destroy(BIO *bio)
{
    BIO_set_data(bio, NULL);
    BIO_set_init(bio, 0);
    return 1;
}

/**
 * @brief Called by OpenSSL to perform various control operations on the BIO.
 * We only need to support the flush operation, which is a no-op for our BIOs
 * since we don't have any internal buffering.
 *
 * @param bio The BIO on which to perform the control operation.
 * @param cmd The control command to perform.
 * @param larg A long argument for the control command.
 * @param parg A pointer argument for the control command.
 * @return long The result of the control operation.  For unsupported commands,
 * we return 0.  For the flush command, we return 1.
 */
static long bio_ctrl(BIO *bio, int cmd, long larg, void *parg)
{
    (void)bio;
    (void)larg;
    (void)parg;
    return (cmd == BIO_CTRL_FLUSH) ? 1 : 0;
}

/**
 * @brief Called by OpenSSL to read ciphertext from the receive buffer (rxbuf).
 * OpenSSL reads raw network bytes (ciphertext) from this BIO to decrypt them
 * internally.  The rxbuf must have been pre-filled by tls_bio_fill() before
 * SSL_read() is called.
 *
 * @param bio The BIO being read.  The BIO's data pointer is the tls_bio_buf_t
 * (rxbuf) holding the ciphertext received from the network.
 * @param buf The buffer into which OpenSSL copies the ciphertext.
 * @param len The maximum number of bytes to copy into buf.
 * @return int The number of bytes copied, or -1 with the retry-read flag set
 * if rxbuf is empty.
 */
static int bio_rx_read(BIO *bio, char *buf, int len)
{
    tls_bio_buf_t *b = NULL;
    size_t avail     = 0;
    void *data       = NULL;
    int n            = 0;

    // Clear retry flags at the start of each call.  If we need to retry, we'll
    // set the appropriate flag before returning.
    BIO_clear_retry_flags(bio);
    if (len <= 0) {
        return 0;
    }

    // OpenSSL calls this function to get ciphertext from the network.
    // Copy data from rxbuf (filled by tls_bio_fill) into OpenSSL's buffer.
    b     = BIO_get_data(bio);
    avail = 0;
    data  = zring_data(&b->buf, &avail);
    if (!data) {
        BIO_set_retry_read(bio);
        return -1;
    }

    // Copy at most len bytes from rxbuf into OpenSSL's buffer, and consume them
    // from rxbuf.  If there are more than len bytes available, we'll return len
    // and leave the rest for the next call.
    n = ((size_t)len < avail) ? len : (int)avail;
    memcpy(buf, data, (size_t)n);
    zring_consume(&b->buf, (size_t)n);
    return n;
}

/**
 * @brief Called by OpenSSL when it has ciphertext ready to be sent to the
 * network. The ciphertext data is copied from OpenSSL's write buffer into
 * txbuf, where it will be picked up by tls_bio_drain and written to the
 * network.
 *
 * @param bio The BIO from which OpenSSL is trying to write ciphertext data. The
 * BIO's data pointer is a tls_bio_buf_t that contains the txbuf ring buffer
 * where the ciphertext data is stored.
 * @param buf The buffer containing the ciphertext data to be written.
 * @param len The number of bytes to write from buf into txbuf.
 * @return int The number of bytes written into txbuf, or -1 if a retry is
 * needed. If txbuf is full and cannot accept any more data, we return -1 and
 * set the retry write flag, so OpenSSL will know to call us again when txbuf
 * has space.
 */
static int bio_tx_write(BIO *bio, const char *buf, int len)
{
    tls_bio_buf_t *b = NULL;
    void *dst        = NULL;
    size_t space     = 0;
    int n            = 0;

    // Clear retry flags at the start of each call.  If we need to retry, we'll
    // set the appropriate flag before returning.
    BIO_clear_retry_flags(bio);
    if (len <= 0) {
        return 0;
    }

    // OpenSSL calls this function when it has ciphertext ready to send.
    // Copy it into txbuf; tls_bio_drain() will write it to the network.
    b   = BIO_get_data(bio);
    dst = zring_space(&b->buf, &space);
    if (!dst) {
        BIO_set_retry_write(bio);
        return -1;
    }

    // Copy at most len bytes from OpenSSL's write buffer into txbuf, and commit
    // them to txbuf.  If there is more than len bytes of space available, we'll
    // return len and leave the rest for the next call.  If there is no space
    // available, we'll return -1 and set the retry write flag, so OpenSSL will
    // call us again when txbuf has space.
    n = ((size_t)len < space) ? len : (int)space;
    memcpy(dst, buf, (size_t)n);
    zring_commit(&b->buf, (size_t)n);
    return n;
}

/**
 * @brief Called by OpenSSL to write a null-terminated string as ciphertext.
 * Delegates to bio_tx_write().
 *
 * @param bio The BIO being written.
 * @param str The null-terminated string to write.
 * @return int The number of bytes written, or -1 with the retry-write flag set
 * if txbuf is full.
 */
static int bio_tx_puts(BIO *bio, const char *str)
{
    return bio_tx_write(bio, str, (int)strlen(str));
}

/**
 * buf:consume(n: integer)
 *
 * Advance the read position by @p n bytes after draining the region
 * returned by buf:peek().  Raises an error if @p n is negative or exceeds
 * the contiguous segment reported by buf:peek().
 *
 * @param n  Number of bytes consumed from the peek region (>= 0).
 */
static int consume_lua(lua_State *L)
{
    tls_bio_t *bio = luaL_checkudata(L, 1, NET_TLS_BIO_MT);
    lua_Integer n  = lauxh_checkinteger(L, 2);

    if (n < 0 || zring_consume(&bio->tx.buf, (size_t)n) != 0) {
        // format directly with snprintf; lua_pushvfstring rejects %lld on
        // Lua 5.3+ and routing through luaL_error would parse the string
        // twice.  64 bytes covers "consume(-9223372036854775808)" comfortably.
        char buf[64];
        int len = snprintf(buf, sizeof(buf), "consume(%lld): out of range",
                           (long long)n);
        lua_pushlstring(L, buf, (size_t)len);
        return lua_error(L);
    }
    return 0;
}

/**
 * buf:peek() -> lightuserdata, integer
 *
 * Returns a pointer to the next contiguous readable region and its byte
 * length.  The caller should drain the region (e.g. via POSIX write()) and
 * then call buf:consume(n) to advance the read position.
 *
 * Returns nil, 0 when the buffer is empty.
 *
 * @note The returned pointer is only valid until the next call that mutates
 *       the buffer.  Do not retain it across yield points.
 */
static int peek_lua(lua_State *L)
{
    tls_bio_t *bio = luaL_checkudata(L, 1, NET_TLS_BIO_MT);
    size_t len     = 0;
    void *ptr      = zring_data(&bio->tx.buf, &len);

    if (!ptr) {
        lua_pushnil(L);
        lua_pushinteger(L, 0);
    } else {
        lua_pushlightuserdata(L, ptr);
        lua_pushinteger(L, (lua_Integer)len);
    }
    return 2;
}

static int drain_lua(lua_State *L)
{
    tls_bio_t *bio = luaL_checkudata(L, 1, NET_TLS_BIO_MT);
    size_t len     = 0;
    void *data     = NULL;
    ssize_t n      = 0;
    ssize_t total  = 0;

    if (bio->fd < 0) {
        // bio has already been freed
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "drain");
        return 2;
    }

    // Drain as much data as possible from txbuf to the network until txbuf is
    // empty or we get EAGAIN/EWOULDBLOCK.
RETRY:
    data = zring_data(&bio->tx.buf, &len);
    if (!data) {
        // fully drained
        lua_pushinteger(L, total);
        return 1;
    }

    // never raise SIGPIPE; send(fd, buf, len, 0) is equivalent to write()
#ifndef MSG_NOSIGNAL
# define MSG_NOSIGNAL 0
#endif

    n = send(bio->fd, data, len, MSG_NOSIGNAL);
    switch (n) {
    case -1:
        if (errno == EINTR) {
            goto RETRY;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
RET_EAGAIN:
            lua_pushinteger(L, total);
            lua_pushnil(L);
            lua_pushboolean(L, 1);
            return 3;
        }
        // got a fatal error
        lua_pushnil(L);
        lua_errno_new(L, errno, "drain");
        return 2;

    case 0:
        // write(2) returning 0 is not an error, but it means we can't make any
        // progress draining the buffer.  We'll treat it as EAGAIN to avoid
        // a busy loop.
        goto RET_EAGAIN;

    default:
        // Successfully wrote n bytes; consume them from txbuf and continue.
        zring_consume(&bio->tx.buf, (size_t)n);
        total += n;
        goto RETRY;
    }
}

/**
 * buf:commit(n: integer)
 *
 * Advance the write position by @p n bytes after filling the region
 * returned by buf:space().  Raises an error if @p n is negative or exceeds
 * the contiguous segment reported by buf:space().
 *
 * @param n  Number of bytes written into the space region (>= 0).
 */
static int commit_lua(lua_State *L)
{
    tls_bio_t *bio = luaL_checkudata(L, 1, NET_TLS_BIO_MT);
    lua_Integer n  = lauxh_checkinteger(L, 2);

    if (n < 0 || zring_commit(&bio->rx.buf, (size_t)n) != 0) {
        // format directly with snprintf; lua_pushvfstring rejects %lld on
        // Lua 5.3+ and routing through luaL_error would parse the string
        // twice.  64 bytes covers "commit(-9223372036854775808)" comfortably.
        char buf[64];
        int len = snprintf(buf, sizeof(buf), "commit(%lld): out of range",
                           (long long)n);
        lua_pushlstring(L, buf, (size_t)len);
        return lua_error(L);
    }
    return 0;
}

/**
 * buf:space() -> lightuserdata, integer
 *
 * Returns a pointer to the next contiguous writable region and its byte
 * length.  The caller should fill the region (e.g. via POSIX read()) and
 * then call buf:commit(n) to advance the write position.
 *
 * Returns nil, 0 when the buffer is full.
 *
 * @note The returned pointer is only valid until the next call that mutates
 *       the buffer.  Do not retain it across yield points.
 */
static int space_lua(lua_State *L)
{
    tls_bio_t *bio = luaL_checkudata(L, 1, NET_TLS_BIO_MT);
    size_t len     = 0;
    void *ptr      = zring_space(&bio->rx.buf, &len);

    if (!ptr) {
        lua_pushnil(L);
        lua_pushinteger(L, 0);
    } else {
        lua_pushlightuserdata(L, ptr);
        lua_pushinteger(L, (lua_Integer)len);
    }
    return 2;
}

static int fill_lua(lua_State *L)
{
    tls_bio_t *bio = luaL_checkudata(L, 1, NET_TLS_BIO_MT);
    size_t len     = 0;
    void *space    = NULL;
    ssize_t total  = 0;
    ssize_t n      = 0;

    if (bio->fd < 0) {
        // bio has already been freed
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "fill");
        return 2;
    }

    space = zring_space(&bio->rx.buf, &len);
    if (!space) {
        lua_pushnil(L);
        lua_errno_new(L, ENOBUFS, "fill");
        return 2;
    }

RETRY:
    n = read(bio->fd, space, len);
    switch (n) {
    case -1:
        if (errno == EINTR) {
            goto RETRY;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (!total) {
                // no data read
                lua_pushnil(L);
                lua_pushnil(L);
                lua_pushboolean(L, 1);
                return 3;
            }
            // partially filled; return the number of bytes filled so far
            lua_pushinteger(L, total);
            return 1;
        }
        // got a fatal error
        lua_pushnil(L);
        lua_errno_new(L, errno, "fill");
        return 2;

    case 0:
        // closed by peer.  Bytes already read within this call must not be
        // discarded: report them as a normal fill so the caller processes
        // the buffered ciphertext (e.g. a close_notify) before observing
        // EOF on the next call.
        if (total == 0) {
            // mark EOF by returning 0 without an error
            return 0;
        }
        lua_pushinteger(L, (lua_Integer)total);
        return 1;

    default:
        // Successfully read n bytes; commit them to rxbuf and continue.
        zring_commit(&bio->rx.buf, (size_t)n);
        total += n;
        space = zring_space(&bio->rx.buf, &len);
        if (space) {
            // rxbuf still has room; keep pulling until read reports
            // EAGAIN or EOF.  The prior !space branch also fell into
            // RETRY, which meant read(fd, NULL, 0) returned 0 and the
            // fill loop reported EOF for a merely-full ring.
            goto RETRY;
        }
        lua_pushinteger(L, (lua_Integer)total);
        return 1;
    }
}

static int tostring_lua(lua_State *L)
{
    tls_bio_t *bio = luaL_checkudata(L, 1, NET_TLS_BIO_MT);
    lua_pushfstring(L, NET_TLS_BIO_MT ": %p", (void *)bio);
    return 1;
}

void tls_bio_free(lua_State *L, tls_bio_t *bio)
{
    if (!bio) {
        return;
    }
    if (bio->rx.mem) {
        BUF_MEM_free(bio->rx.mem);
        bio->rx.mem = NULL;
    }
    if (bio->tx.mem) {
        BUF_MEM_free(bio->tx.mem);
        bio->tx.mem = NULL;
    }
    bio->fd  = -1;
    bio->ref = lauxh_unref(L, bio->ref);
}

static int gc_lua(lua_State *L)
{
    tls_bio_t *bio = luaL_checkudata(L, 1, NET_TLS_BIO_MT);
    tls_bio_free(L, bio);
    return 0;
}

static inline int bio_buf_init(tls_bio_buf_t *b, size_t cap)
{
    b->mem = BUF_MEM_new();
    if (!b->mem) {
        return -1;
    } else if (BUF_MEM_grow(b->mem, cap) == 0) {
        // grow failed: free and NULL so callers do not double-free.
        BUF_MEM_free(b->mem);
        b->mem = NULL;
        return -1;
    }
    zring_init(&b->buf, b->mem->data, cap);
    return 0;
}

tls_bio_t *tls_bio_new(lua_State *L, int fd, size_t cap)
{
    tls_bio_t *bio = lua_newuserdata(L, sizeof(tls_bio_t));

    bio->fd     = fd;
    bio->ref    = LUA_NOREF;
    bio->rx.mem = NULL;
    bio->tx.mem = NULL;
    if (bio_buf_init(&bio->rx, cap) != 0 || bio_buf_init(&bio->tx, cap) != 0) {
        // bio_buf_init NULLs its own mem on failure, so only the rx side
        // (if it succeeded before tx failed) needs releasing here.
        if (bio->rx.mem) {
            BUF_MEM_free(bio->rx.mem);
            bio->rx.mem = NULL;
        }
        return NULL;
    }
    lauxh_setmetatable(L, NET_TLS_BIO_MT);
    bio->ref = lauxh_ref(L);
    return bio;
}

static BIO_METHOD *g_rx_bio_method = NULL;
static BIO_METHOD *g_tx_bio_method = NULL;

int tls_bio_setup(SSL *ssl, tls_bio_t *bio)
{
    BIO *rxbio = NULL;
    BIO *txbio = NULL;

    rxbio = BIO_new(g_rx_bio_method);
    if (!rxbio) {
        // hard error, no BIO allocated
        return -1;
    }
    BIO_set_data(rxbio, &bio->rx);

    txbio = BIO_new(g_tx_bio_method);
    if (!txbio) {
        BIO_free(rxbio);
        return -1; /* hard error, no BIO allocated */
    }
    BIO_set_data(txbio, &bio->tx);

    /* SSL_set_bio transfers ownership of both BIOs to ssl.
     * SSL_free() will free them — do not call BIO_free() separately. */
    SSL_set_bio(ssl, rxbio, txbio);
    return 0;
}

static void bio_init_once(void)
{
    g_rx_bio_method = BIO_meth_new(BIO_TYPE_SOURCE_SINK | BIO_get_new_index(),
                                   "net.tls.rxbio");
    BIO_meth_set_read(g_rx_bio_method, bio_rx_read);
    BIO_meth_set_ctrl(g_rx_bio_method, bio_ctrl);
    BIO_meth_set_create(g_rx_bio_method, bio_create);
    BIO_meth_set_destroy(g_rx_bio_method, bio_destroy);

    g_tx_bio_method = BIO_meth_new(BIO_TYPE_SOURCE_SINK | BIO_get_new_index(),
                                   "net.tls.txbio");
    BIO_meth_set_write(g_tx_bio_method, bio_tx_write);
    BIO_meth_set_puts(g_tx_bio_method, bio_tx_puts);
    BIO_meth_set_ctrl(g_tx_bio_method, bio_ctrl);
    BIO_meth_set_create(g_tx_bio_method, bio_create);
    BIO_meth_set_destroy(g_tx_bio_method, bio_destroy);
}

/**
 * @brief Initialises the module-level BIO_METHOD singletons used by all TLS
 * connections.  Safe to call from multiple threads; the actual
 * initialisation runs exactly once via pthread_once().
 */
void tls_bio_init(lua_State *L)
{
    static pthread_once_t g_bio_init_once = PTHREAD_ONCE_INIT;
    pthread_once(&g_bio_init_once, bio_init_once);

    // rxbuffer
    luaL_newmetatable(L, NET_TLS_BIO_MT);
    lauxh_pushfn2tbl(L, "__gc", gc_lua);
    lauxh_pushfn2tbl(L, "__tostring", tostring_lua);
    lua_newtable(L);

    lauxh_pushfn2tbl(L, "fill", fill_lua);
    lauxh_pushfn2tbl(L, "space", space_lua);
    lauxh_pushfn2tbl(L, "commit", commit_lua);

    lauxh_pushfn2tbl(L, "drain", drain_lua);
    lauxh_pushfn2tbl(L, "peek", peek_lua);
    lauxh_pushfn2tbl(L, "consume", consume_lua);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}
