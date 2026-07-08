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

#ifndef zring_h
#define zring_h

#include <stddef.h>

/**
 * @brief Ring buffer backed by externally-provided memory.
 *
 * Invariant: `tail == (head + count) % cap`
 *
 * The memory region pointed to by @p mem is **not owned** by this structure;
 * the caller is responsible for its lifetime.
 */
typedef struct {
    size_t cap;   /**< Capacity in bytes (fixed after initialisation). */
    size_t head;  /**< Read  position in [0, cap). */
    size_t tail;  /**< Write position in [0, cap). */
    size_t count; /**< Number of valid bytes currently stored. */
    void *mem;    /**< Externally-provided backing memory (not owned). */
} zring_t;

/**
 * @brief Initialise a ring buffer backed by @p mem of @p cap bytes.
 *
 * @p mem must remain valid for the lifetime of the ring buffer.
 *
 * @param[out] rb   Ring buffer to initialise.
 * @param[in]  mem  Backing memory region (must not be NULL, not owned).
 * @param[in]  cap  Capacity of @p mem in bytes (must be > 0).
 */
static inline void zring_init(zring_t *rb, void *mem, size_t cap)
{
    *rb = (zring_t){
        .mem   = mem,
        .cap   = cap,
        .head  = 0,
        .tail  = 0,
        .count = 0,
    };
}

/**
 * @brief Return the size of the contiguous writable region.
 *
 * Computes `min(avail, contig)` where:
 * - `avail  = cap - count` (total free bytes, possibly split across two
 *                           regions)
 * - `contig = cap - tail`  (bytes writable before wrapping to the start)
 *
 * Layout when head <= tail (free space may be split in two):
 * @code
 *   [0]                                                [cap)
 *    +---------+===========+---------------------------+
 *    |  free   |   data    |  free (returned segment)  |
 *    +---------+===========+---------------------------+
 *    0        head        tail                         cap
 *
 *    avail  = cap - count = (cap - tail) + head  [two disjoint regions]
 *    contig = cap - tail                          [bytes until end-of-buffer]
 *    min(avail, contig) = contig  (avail >= contig because head >= 0)
 * @endcode
 *
 * Layout when tail < head (free space is one contiguous region):
 * @code
 *   [0]                                                [cap)
 *    +===========+---------------------------+=========+
 *    |   data    |  free (returned segment)  |  data   |
 *    +===========+---------------------------+=========+
 *    0          tail                        head      cap
 *
 *    avail  = head - tail                    [contiguous free bytes]
 *    contig = cap  - tail                    [bytes until end-of-buffer]
 *    min(avail, contig) = avail  (avail <= contig because head <= cap)
 * @endcode
 *
 * Use this to check available space without obtaining a pointer.
 * Returns the same value as the @p len set by zring_space().
 *
 * @param[in] rb  Ring buffer.
 * @return Number of contiguous writable bytes (0 if the buffer is full).
 */
static inline size_t zring_space_size(zring_t *rb)
{
    size_t avail  = rb->cap - rb->count;
    size_t contig = rb->cap - rb->tail;
    return avail < contig ? avail : contig;
}

/**
 * @brief Return the size of the contiguous readable region.
 *
 * Computes `min(count, contig)` where:
 * - `count  = rb->count`  (total stored bytes, possibly split across two
 *                          regions)
 * - `contig = cap - head` (bytes readable before wrapping to the start)
 *
 * Layout when head <= tail (data is one contiguous region):
 * @code
 *   [0]                                                [cap)
 *    +---------+===========================+-----------+
 *    |  free   |  data (returned segment)  |   free    |
 *    +---------+===========================+-----------+
 *    0        head                        tail        cap
 *
 *    count  = tail - head                 [contiguous data bytes]
 *    contig = cap  - head                 [bytes until end-of-buffer]
 *    min(count, contig) = count  (count <= contig because tail <= cap)
 * @endcode
 *
 * Layout when tail < head (data wraps; first segment ends at cap):
 * @code
 *   [0]                                                [cap)
 *    +===========+-----------+=========================+
 *    |   data    |   free    |  data (returned segment)|
 *    +===========+-----------+=========================+
 *    0          tail        head                      cap
 *
 *    count  = (cap - head) + tail         [total data: two segments]
 *    contig = cap - head                  [bytes until end-of-buffer]
 *    min(count, contig) = contig  (count >= contig because tail >= 0)
 * @endcode
 *
 * Use this to check available data without obtaining a pointer.
 * Returns the same value as the @p len set by zring_data().
 *
 * @param[in] rb  Ring buffer.
 * @return Number of contiguous readable bytes (0 if the buffer is empty).
 */
static inline size_t zring_data_size(zring_t *rb)
{
    size_t contig = rb->cap - rb->head;
    return rb->count < contig ? rb->count : contig;
}

/**
 * @brief Return a pointer to the largest contiguous writable region.
 *
 * Only a single contiguous segment is returned per call.
 * After zring_commit(), call again to obtain any remaining space that wraps
 * around to the beginning of the buffer.
 *
 * @param[in]  rb   Ring buffer.
 * @param[out] len  Set to zring_space_size(rb); 0 if the buffer is full.
 * @return Pointer to the start of the writable region, or NULL if full.
 */
static inline void *zring_space(zring_t *rb, size_t *len)
{
    *len = zring_space_size(rb);
    if (!*len) {
        return NULL;
    }
    return (char *)rb->mem + rb->tail;
}

/**
 * @brief Return a pointer to the largest contiguous readable region.
 *
 * Only a single contiguous segment is returned per call.
 * After zring_consume(), call again to obtain any remaining data that wraps
 * around to the beginning of the buffer.
 *
 * @param[in]  rb   Ring buffer.
 * @param[out] len  Set to zring_data_size(rb); 0 if the buffer is empty.
 * @return Pointer to the start of the readable region, or NULL if empty.
 */
static inline void *zring_data(zring_t *rb, size_t *len)
{
    *len = zring_data_size(rb);
    if (!*len) {
        return NULL;
    }
    return (char *)rb->mem + rb->head;
}

/**
 * @brief Mark @p n bytes as written (advance the write position).
 *
 * @p n must not exceed zring_space_size(), i.e. the contiguous writable
 * segment, not merely the total free capacity.
 *
 * @param[in,out] rb  Ring buffer.
 * @param[in]     n   Number of bytes to commit.
 * @return 0 on success, -1 if @p n exceeds zring_space_size().
 */
static inline int zring_commit(zring_t *rb, size_t n)
{
    if (n > zring_space_size(rb)) {
        return -1;
    }
    rb->count += n;
    rb->tail += n;
    if (rb->tail >= rb->cap) {
        rb->tail -= rb->cap;
    }
    return 0;
}

/**
 * @brief Mark @p n bytes as consumed (advance the read position).
 *
 * @p n must not exceed zring_data_size(), i.e. the contiguous readable
 * segment, not merely the total stored byte count.
 *
 * @param[in,out] rb  Ring buffer.
 * @param[in]     n   Number of bytes to consume.
 * @return 0 on success, -1 if @p n exceeds zring_data_size().
 */
static inline int zring_consume(zring_t *rb, size_t n)
{
    if (n > zring_data_size(rb)) {
        return -1;
    }
    rb->count -= n;
    rb->head += n;
    if (rb->head >= rb->cap) {
        rb->head -= rb->cap;
    }
    return 0;
}

#endif /* zring_h */
