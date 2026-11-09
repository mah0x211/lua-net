local assert = require('assert')
local execvp = require('exec').execvp
local socket = require('net.socket')
local wait = require('io.wait')
local sleep = require('testcase.timer').sleep
local tls_context = require('net.tls.context')
local tls_server = require('net.tls.server')
local tls_client = require('net.tls.client')
local context_helpers = require('test.tls.context.helpers')
local new_ep = context_helpers.new_ep
local handshake = context_helpers.handshake

-- Process and fixture ownership is separate for each test file.
local function new()
    local PROCESSES = {}
    local TICKET_SESSION = os.tmpname()
    local TICKET_TRACE = os.tmpname()

    local function exec(...)
        local proc, err = execvp(...)
        if proc then
            PROCESSES[#PROCESSES + 1] = proc
        end
        return proc, err
    end

    local fixtures = require('test.tls.context.fixtures').new(exec)
    local get_server_config = fixtures.get_server_config
    local get_crl_fixture_pem = fixtures.get_crl_fixture_pem
    local get_chain_fixture_dir = fixtures.get_chain_fixture_dir
    local get_client_cert_fixture_dir = fixtures.get_client_cert_fixture_dir
    local get_verify_fixture_dir = fixtures.get_verify_fixture_dir

    local function new_tls_server(cert, key, protocol, cipher, alpn,
                                  session_timeout, prefer_client_ciphers)
        return tls_server({
            cert = cert,
            key = key,
            protocol = protocol,
            cipher = cipher,
            alpn = alpn,
            session_timeout = session_timeout,
            prefer_client_ciphers = prefer_client_ciphers,
        })
    end

    local function new_tls_client(protocol, cipher, alpn)
        return tls_client({
            protocol = protocol,
            cipher = cipher,
            alpn = alpn,
        })
    end

    local function free_port()
        local s = assert(socket.bind_inet('127.0.0.1', 0, {
            socktype = 'stream',
            protocol = 'tcp',
            reuseaddr = true,
            reuseport = true,
        }))
        local port = assert(s:getsockname()):port()
        s:close()
        return port
    end

    local function start_s_server(port, alpn, ciphersuites)
        local args = {
            's_server',
            '-accept',
            '127.0.0.1:' .. tostring(port),
            '-cert',
            get_server_config().cert,
            '-key',
            get_server_config().key,
            '-quiet',
            '-naccept',
            '1',
        }
        if alpn then
            args[#args + 1] = '-alpn'
            args[#args + 1] = alpn
        end
        if ciphersuites then
            args[#args + 1] = '-tls1_3'
            args[#args + 1] = '-ciphersuites'
            args[#args + 1] = ciphersuites
        end
        return exec('openssl', args)
    end

    local function start_ticket_s_server(port, protocol, extra_args)
        local args = {
            's_server',
            '-accept',
            '127.0.0.1:' .. tostring(port),
            '-cert',
            get_server_config().cert,
            '-key',
            get_server_config().key,
            '-quiet',
            '-state',
            '-naccept',
            '2',
            protocol == 'tlsv1.2' and '-tls1_2' or '-tls1_3',
        }
        for _, arg in ipairs(extra_args or {}) do
            args[#args + 1] = arg
        end
        return exec('openssl', args)
    end

    local function start_s_client(port, alpn, ciphersuites)
        local args = {
            's_client',
            '-connect',
            '127.0.0.1:' .. tostring(port),
            '-quiet',
            '-noservername',
        }
        if alpn then
            args[#args + 1] = '-alpn'
            args[#args + 1] = alpn
        end
        if ciphersuites then
            args[#args + 1] = '-tls1_3'
            args[#args + 1] = '-ciphersuites'
            args[#args + 1] = ciphersuites
        end
        return exec('openssl', args)
    end

    local function start_s_client_tls12_cipher(port, cipher)
        return exec('openssl', {
            's_client',
            '-connect',
            '127.0.0.1:' .. tostring(port),
            '-quiet',
            '-noservername',
            '-tls1_2',
            '-cipher',
            cipher,
        })
    end

    local function start_s_client_with_ca(port, cafile)
        return exec('openssl', {
            's_client',
            '-connect',
            '127.0.0.1:' .. tostring(port),
            '-quiet',
            '-noservername',
            '-CAfile',
            cafile,
            '-verify_return_error',
        })
    end

    local function start_s_client_with_cert(port, cert, key)
        return exec('openssl', {
            's_client',
            '-connect',
            '127.0.0.1:' .. tostring(port),
            '-quiet',
            '-noservername',
            '-cert',
            cert,
            '-key',
            key,
        })
    end

    local function start_s_client_sni(port, servername, cert, key)
        local args = {
            's_client',
            '-connect',
            '127.0.0.1:' .. tostring(port),
            '-quiet',
            '-servername',
            servername,
        }
        if cert then
            args[#args + 1] = '-cert'
            args[#args + 1] = cert
            args[#args + 1] = '-key'
            args[#args + 1] = key
        end
        return exec('openssl', args)
    end

    local function wait_listen(port)
        for _ = 1, 200 do
            local sock, err, again = socket.connect_inet('127.0.0.1', port, {
                socktype = 'stream',
                protocol = 'tcp',
            })
            if sock then
                if again then
                    local ok = wait.writable(sock:fd(), 0.05)
                    if ok and not sock:error() then
                        return sock
                    end
                    sock:close()
                else
                    return sock
                end
            end
            _ = err
            -- ECONNREFUSED: server not ready yet; back off and retry
            sleep(0.05)
        end
        return nil, 's_server did not start listening on port ' .. tostring(port)
    end

    local function start_s_server_cert(port, cert, key)
        return exec('openssl', {
            's_server',
            '-accept',
            '127.0.0.1:' .. tostring(port),
            '-cert',
            cert,
            '-key',
            key,
            '-quiet',
            '-naccept',
            '1',
        })
    end

    local function connect_verifying_client(port, servername, verify_name,
                                            verify_time, verify_cert)
        local csock, cerr = wait_listen(port)
        if not csock then
            return nil, cerr
        end
        local fd = csock:fd()

        local client, err = tls_client({
            cafile = get_verify_fixture_dir() .. '/trusted-ca.crt',
        })
        if not client then
            csock:close()
            return nil, err
        end
        local ctx
        ctx, err = tls_context.connect(client, fd, {
            servername = servername,
            verify_name = verify_name,
            verify_time = verify_time,
            verify_cert = verify_cert,
        })
        if not ctx then
            csock:close()
            return nil, err
        end

        local ep = new_ep(ctx, 'client', fd, csock)
        local hok
        hok, err = handshake(ep)
        if not hok then
            local _, verify_error = ctx:get_verify_result()
            ep.ctx:close()
            csock:close()
            return nil, err, verify_error
        end
        return ep
    end

    local function after_each()
        for i = #PROCESSES, 1, -1 do
            local proc = PROCESSES[i]
            if proc.pid > 0 then
                proc:close(0.1)
            end
            PROCESSES[i] = nil
        end
    end

    local function after_all()
        after_each()
        os.remove(TICKET_SESSION)
        os.remove(TICKET_TRACE)
        fixtures.close()
    end

    return {
        exec = exec,
        new_tls_server = new_tls_server,
        new_tls_client = new_tls_client,
        free_port = free_port,
        start_s_server = start_s_server,
        start_ticket_s_server = start_ticket_s_server,
        start_s_client = start_s_client,
        start_s_client_tls12_cipher = start_s_client_tls12_cipher,
        start_s_client_with_ca = start_s_client_with_ca,
        start_s_client_with_cert = start_s_client_with_cert,
        start_s_client_sni = start_s_client_sni,
        wait_listen = wait_listen,
        start_s_server_cert = start_s_server_cert,
        connect_verifying_client = connect_verifying_client,
        get_server_config = get_server_config,
        get_crl_fixture_pem = get_crl_fixture_pem,
        get_chain_fixture_dir = get_chain_fixture_dir,
        get_client_cert_fixture_dir = get_client_cert_fixture_dir,
        get_verify_fixture_dir = get_verify_fixture_dir,
        TICKET_SESSION = TICKET_SESSION,
        TICKET_TRACE = TICKET_TRACE,
        ticket_connection = context_helpers.new_ticket_connection(TICKET_TRACE),
        after_each = after_each,
        after_all = after_all,
    }

end

return { new = new }
