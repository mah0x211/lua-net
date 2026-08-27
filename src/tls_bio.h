/**
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

#ifndef net_tls_bio_h
#define net_tls_bio_h

#include <openssl/err.h>
#include <openssl/ssl.h>
#include <openssl/x509_vfy.h>
#include <openssl/x509v3.h>
// lua
#include "lauxhlib.h"

// local
#include "zring.h"

#define NET_TLS_BIO_MT "net.tls.bio"

/**
 * @brief Internal ring-buffer object managed as a Lua full userdata.
 *
 * One instance is allocated for the receive path (rxbuf) and one for the
 * transmit path (txbuf) of every TLS context.  The tls_ctx_t owns both via
 * raw C pointers; @c ref keeps the userdata reachable in the Lua registry so
 * that the Lua GC does not collect it while the context is still alive.
 */
typedef struct {
    zring_t buf;  /**< Ring buffer operating over @c mem->data. */
    BUF_MEM *mem; /**< OpenSSL-managed backing memory (NULL after free). */
    int rx_eof;   /**< Receive path only: read(2) reported EOF. */
} tls_bio_buf_t;

typedef struct {
    int ref;               /**< prevent premature GC. */
    int fd;                /**< network socket file descriptor. */
    BIO_METHOD *rx_method; /**< receive BIO_METHOD owned by this instance. */
    BIO_METHOD *tx_method; /**< transmit BIO_METHOD owned by this instance. */
    tls_bio_buf_t rx;      /**< receive ring buffer */
    tls_bio_buf_t tx;      /**< transmit ring buffer */
} tls_bio_t;

/**
 * @brief Register the NET_TLS_BIO_MT metatable for the BIO userdata.
 *
 * Must be called once (e.g. from luaopen) before any tls_bio_new() call.
 * The per-connection BIO_METHOD objects are created by tls_bio_new() and
 * require no module-level initialisation.
 *
 * @param L Lua state, used to register the BIO userdata metatable.
 */
void tls_bio_init(lua_State *L);

/**
 * @brief Wires custom memory BIOs to @p ssl using @p bio's rx and tx buffers.
 *
 * @param ssl An SSL object to attach the BIOs to.
 * @param bio BIO object containing both receive and transmit ring buffers.
 * @return    0 on success, -1 on failure.
 */
int tls_bio_setup(SSL *ssl, tls_bio_t *bio);

/**
 * @brief Allocate a tls_bio_t full userdata with the given capacity for both
 * receive and transmit buffers.
 *
 * @param L   Lua state, used to allocate the userdata and register the
 *            metatable.
 * @param fd  Network socket file descriptor.
 * @param cap Capacity in bytes for both rx and tx buffers; must be > 0.  An
 *            unallocatable capacity yields NULL.
 * @return    Pointer to the allocated tls_bio_t on success, or NULL on failure.
 */
tls_bio_t *tls_bio_new(lua_State *L, int fd, size_t cap);

/**
 * @brief Free the BIO's associated buffers and release the Lua registry
 * reference.
 *
 * @param L   Lua state, used to free the registry reference.
 * @param bio BIO to free; may be NULL.
 */
void tls_bio_free(lua_State *L, tls_bio_t *bio);

/**
 * @brief Return the number of bytes of ciphertext data currently stored in the
 * transmit buffer, i.e. the amount of data waiting to be written to the
 * network.
 *
 * @param bio BIO containing the transmit buffer to query.
 * @return    Number of bytes of data currently stored in the transmit buffer.
 */
static inline size_t tls_bio_tx_size(tls_bio_t *bio)
{
    return zring_data_size(&bio->tx.buf);
}

/**
 * @brief Return the number of bytes of ciphertext data currently stored in
 * the receive buffer, i.e. the amount of data read from the network but not
 * yet consumed by OpenSSL.
 *
 * @param bio BIO containing the receive buffer to query.
 * @return    Number of bytes of data currently stored in the receive buffer.
 */
static inline size_t tls_bio_rx_size(tls_bio_t *bio)
{
    return zring_data_size(&bio->rx.buf);
}

#endif /* net_tls_bio_h */
