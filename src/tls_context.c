/*
 *  Copyright (C) 2023 Masatoshi Fukunaga
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
 *
 *
 * Transport path:
 *   POSIX read(fd)  --> rxbuf --> rxbio --> SSL_read  --> Lua
 *   Lua             --> SSL_write --> txbio --> txbuf --> POSIX write(fd)
 *
 * Both BIOs are backed by ring buffers in tls_bio_buf_t.  The ring buffers hold
 * the ciphertext that is exchanged with the network fd, keeping OpenSSL from
 * touching the fd directly.
 */
// project
#include "tls.h"
// depend
#include "lauxhlib.h"
#include "lua_errno.h"
// lua
#include <lauxlib.h>
// system
#include <arpa/inet.h>
#include <errno.h>
#include <limits.h>
#include <netinet/in.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509_vfy.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>

static int do_handshake(lua_State *L, tls_ctx_t *ctx)
{
    int rv = 0;

    // Only SSL_accept runs Lua callbacks from inside the handshake (the SNI
    // callback and the ALPN select callback it may switch to); those run on
    // the lua_State that drives the handshake, so tls_server_t.L is
    // refreshed around the call and the connection context is exposed via
    // app_data for the SNI-selected server's callbacks.  SSL_connect has no
    // client-side Lua callbacks and needs none of this.
    if (ctx->handshake_cb == SSL_accept) {
        tls_server_t *p     = (tls_server_t *)ctx->parent;
        lua_State *prev_L   = p->L;
        SSL_set_app_data(ctx->ssl, ctx);
        p->L = L;
        rv   = ctx->handshake_cb(ctx->ssl);
        p->L = prev_L;
        SSL_set_app_data(ctx->ssl, NULL);
    } else if (ctx->handshake_cb) {
        rv = ctx->handshake_cb(ctx->ssl);
    }

    return rv;
}

static int handshake_bio_lua(lua_State *L, tls_ctx_t *ctx)
{
    int rv = do_handshake(L, ctx);
    if (rv == 1) {
        // Handshake is only complete once the last handshake flight has been
        // flushed to the transport.
        ctx->handshake_cb = NULL;
        lua_pushboolean(L, 1);
        return 1;
    }

    rv = SSL_get_error(ctx->ssl, rv);
    switch (rv) {
    case SSL_ERROR_WANT_READ:
    case SSL_ERROR_WANT_WRITE:
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        lua_pushinteger(L, rv);
        return 3;

    case SSL_ERROR_ZERO_RETURN:
        // connection closed
        return 0;

    default:
        lua_pushboolean(L, 0);
        if (ctx->handshake_cb == SSL_connect) {
            // SSL_connect failure is more likely to be a server-side issue, so
            // use a different default error message to hint that to users.
            tls_push_error(L, "SSL_connect",
                           "failed to initiate SSL/TLS handshake with server");
        } else {
            // SSL_accept failure is more likely to be a client-side issue, so
            // use a different default error message to hint that to users.
            tls_push_error(L, "SSL_accept",
                           "failed to initiate SSL/TLS handshake with client");
        }
        return 2;
    }
}

static int handshake_lua(lua_State *L)
{
    tls_ctx_t *ctx = luaL_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    int rv         = 0;

    if (!ctx->ssl) {
        lua_pushboolean(L, 0);
        lua_errno_new((L), EINVAL, "handshake");
        return 2;
    } else if (!ctx->handshake_cb) {
        lua_pushboolean(L, 1);
        return 1;
    }

    ERR_clear_error();
    if (ctx->bio) {
        return handshake_bio_lua(L, ctx);
    }

    rv = do_handshake(L, ctx);
    if (rv != 1) {
        rv = SSL_get_error(ctx->ssl, rv);
        switch (rv) {
        case SSL_ERROR_WANT_READ:
        case SSL_ERROR_WANT_WRITE:
            lua_pushboolean(L, 0);
            lua_pushnil(L);
            lua_pushinteger(L, rv);
            return 3;

        case SSL_ERROR_ZERO_RETURN:
            // connection closed
            return 0;
        }

        // error occurred
        lua_pushboolean(L, 0);
        if (ctx->handshake_cb == SSL_connect) {
            tls_push_error(L, "handshake.SSL_connect",
                           "failed to initiate SSL/TLS handshake with server");
        } else {
            tls_push_error(L, "handshake.SSL_accept",
                           "failed to initiate SSL/TLS handshake with client");
        }
        return 2;
    }

    // handshake success
    ctx->handshake_cb = NULL;
    lua_pushboolean(L, 1);
    return 1;
}

static int write_bio_lua(lua_State *L, tls_ctx_t *ctx, const char *buf,
                         size_t len)
{
    // drain first — pending SSL_write may have produced outgoing data that
    // needs to be sent before we can make progress with the new SSL_write
    int chunk  = (len > (size_t)INT_MAX) ? INT_MAX : (int)len;
    ssize_t rv = SSL_write(ctx->ssl, buf, chunk);
    if (rv > 0) {
        // SSL_write always produces ciphertext in txbuf; signal the caller to
        // drain it so the data actually reaches the peer.
        lua_pushinteger(L, rv);
        if ((size_t)rv == len) {
            // SSL_write always produces ciphertext in txbuf; signal the caller
            // to drain it so the data actually reaches the peer.
            return 1;
        }
        // Partial write (SSL_MODE_ENABLE_PARTIAL_WRITE): tell the caller
        // how many bytes were consumed and that another write is required,
        // so the wrapper resends the remainder just like the non-BIO
        // write_lua path.
        lua_pushnil(L);
        lua_pushinteger(L, SSL_ERROR_WANT_WRITE);
        return 3;
    }

    rv = SSL_get_error(ctx->ssl, (int)rv);
    switch (rv) {
    case SSL_ERROR_WANT_WRITE:
    case SSL_ERROR_WANT_READ:
        // buffer is full — drain it to make room for the pending SSL_write
        lua_pushinteger(L, 0);
        lua_pushnil(L);
        lua_pushinteger(L, rv);
        return 3;

    case SSL_ERROR_ZERO_RETURN:
        // connection closed
        return 0;

    default:
        lua_pushnil(L);
        tls_push_error(L, "write.SSL_write", "failed to write data");
        return 2;
    }
}

static int write_lua(lua_State *L)
{
    tls_ctx_t *ctx  = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    size_t len      = 0;
    const char *buf = lauxh_checklstring(L, 2, &len);
    // SSL_write() takes int; clamp to INT_MAX so a buffer larger than INT_MAX
    // is written in chunks instead of being truncated (same contract as
    // write_bio_lua).
    int chunk       = (len > (size_t)INT_MAX) ? INT_MAX : (int)len;
    ssize_t rv      = 0;

    if (!ctx->ssl) {
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "write");
        return 2;
    } else if (len == 0) {
        // nothing to write
        lua_pushinteger(L, 0);
        return 1;
    }

    ERR_clear_error();
    if (ctx->bio) {
        return write_bio_lua(L, ctx, buf, len);
    }

    rv = SSL_write(ctx->ssl, buf, chunk);
    if (rv <= 0) {
        rv = SSL_get_error(ctx->ssl, rv);
        switch (rv) {
        case SSL_ERROR_WANT_READ:
        case SSL_ERROR_WANT_WRITE:
            lua_pushinteger(L, 0);
            lua_pushnil(L);
            lua_pushinteger(L, rv);
            return 3;

        case SSL_ERROR_ZERO_RETURN:
            // connection closed
            return 0;
        }

        // error occurred
        lua_pushnil(L);
        tls_push_error(L, "write.SSL_write", "failed to write data");
        return 2;
    }

    lua_pushinteger(L, rv);
    if ((size_t)rv == len) {
        // all data was written
        return 1;
    }
    // not all data was written
    lua_pushnil(L);
    lua_pushinteger(L, SSL_ERROR_WANT_WRITE);
    return 3;
}

static int read_bio_lua(lua_State *L, tls_ctx_t *ctx, char *buf,
                        lua_Integer bufsiz)
{
    ssize_t rv = SSL_read(ctx->ssl, buf, (int)bufsiz);
    if (rv > 0) {
        lua_pushlstring(L, buf, (size_t)rv);
        return 1;
    }

    rv = SSL_get_error(ctx->ssl, (int)rv);
    switch (rv) {
    case SSL_ERROR_WANT_READ:
    case SSL_ERROR_WANT_WRITE:
        // need to read data or drain data
        lua_pushnil(L);
        lua_pushnil(L);
        lua_pushinteger(L, rv);
        return 3;

    case SSL_ERROR_ZERO_RETURN:
        // connection closed
        return 0;

    default:
        lua_pushnil(L);
        tls_push_error(L, "read.SSL_read", "failed to read data");
        return 2;
    }
}

static int read_lua(lua_State *L)
{
    tls_ctx_t *ctx     = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    lua_Integer bufsiz = lauxh_optinteger(L, 2, BUFSIZ);
    void *buf          = NULL;
    ssize_t rv         = 0;

    if (!ctx->ssl) {
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "read");
        return 2;
    }

    // bufsiz < 0 means "use the default buffer size"
    // bufsiz == 0 is passed through to SSL_read()
    if (bufsiz < 0) {
        bufsiz = BUFSIZ;
    } else if ((uint64_t)bufsiz > (uint64_t)INT_MAX) {
        // SSL_read() takes int; clamp the requested size so the int casts
        // below cannot turn a huge value into a negative length.
        bufsiz = INT_MAX;
    }
    buf = lua_newuserdata(L, bufsiz);

    ERR_clear_error();
    if (ctx->bio) {
        return read_bio_lua(L, ctx, buf, bufsiz);
    }

    rv = SSL_read(ctx->ssl, buf, (int)bufsiz);
    if (rv <= 0) {
        rv = SSL_get_error(ctx->ssl, rv);
        switch (rv) {
        case SSL_ERROR_WANT_READ:
        case SSL_ERROR_WANT_WRITE:
            lua_pushnil(L);
            lua_pushnil(L);
            lua_pushinteger(L, rv);
            return 3;

        case SSL_ERROR_ZERO_RETURN:
            // connection closed
            return 0;
        }

        // error occurred
        lua_pushnil(L);
        tls_push_error(L, "read.SSL_read", "failed to read data");
        return 2;
    }

    lua_pushlstring(L, buf, rv);
    return 1;
}

/**
 * @brief Release the SSL object after a completed shutdown.  The BIO buffers
 * are kept so the caller can drain the final close_notify ciphertext before
 * disposing of the context with close().
 */
static void cleanup_ssl(tls_ctx_t *ctx)
{
    SSL_free(ctx->ssl); /* also frees rxbio and txbio */
    ctx->ssl = NULL;
}

static void cleanup_context(lua_State *L, tls_ctx_t *ctx)
{
    cleanup_ssl(ctx);
    if (ctx->bio) {
        tls_bio_free(L, ctx->bio);
        ctx->bio = NULL;
    }
    if (ctx->parent_ref != LUA_NOREF) {
        lauxh_unref(L, ctx->parent_ref);
        ctx->parent_ref = LUA_NOREF;
    }
    ctx->parent       = NULL;
    ctx->handshake_cb = NULL;
}

static int close_lua(lua_State *L)
{
    tls_ctx_t *ctx = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);

    // unconditional resource disposal; the graceful TLS shutdown is
    // performed by shutdown().
    cleanup_context(L, ctx);
    lua_pushboolean(L, 1);
    return 1;
}

static int shutdown_bio_lua(lua_State *L, tls_ctx_t *ctx)
{
    // SSL was fully connected — exchange close_notify with the peer.
    // On completion only the SSL object is released; the BIO buffers are
    // kept for the final drain and disposed of by close().
    size_t rxsize = tls_bio_rx_size(ctx->bio);
    int rv        = 0;

RETRY:
    rv = SSL_shutdown(ctx->ssl);
    switch (rv) {
    case 1:
        // Bidirectional shutdown complete.  "Sent" only means OpenSSL wrote
        // the close_notify into our TX BIO ring, so the caller must still
        // drain it to the socket before disposing of the context.
        cleanup_ssl(ctx);
        lua_pushboolean(L, 1);
        return 1;

    case 0:
        // Our close_notify was written to txbuf
        // user needs to send it to the peer and wait for the peer's
        // close_notify then retry SSL_shutdown to complete the shutdown
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        lua_pushinteger(L, SSL_ERROR_WANT_WRITE);
        return 3;
    }

    // rv < 0 indicates an error; determine if it's retryable or fatal
    rv = SSL_get_error(ctx->ssl, rv);
    switch (rv) {
    case SSL_ERROR_WANT_WRITE:
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        lua_pushinteger(L, rv);
        return 3;

    case SSL_ERROR_WANT_READ: {
        // SSL_MODE_AUTO_RETRY stays disabled (this library is fully
        // non-blocking), so SSL_shutdown() discards at most one buffered
        // non-application-data record (e.g. a session ticket) per call.
        // A WANT_READ with unread ciphertext still in the ring means the
        // memory BIO is readable right now; per the OpenSSL retry rules we
        // repeat the call here instead of sending the caller off to poll
        // the socket for data that is already buffered.
        size_t rxsize_after = tls_bio_rx_size(ctx->bio);
        if (rxsize_after != rxsize && rxsize_after > 0) {
            rxsize = rxsize_after;
            goto RETRY;
        }
        // Drain any pending TX before waiting for the peer's close_notify;
        // otherwise we deadlock if our close_notify hasn't been sent yet.
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        lua_pushinteger(
            L, tls_bio_tx_size(ctx->bio) > 0 ? SSL_ERROR_WANT_WRITE : rv);
        return 3;
    }

    default:
        /* Other SSL error: report it; the caller disposes via close() */
        lua_pushboolean(L, 0);
        tls_push_error(L, "shutdown.SSL_shutdown",
                       "failed to shutdown SSL context");
        return 2;
    }
}

static int shutdown_lua(lua_State *L)
{
    tls_ctx_t *ctx = luaL_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    int rv         = 0;

    if (!ctx->ssl) {
        // already shut down or disposed
        lua_pushboolean(L, 1);
        return 1;
    } else if (ctx->handshake_cb) {
        // if handshake_cb is not NULL, the handshake is not complete and the
        // peer has no state about this connection, so there is nothing to
        // shut down; the caller disposes of the context with close().
        lua_pushboolean(L, 1);
        return 1;
    }

    ERR_clear_error();
    if (ctx->bio) {
        return shutdown_bio_lua(L, ctx);
    }

    rv = SSL_shutdown(ctx->ssl);
    if (rv >= 0) {
        // our close_notify was handed to the socket; do not wait for the
        // peer's close_notify — the caller disposes via close().
        cleanup_ssl(ctx);
        lua_pushboolean(L, 1);
        return 1;
    }

    rv = SSL_get_error(ctx->ssl, rv);
    switch (rv) {
    case SSL_ERROR_WANT_READ:
    case SSL_ERROR_WANT_WRITE:
        lua_pushboolean(L, 0);
        lua_pushnil(L);
        lua_pushinteger(L, rv);
        return 3;

    default:
        lua_pushboolean(L, 0);
        tls_push_error(L, "shutdown.SSL_shutdown",
                       "failed to shutdown SSL context");
        return 2;
    }
}

static int get_bio_lua(lua_State *L)
{
    tls_ctx_t *ctx = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);

    if (ctx->bio) {
        lauxh_pushref(L, ctx->bio->ref);
        return 1;
    } else if (!ctx->ssl) {
        // the context has been disposed
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "get_bio");
        return 2;
    }
    return 0;
}

static int get_alpn_lua(lua_State *L)
{
    tls_ctx_t *ctx            = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    const unsigned char *data = NULL;
    unsigned int len          = 0;

    if (!ctx->ssl) {
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "get_alpn");
        return 2;
    }

    SSL_get0_alpn_selected(ctx->ssl, &data, &len);
    if (len == 0) {
        // no ALPN was negotiated
        return 0;
    }
    lua_pushlstring(L, (const char *)data, len);
    return 1;
}

static int get_version_lua(lua_State *L)
{
    tls_ctx_t *ctx = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);

    if (!ctx->ssl) {
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "get_version");
        return 2;
    }
    lua_pushstring(L, SSL_get_version(ctx->ssl));
    return 1;
}

static int get_cipher_lua(lua_State *L)
{
    tls_ctx_t *ctx          = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    const SSL_CIPHER *cipher = NULL;

    if (!ctx->ssl) {
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "get_cipher");
        return 2;
    }
    // no cipher suite is selected before the handshake completes
    cipher = SSL_get_current_cipher(ctx->ssl);
    if (!cipher) {
        return 0;
    }
    lua_pushstring(L, SSL_CIPHER_get_name(cipher));
    return 1;
}

static int get_peer_cert_lua(lua_State *L)
{
    tls_ctx_t *ctx = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    X509 *cert     = NULL;
    BIO *bio       = NULL;

    if (!ctx->ssl) {
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "get_peer_cert");
        return 2;
    }
    // the peer presented no certificate before / without the handshake; on
    // the server side this is the client certificate, on the client side
    // the server certificate
    cert = SSL_get_peer_certificate(ctx->ssl);
    if (!cert) {
        return 0;
    }

    bio = BIO_new(BIO_s_mem());
    if (!bio || PEM_write_bio_X509(bio, cert) != 1) {
        X509_free(cert);
        BIO_free(bio);
        return luaL_error(L, "failed to encode the peer certificate");
    }
    char *ptr = NULL;
    long len  = BIO_get_mem_data(bio, &ptr);
    lua_pushlstring(L, ptr, (size_t)len);
    X509_free(cert);
    BIO_free(bio);
    return 1;
}

static int get_verify_result_lua(lua_State *L)
{
    tls_ctx_t *ctx = lauxh_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    long res       = 0;

    if (!ctx->ssl) {
        lua_pushnil(L);
        lua_errno_new(L, EINVAL, "get_verify_result");
        return 2;
    }
    res = SSL_get_verify_result(ctx->ssl);
    if (res == X509_V_OK) {
        lua_pushboolean(L, 1);
        return 1;
    }
    lua_pushnil(L);
    lua_pushstring(L, X509_verify_cert_error_string(res));
    return 2;
}

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, NET_TLS_CONTEXT_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    tls_ctx_t *ctx = luaL_checkudata(L, 1, NET_TLS_CONTEXT_MT);
    cleanup_context(L, ctx);
    return 0;
}

static size_t get_max_encrypted_length(int minv, int maxv)
{
    const int versions[] = {
        TLS1_VERSION,
        TLS1_1_VERSION,
        TLS1_2_VERSION,
        TLS1_3_VERSION,
    };
    size_t cap = 0;
    size_t n   = sizeof(versions) / sizeof(versions[0]);

    for (size_t i = 0; i < n; i++) {
        int version = versions[i];

        if ((minv <= 0 || version >= minv) && (maxv <= 0 || version <= maxv)) {
            size_t len = tls_get_encrypted_length(version);
            if (len > cap) {
                cap = len;
            }
        }
    }

    if (cap == 0) {
        return tls_get_encrypted_length(TLS1_2_VERSION);
    }
    return cap;
}

static int encrypted_length_lua(lua_State *L)
{
    tls_protocol_t protocol = luaL_checkoption(L, 1, "default", TLS_PROTOCOLS);
    int minv                = 0;
    int maxv                = 0;

    tls_get_protocol_vers(protocol, &minv, &maxv);
    lua_pushinteger(L, (lua_Integer)get_max_encrypted_length(minv, maxv));
    return 1;
}

static inline size_t get_bio_bufcap(SSL *ssl, lua_Integer bufcap)
{
    size_t mincap = get_max_encrypted_length(SSL_get_min_proto_version(ssl),
                                             SSL_get_max_proto_version(ssl));

    if (bufcap <= 0 || (size_t)bufcap < mincap) {
        return mincap;
    }
    return (size_t)bufcap;
}

static int accept_lua(lua_State *L)
{
    tls_server_t *s    = luaL_checkudata(L, 1, NET_TLS_SERVER_MT);
    lua_Integer fdarg  = lauxh_checkinteger(L, 2);
    int use_bio        = lauxh_optboolean(L, 3, 0);
    lua_Integer bufcap = lauxh_optinteger(L, 4, 0);
    int fd             = 0;
    tls_ctx_t *ctx     = NULL;
    const char *errop  = NULL;
    const char *errmsg = NULL;

    // narrowing an out-of-range lua_Integer to int would hand OpenSSL an
    // unrelated descriptor number; reject before any allocation
    if (fdarg < 0 || fdarg > INT_MAX) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "accept");
        return 2;
    }
    fd = (int)fdarg;

    ctx               = lua_newuserdata(L, sizeof(tls_ctx_t));
    ctx->handshake_cb = SSL_accept;
    ctx->parent       = s;
    ctx->ssl          = SSL_new(s->ctx);
    ctx->bio          = NULL;
    ctx->parent_ref   = LUA_NOREF;
    lauxh_setmetatable(L, NET_TLS_CONTEXT_MT);
    ctx->parent_ref = lauxh_refat(L, 1);

    if (!ctx->ssl) {
        errop  = "accept.SSL_new";
        errmsg = "failed to create SSL context";
    } else if (use_bio) {
        size_t cap = get_bio_bufcap(ctx->ssl, bufcap);

        // if BIOs are used, SSL won't touch the fd directly, so we need to set
        // up the BIOs to enable the handshake and data exchange to work
        if (!(ctx->bio = tls_bio_new(L, fd, cap))) {
            errop  = "accept.tls_bio_new";
            errmsg = "failed to create tls_bio for SSL context";
        } else if (tls_bio_setup(ctx->ssl, ctx->bio) != 0) {
            errop  = "accept.tls_bio_setup";
            errmsg = "failed to set up BIOs for SSL context";
        } else {
            // successfully set up BIOs; ready for handshake
            return 1;
        }
    } else if (SSL_set_fd(ctx->ssl, fd) != 1) {
        errop  = "accept.SSL_set_fd";
        errmsg = "failed to set file descriptor";
    } else {
        // successfully set fd for SSL; ready for handshake
        return 1;
    }

    // error occurred
    cleanup_context(L, ctx);
    lua_pushnil(L);
    tls_push_error(L, errop, errmsg);
    return 2;
}

static int noverify_time_cb(int preverify_ok, X509_STORE_CTX *x509_ctx)
{
    if (preverify_ok == 0) {
        switch (X509_STORE_CTX_get_error(x509_ctx)) {
        case X509_V_ERR_CERT_HAS_EXPIRED:
        case X509_V_ERR_CERT_NOT_YET_VALID:
            /* ignore expired certificate error */
            return 1;
        }
    }
    return preverify_ok;
}

static int connect_lua(lua_State *L)
{
    tls_client_t *c        = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    lua_Integer fdarg      = lauxh_checkinteger(L, 2);
    size_t len             = 0;
    const char *servername = luaL_optlstring(L, 3, NULL, &len);
    int noverify_name      = lauxh_optboolean(L, 4, 0);
    int noverify_time      = lauxh_optboolean(L, 5, 0);
    int noverify_cert      = lauxh_optboolean(L, 6, 0);
    int use_bio            = lauxh_optboolean(L, 7, 0);
    lua_Integer bufcap     = lauxh_optinteger(L, 8, 0);
    int fd                 = 0;
    tls_ctx_t *ctx         = NULL;
    union {
        struct in_addr ip4;
        struct in6_addr ip6;
    } addr             = {0};
    // Decide once whether the caller-supplied servername is a numeric IP
    // literal.  When it is, RFC 6066 forbids sending SNI, and hostname
    // verification must use IP identity matching
    // (X509_VERIFY_PARAM_set1_ip_asc) instead of DNS matching (SSL_set1_host).
    int is_ip          = (len && (inet_pton(AF_INET, servername, &addr) == 1 ||
                                  inet_pton(AF_INET6, servername, &addr) == 1));
    const char *errop  = NULL;
    const char *errmsg = NULL;

    // narrowing an out-of-range lua_Integer to int would hand OpenSSL an
    // unrelated descriptor number; reject before any allocation
    if (fdarg < 0 || fdarg > INT_MAX) {
        lua_pushnil(L);
        errno = EINVAL;
        lua_errno_new(L, errno, "connect");
        return 2;
    }
    fd = (int)fdarg;

    ctx               = lua_newuserdata(L, sizeof(tls_ctx_t));
    ctx->handshake_cb = SSL_connect;
    ctx->parent       = c;
    ctx->ssl          = SSL_new(c->ctx);
    ctx->bio          = NULL;
    ctx->parent_ref   = LUA_NOREF;
    lauxh_setmetatable(L, NET_TLS_CONTEXT_MT);
    ctx->parent_ref = lauxh_refat(L, 1);

    if (!ctx->ssl) {
        errop  = "connect.SSL_new";
        errmsg = "failed to create SSL context";
        goto FAIL;
    }

    // The caller asked for hostname verification (noverify_name=0) but did
    // not supply an identity to verify against.  Refuse to proceed; silently
    // continuing would accept any CA-valid certificate on the peer side.
    if (!noverify_name && len == 0) {
        errop  = "connect.servername";
        errmsg = "servername is required to verify the peer certificate "
                 "identity";
        goto FAIL;
    }

    if (len) {
        if (is_ip) {
            if (!noverify_name) {
                // IP literal servername: pin the peer certificate identity to
                // the requested IP address so a CA-valid certificate issued for
                // a different endpoint is still rejected.
                X509_VERIFY_PARAM *param = SSL_get0_param(ctx->ssl);
                if (X509_VERIFY_PARAM_set1_ip_asc(param, servername) != 1) {
                    errop  = "connect.X509_VERIFY_PARAM_set1_ip_asc";
                    errmsg = "failed to set IP address for verification";
                    goto FAIL;
                }
            }
        } else if (SSL_set_tlsext_host_name(ctx->ssl, servername) != 1) {
            // DNS servername: enable SNI and hostname verification.
            errop  = "connect.SSL_set_tlsext_host_name";
            errmsg = "failed to set server name indication (SNI)";
            goto FAIL;
        } else if (!noverify_name && SSL_set1_host(ctx->ssl, servername) != 1) {
            errop  = "connect.SSL_set1_host";
            errmsg = "failed to set hostname for verification";
            goto FAIL;
        }
    }

    if (noverify_cert) {
        // ignore server certificate error
        SSL_set_verify(ctx->ssl, SSL_VERIFY_NONE, NULL);
    } else if (noverify_time) {
        // ignore server certificate expired error by callback
        SSL_set_verify(ctx->ssl, SSL_VERIFY_PEER, noverify_time_cb);
    } else {
        // verify server certificate
        SSL_set_verify(ctx->ssl, SSL_VERIFY_PEER, NULL);
    }

    if (use_bio) {
        size_t cap = get_bio_bufcap(ctx->ssl, bufcap);
        if (!(ctx->bio = tls_bio_new(L, fd, cap))) {
            errop  = "connect.tls_bio_new";
            errmsg = "failed to create tls_bio for SSL context";
        } else if (tls_bio_setup(ctx->ssl, ctx->bio) != 0) {
            errop  = "connect.tls_bio_setup";
            errmsg = "failed to set up BIOs for SSL context";
        } else {
            // successfully set up BIOs; ready for handshake
            return 1;
        }
    } else if (SSL_set_fd(ctx->ssl, fd) != 1) {
        errop  = "connect.SSL_set_fd";
        errmsg = "failed to set file descriptor";
        goto FAIL;
    } else {
        // successfully set fd for SSL; ready for handshake
        return 1;
    }

FAIL:
    cleanup_context(L, ctx);
    lua_pushnil(L);
    tls_push_error(L, errop, errmsg);
    return 2;
}

LUALIB_API int luaopen_net_tls_context(lua_State *L)
{
    struct luaL_Reg mmethod[] = {
        {"__gc",       gc_lua      },
        {"__tostring", tostring_lua},
        {NULL,         NULL        }
    };
    struct luaL_Reg method[] = {
        {"get_alpn",          get_alpn_lua         },
        {"get_version",       get_version_lua      },
        {"get_cipher",        get_cipher_lua       },
        {"get_peer_cert",     get_peer_cert_lua    },
        {"get_verify_result", get_verify_result_lua},
        {"get_bio",           get_bio_lua          },
        {"read",              read_lua             },
        {"write",             write_lua            },
        {"close",             close_lua            },
        {"shutdown",          shutdown_lua         },
        {"handshake",         handshake_lua        },
        {NULL,                NULL                 }
    };

    luaL_newmetatable(L, NET_TLS_CONTEXT_MT);
    for (struct luaL_Reg *ptr = mmethod; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    lua_newtable(L);
    for (struct luaL_Reg *ptr = method; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    lua_errno_loadlib(L);
    tls_init(L);
    tls_bio_init(L);

    lua_createtable(L, 0, 5);
    lauxh_pushfn2tbl(L, "accept", accept_lua);
    lauxh_pushfn2tbl(L, "connect", connect_lua);
    lauxh_pushfn2tbl(L, "encrypted_length", encrypted_length_lua);
    /* keep constants for backward compatibility with lib/tls.lua */
    lauxh_pushint2tbl(L, "WANT_READ", SSL_ERROR_WANT_READ);
    lauxh_pushint2tbl(L, "WANT_WRITE", SSL_ERROR_WANT_WRITE);
    return 1;
}
