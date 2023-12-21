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
 */

#include "tls.h"

// set callback for ALPN (Application-Layer Protocol Negotiation) support
// SSL_CTX_set_alpn_select_cb(ctx->sslctx, alpn_select_cb, ctx);
// set callback for NPN (Next Protocol Negotiation) support
// SSL_CTX_set_next_protos_advertised_cb(ctx->sslctx, npn_advertise_cb, ctx);

static int set_crls(lua_State *L)
{
    tls_client_t *c          = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    size_t len               = 0;
    const char *crls         = luaL_checkstring(L, 2);
    X509_STORE *store        = SSL_CTX_get_cert_store(c->ctx);
    BIO *bio                 = BIO_new_mem_buf((void *)crls, len);
    STACK_OF(X509_INFO) *inf = NULL;
    const char *errop        = NULL;
    const char *errmsg       = NULL;

    if (!bio) {
        errop  = "BIO_new_mem_buf";
        errmsg = "failed to create BIO";
        goto FAIL;
    }

    // read CRLs from PEM format
    inf = PEM_X509_INFO_read_bio(bio, NULL, NULL, NULL);
    if (!inf) {
        errop  = "PEM_X509_INFO_read_bio";
        errmsg = "failed to read CRLs";
        goto FAIL;
    }

    // add CRLs to the store
    for (int i = 0; i < sk_X509_INFO_num(inf); i++) {
        X509_INFO *it = sk_X509_INFO_value(inf, i);
        if (!it->crl) {
            continue;
        } else if (X509_STORE_add_crl(store, it->crl) != 1) {
            errop  = "X509_STORE_add_crl";
            errmsg = "failed to add CRL";
            goto FAIL;
        }
    }

    // enable CRL checking for the entire certificate chain and also enable CRL
    // checking for leaf certificate
    if (X509_STORE_set_flags(store, X509_V_FLAG_CRL_CHECK |
                                        X509_V_FLAG_CRL_CHECK_ALL) != 1) {
        errop  = "X509_STORE_set_flags";
        errmsg = "failed to set CRL flags";
        goto FAIL;
    }

    sk_X509_INFO_pop_free(inf, X509_INFO_free);
    BIO_free(bio);
    lua_pushboolean(L, 1);
    return 1;

FAIL:
    if (inf) {
        sk_X509_INFO_pop_free(inf, X509_INFO_free);
    }
    if (bio) {
        BIO_free(bio);
    }
    lua_pushboolean(L, 0);
    tls_push_error(L, errop, errmsg);
    return 2;
}

static int load_verify_locations(lua_State *L)
{
    tls_client_t *c    = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    const char *cafile = luaL_checkstring(L, 2);
    const char *capath = luaL_checkstring(L, 3);

    if (SSL_CTX_load_verify_locations(c->ctx, cafile, capath) != 1) {
        lua_pushboolean(L, 0);
        tls_push_error(L, "SSL_CTX_load_verify_locations",
                       "failed to load verify locations");
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int set_verify_depth_lua(lua_State *L)
{
    tls_client_t *c = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    int depth       = lauxh_checkuinteger(L, 2);
    SSL_CTX_set_verify_depth(c->ctx, depth);
    return 0;
}

static int tostring_lua(lua_State *L)
{
    lua_pushfstring(L, NET_TLS_CLIENT_MT ": %p", lua_touserdata(L, 1));
    return 1;
}

static int gc_lua(lua_State *L)
{
    tls_client_t *c = luaL_checkudata(L, 1, NET_TLS_CLIENT_MT);
    SSL_CTX_free(c->ctx);
    lauxh_unref(L, c->error_cb_ref);
    return 0;
}

typedef struct {
    SSL *ssl;
    X509_STORE *store;
    X509 *cert;
    STACK_OF(X509) * chain;
    OCSP_CERTID *certid;
    OCSP_RESPONSE *resp;
    OCSP_BASICRESP *basic;
    int status;
    int reason;
    ASN1_GENERALIZEDTIME *revtime;
    ASN1_GENERALIZEDTIME *thisupd;
    ASN1_GENERALIZEDTIME *nextupd;
    const char *errop;
    const char *errmsg;
} ocsp_verify_ctx_t;

static int check_ocsp_response(ocsp_verify_ctx_t *ctx)
{
    const long jitter = 60;
    const long maxage = 14 * 24 * 60 * 60;
    int status        = OCSP_response_status(ctx->resp);

    if (status != OCSP_RESPONSE_STATUS_SUCCESSFUL) {
        ctx->errop = "OCSP_response_status";

        switch (status) {
        case OCSP_RESPONSE_STATUS_MALFORMEDREQUEST:
            ctx->errmsg = "invalid OCSP status: "
                          "OCSP_RESPONSE_STATUS_MALFORMEDREQUEST";
            break;

        case OCSP_RESPONSE_STATUS_INTERNALERROR:
            ctx->errmsg = "invalid OCSP status: "
                          "OCSP_RESPONSE_STATUS_INTERNALERROR";
            break;
        case OCSP_RESPONSE_STATUS_TRYLATER:
            ctx->errmsg = "invalid OCSP status: "
                          "OCSP_RESPONSE_STATUS_TRYLATER";
            break;
        case OCSP_RESPONSE_STATUS_SIGREQUIRED:
            ctx->errmsg = "invalid OCSP status: "
                          "OCSP_RESPONSE_STATUS_SIGREQUIRED";
            break;
        case OCSP_RESPONSE_STATUS_UNAUTHORIZED:
            ctx->errmsg = "invalid OCSP status: "
                          "OCSP_RESPONSE_STATUS_UNAUTHORIZED";
            break;
        default:
            ctx->errmsg = "invalid OCSP status: "
                          "unsupported OCSP response status";
        }
        return -1;
    }

    ctx->basic = OCSP_response_get1_basic(ctx->resp);
    if (!ctx->basic) {
        ctx->errop  = "OCSP_response_get1_basic";
        ctx->errmsg = "failed to decode OCSP response";
        return -1;
    } else if (OCSP_basic_verify(ctx->basic, ctx->chain, ctx->store, 0) != 1) {
        ctx->errop  = "OCSP_basic_verify";
        ctx->errmsg = "failed to verify OCSP basic response";
        return -1;
    }

    if (OCSP_resp_find_status(ctx->basic, ctx->certid, &ctx->status,
                              &ctx->reason, &ctx->revtime, &ctx->thisupd,
                              &ctx->nextupd) != 1) {
        ctx->errop  = "OCSP_resp_find_status";
        ctx->errmsg = "failed to find status";
        return -1;
    }

    if (OCSP_check_validity(ctx->thisupd, ctx->nextupd, jitter, maxage) != 1) {
        ctx->errop  = "OCSP_check_validity";
        ctx->errmsg = "ocsp response not current";
        return -1;
    }

    return 0;
}

static int verify_ocsp_response(ocsp_verify_ctx_t *ctx, SSL *ssl)
{
    const unsigned char *raw = NULL;
    int size                 = SSL_get_tlsext_status_ocsp_resp(ssl, &raw);

    ctx->ssl = ssl;
    if (size <= 0) {
        // server did not provide OCSP response
        return 1;
    }

    ctx->resp = d2i_OCSP_RESPONSE(NULL, &raw, size);
    if (!ctx->resp) {
        ctx->errop  = "d2i_OCSP_RESPONSE";
        ctx->errmsg = "failed to decode OCSP response";
        return -1;
    }

    ctx->store = SSL_CTX_get_cert_store(SSL_get_SSL_CTX(ssl));
    ctx->cert  = SSL_get_peer_certificate(ssl);
    if (!ctx->cert) {
        ctx->errop  = "SSL_get_peer_certificate";
        ctx->errmsg = "failed to get peer certificate";
        return -1;
    }

    ctx->chain = SSL_get_peer_cert_chain(ssl);
    if (!ctx->chain) {
        ctx->errop  = "SSL_get_peer_cert_chain";
        ctx->errmsg = "failed to get peer certificate chain";
        return -1;
    }

    for (int i = 0; i < sk_X509_num(ctx->chain); i++) {
        X509 *issuer = sk_X509_value(ctx->chain, i);
        if (X509_check_issued(issuer, ctx->cert) == X509_V_OK) {
            ctx->certid = OCSP_cert_to_id(EVP_sha1(), ctx->cert, issuer);
            if (!ctx->certid) {
                int err     = ERR_get_error();
                ctx->errop  = "OCSP_cert_to_id";
                ctx->errmsg = ERR_error_string(err, NULL);
                return -1;
            }
            return check_ocsp_response(ctx);
        }
    }
    ctx->errop  = "X509_check_issued";
    ctx->errmsg = "failed to find issuer certificate";
    return -1;
}

static void print_error(tls_client_t *c, const char *op, const char *errmsg)
{
    if (c->error_cb_ref != LUA_NOREF) {
        lauxh_pushref(c->L, c->error_cb_ref);
        lua_pushstring(c->L, op);
        lua_pushstring(c->L, errmsg);
        if (lua_pcall(c->L, 2, 0, 0) == 0) {
            // succeeded to call error callback
            return;
        }
        // ouput error of error callback
        fprintf(stderr, "failed to call error callback: %s\n",
                lua_tostring(c->L, -1));
    }
    // output error to stderr
    fprintf(stderr, "%s: %s\n", op, errmsg);
}

// TLS handshake verification callback for stapled requests
static int ocsp_verify_cb(SSL *ssl, void *arg)
{
    tls_client_t *c       = SSL_get_app_data(ssl);
    ocsp_verify_ctx_t ctx = {0};
    int rc                = verify_ocsp_response(&ctx, ssl);

    if (rc == 0) {
        switch (ctx.status) {
        case V_OCSP_CERTSTATUS_GOOD:
            rc = 1;
            break;
        case V_OCSP_CERTSTATUS_REVOKED:
            rc = 0;
            break;
        default:
            ctx.errop  = "OCSP_resp_find_status";
            ctx.errmsg = "unknown OCSP response status";
            rc         = -1;
        }
    }

    if (ctx.errmsg) {
        print_error(c, ctx.errop, ctx.errmsg);
    }
    if (ctx.certid) {
        OCSP_CERTID_free(ctx.certid);
    }
    if (ctx.basic) {
        OCSP_BASICRESP_free(ctx.basic);
    }
    if (ctx.resp) {
        OCSP_RESPONSE_free(ctx.resp);
    }

    return rc;
}

static int new_lua(lua_State *L)
{
    int narg          = lua_gettop(L);
    int protocol      = luaL_checkoption(L, 1, "default", TLS_PROTOCOLS);
    int cipher        = luaL_checkoption(L, 2, "default", TLS_CIPHER_SUITES);
    int cache_timeout = lauxh_optinteger(L, 3, 0);
    int cache_size = lauxh_optinteger(L, 4, SSL_SESSION_CACHE_MAX_SIZE_DEFAULT);
    int prefer_client_ciphers = lauxh_optboolean(L, 5, 0);
    tls_client_t *c           = NULL;
    const char *errop         = NULL;
    const char *errmsg        = NULL;

    // check error function
    if (narg >= 6 && !lua_isnoneornil(L, 6)) {
        luaL_checktype(L, 6, LUA_TFUNCTION);
        lua_settop(L, 6);
    }

    // create context
    c               = lua_newuserdata(L, sizeof(tls_client_t));
    c->L            = L;
    c->error_cb_ref = LUA_NOREF;
    c->ctx          = SSL_CTX_new(TLS_client_method());
    if (!c->ctx) {
        errop  = "SSL_CTX_new";
        errmsg = "failed to create SSL_CTX";
        goto FAIL;
    }

    // set mode
    SSL_CTX_clear_mode(c->ctx, SSL_MODE_AUTO_RETRY);
    SSL_CTX_set_mode(c->ctx, SSL_MODE_ENABLE_PARTIAL_WRITE);
    SSL_CTX_set_mode(c->ctx, SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);

    // set protocols
    if (tls_set_protocol_vers(c->ctx, protocol) != 1) {
        errop  = "tls_set_protocol_vers";
        errmsg = "failed to set protocol version";
        goto FAIL;
    }

    // set cipher suite
    if (tls_set_cipher_suite(c->ctx, cipher) != 1) {
        errop  = "tls_set_cipher_suite";
        errmsg = "failed to set cipher suite";
        goto FAIL;
    }

    // session settings
    if (cache_timeout <= 0) {
        // disable session cache and session tickets
        SSL_CTX_set_session_cache_mode(c->ctx, SSL_SESS_CACHE_OFF);
        SSL_CTX_set_options(c->ctx, SSL_OP_NO_TICKET);
        SSL_CTX_set_num_tickets(c->ctx, 0);
    } else {
        // enable session cache
        SSL_CTX_set_session_cache_mode(c->ctx, SSL_SESS_CACHE_CLIENT);
        SSL_CTX_set_timeout(c->ctx, cache_timeout);
        if (cache_size > 0) {
            SSL_CTX_sess_set_cache_size(c->ctx, cache_size);
        }
        SSL_CTX_set_num_tickets(c->ctx, 2);
    }

    // prefer client cipher suites over server cipher suites
    if (prefer_client_ciphers != 1) {
        SSL_CTX_set_options(c->ctx, SSL_OP_CIPHER_SERVER_PREFERENCE);
    }

    // set default verify certificate locations
    if (SSL_CTX_set_default_verify_paths(c->ctx) != 1) {
        errop  = "SSL_CTX_set_default_verify_paths";
        errmsg = "failed to set default verify paths";
        goto FAIL;
    }

    // set default OCSP callback
    if (SSL_CTX_set_tlsext_status_type(c->ctx, TLSEXT_STATUSTYPE_ocsp) != 1 ||
        SSL_CTX_set_tlsext_status_cb(c->ctx, ocsp_verify_cb) != 1) {
        errop  = "SSL_CTX_set_tlsext_status_cb";
        errmsg = "failed to set default OCSP callback";
        goto FAIL;
    }

    // keep error function reference
    if (narg >= 6) {
        c->error_cb_ref = lauxh_refat(L, 6);
    }

    // return net.tls.client userdata
    lauxh_setmetatable(L, NET_TLS_CLIENT_MT);
    return 1;

FAIL:
    if (c->ctx) {
        SSL_CTX_free(c->ctx);
    }
    lua_pushnil(L);
    tls_push_error(L, errop, errmsg);
    return 2;
}

LUALIB_API int luaopen_net_tls_client(lua_State *L)
{
    struct luaL_Reg mmethod[] = {
        {"__gc",       gc_lua      },
        {"__tostring", tostring_lua},
        {NULL,         NULL        }
    };
    struct luaL_Reg method[] = {
        {"set_verify_depth",      set_verify_depth_lua },
        {"load_verify_locations", load_verify_locations},
        {"set_crls",              set_crls             },
        {NULL,                    NULL                 }
    };

    luaL_newmetatable(L, NET_TLS_CLIENT_MT);
    for (struct luaL_Reg *ptr = mmethod; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    lua_newtable(L);
    for (struct luaL_Reg *ptr = method; ptr->name; ptr++) {
        lauxh_pushfn2tbl(L, ptr->name, ptr->func);
    }
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    // initialize
    tls_init(L);

    lua_pushcfunction(L, new_lua);
    return 1;
}
