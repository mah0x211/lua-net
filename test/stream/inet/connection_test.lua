local support = require('test.stream.inet.helpers').new()
local testcase = require('testcase')
local assert = require('assert')
local error = require('error')
local errno = require('errno')
local errno_eai = require('errno.eai')
local inet = require('net.stream.inet')
local HOST = support.HOST
local open_pair = support.open_pair

local ACCEPTED_FD

function testcase.before_each()
    support.before_each()
end

function testcase.after_each()
    support.after_each(ACCEPTED_FD)
    ACCEPTED_FD = nil
end

function testcase.server_new()
    -- test that create new net.stream.inet.Server
    local s, _, ai = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert.match(tostring(s), '^net.stream.inet.Server: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(s:isnonblock(), 'nonblocking mode')
    assert.equal(s:family(), 'inet')
    assert.equal(s:socktype(), 'stream')
    assert.equal(s:protocol(), 'tcp')
    -- confirm that port is not 0
    ai = assert(s:getsockname())
    assert.equal(ai:addr(), HOST)
    assert.greater(ai:port(), 0)
    assert.is_true(s:reuseaddr())
    assert.is_true(s:reuseport())
    s:close()

    -- test that returns an error that nodename nor servname provided, or not known
    local _, err = inet.server.new('invalid hostname', 0)
    assert.not_nil(error.is(err, errno_eai.EAI_NONAME))
    _, err = inet.server.new(HOST, 'invalid servname')
    assert(error.is(err, errno_eai.EAI_SERVICE) or
               error.is(err, errno_eai.EAI_NONAME))

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.server.new(HOST, 0, {
            reuseaddr = 1,
        })
    end), 'reuseaddr must be boolean', false)

    assert.match(assert.throws(function()
        inet.server.new(HOST, 0, {
            reuseport = 'foo',
        })
    end), 'reuseport must be boolean', false)
end

function testcase.client_new_failover_across_resolved_addrs()
    -- Drive the failover across the resolved addresses of 'localhost':
    -- with a listener on one family only, the connect to the other
    -- family's address fails and client.new must try the remaining
    -- address instead of giving up with the first ECONNREFUSED.
    --
    -- The order in which the resolver returns the families depends on
    -- /etc/hosts, so listen on an address from the other family. Both
    -- loopback families must be available for this failover test.
    local addrinfo = require('net.addrinfo')
    local addrs = assert(addrinfo.getaddrinfo('localhost', 0, {
        socktype = 'stream',
        protocol = 'tcp',
    }))
    local first_family = assert(addrs[1]):family()
    local listen_addr
    for _, ai in ipairs(addrs) do
        if ai:family() ~= first_family then
            listen_addr = ai:addr()
            break
        end
    end
    assert(listen_addr, 'localhost must resolve to both IPv4 and IPv6')

    local s = assert(inet.server.new(listen_addr, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c, err = inet.client.new('localhost', port)
    assert(c, err)
    assert.equal(assert(c:getpeername()):addr(), listen_addr)

    c:close()
    s:close()
end

function testcase.client_new()
    local s = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    local port = assert(s:getsockname()):port()

    -- test that return client
    assert(s:listen())
    local c, err, timeout, ai = assert(inet.client.new(HOST, port, {
        deadline = 0.1,
    }))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.match(tostring(c), '^net.stream.inet.Client: ', false)
    assert.match(tostring(ai), '^net.addrinfo: ', false)
    assert(c:isnonblock(), 'c:isnonblock() is not false')
    assert.equal(c:family(), 'inet')
    assert.equal(c:socktype(), 'stream')
    assert.equal(c:protocol(), 'tcp')
    assert.equal(ai:addr(), HOST)
    assert.equal(ai:port(), port)
    local peer_addr = assert(c:getpeername())
    assert.equal(peer_addr:addr(), HOST)
    assert.equal(peer_addr:port(), port)
    c:close()
    s:close()

    -- test that returns error that refuse
    c, err, timeout = inet.client.new(HOST, port, {
        deadline = 0.1,
    })
    assert.is_nil(c)
    assert.not_nil(error.is(err, errno.ECONNREFUSED))
    assert.is_nil(timeout)

    -- test that throws an error
    assert.match(assert.throws(function()
        inet.client.new(HOST, port, {
            deadline = 'foo',
        })
    end), 'deadline must be finite number', false)
end

function testcase.client_new_does_not_modify_opts()
    -- the servername fallback used to be written back into the
    -- caller-provided opts table; the table must be left untouched
    local s = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local tlscfg = {
        verify_name = false,
        verify_time = false,
        verify_cert = false,
    }
    local opts = {
        deadline = 0.1,
        tlscfg = tlscfg,
    }
    -- tls client without an explicit servername: the fallback to the
    -- connection host must not add a servername key to opts
    local c, err = inet.client.new(HOST, port, opts)
    assert(c, err)
    c:close()
    s:close()

    assert.equal(opts, {
        deadline = 0.1,
        tlscfg = {
            verify_name = false,
            verify_time = false,
            verify_cert = false,
        },
    })
    assert.rawequal(opts.tlscfg, tlscfg)
end

function testcase.accept()
    local _, _, peer = open_pair()
    assert.match(tostring(peer), '^net.stream.inet.Socket: ', false)
end

function testcase.accept_sec_timeout()
    -- accept and acceptfd with a sec argument report the timeout
    -- indication when no connection arrives within the deadline; without
    -- the argument they keep waiting indefinitely and are not exercised
    -- here.
    local s = assert(inet.server.new(HOST, 0, {
        reuseaddr = true,
        reuseport = true,
    }))
    assert(s:listen())

    local clock = require('time.clock').gettime
    local started = clock()
    local sock, err, timeout = s:accept(nil, 0.05)
    assert.greater_or_equal(clock() - started, 0.04)
    assert.is_nil(sock)
    assert.is_nil(err)
    assert.is_true(timeout)

    started = clock()
    local fd, ferr, ftimeout = s:acceptfd(nil, 0.05)
    assert.greater_or_equal(clock() - started, 0.04)
    assert.is_nil(fd)
    assert.is_nil(ferr)
    assert.is_true(ftimeout)
    assert(s:close())
end

function testcase.accept_sec_validation()
    local s = assert(inet.server.new(HOST, 0))
    assert(s:listen())
    assert.match(assert.throws(function()
        s:accept(nil, 'foo')
    end), 'sec must be finite number')
    assert.match(assert.throws(function()
        s:acceptfd(nil, 'foo')
    end), 'sec must be finite number')
    assert(s:close())
end

function testcase.accept_within_sec_with_ai()
    -- a connection arriving within the deadline is accepted with the
    -- timeout slot staying nil, and acceptfd returns the descriptor along
    -- with the peer addrinfo when with_ai is set
    local s = assert(inet.server.new(HOST, 0))
    assert(s:listen())
    local port = assert(s:getsockname()):port()

    local c = assert(inet.client.new(HOST, port))
    local sock, err, timeout, ai = assert(s:accept(true, 1))
    assert.is_nil(err)
    assert.is_nil(timeout)
    assert.match(tostring(sock), '^net.stream.inet.Socket: ', false)
    assert.not_nil(ai)
    assert.greater(assert(ai:port()), 0)
    assert.equal(ai:addr(), HOST)
    assert.equal(ai:port(), assert(c:getsockname()):port())
    assert(sock:close())
    assert(c:close())

    local c2 = assert(inet.client.new(HOST, port))
    local fd, ferr, ftimeout, fai = assert(s:acceptfd(true, 1))
    ACCEPTED_FD = fd
    assert.is_nil(ferr)
    assert.is_nil(ftimeout)
    assert.is_int(fd)
    assert.greater_or_equal(fd, 0)
    assert.not_nil(fai)
    assert.equal(fai:addr(), HOST)
    assert.equal(fai:port(), assert(c2:getsockname()):port())
    -- the raw descriptor can be adopted back into a socket object
    local adopted = assert(inet.wrap(fd))
    ACCEPTED_FD = nil
    assert(adopted:close())
    assert(c2:close())
    assert(s:close())
end
