require('luacov')
local testcase = require('testcase')
local errno = require('errno')
local poll = require('net.poll')

function testcase.after_all()
    poll.set_poller()
end

function testcase.default_poller()
    for _, v in ipairs({
        {
            -- test that pollable returns false
            func = poll.pollable,
            exp = false,
        },
        {
            -- test that waitrecv returns false
            func = poll.waitrecv,
            exp = false,
        },
        {
            -- test that unwaitrecv returns true
            func = poll.unwaitrecv,
            exp = true,
        },
        {
            -- test that waitsend returns false
            func = poll.waitsend,
            exp = false,
        },
        {
            -- test that unwaitsend returns true
            func = poll.unwaitsend,
            exp = true,
        },
        {
            -- test that unwait returns true
            func = poll.unwait,
            exp = true,
        },
        {
            -- test that readlock returns false
            func = poll.readlock,
            exp = false,
        },
        {
            -- test that readunlock returns true
            func = poll.readunlock,
            exp = true,
        },
        {
            -- test that writelock returns false
            func = poll.writelock,
            exp = false,
        },
        {
            -- test that writeunlock returns true
            func = poll.writeunlock,
            exp = true,
        },
    }) do
        assert.equal(v.func(), v.exp)
    end

    for _, v in ipairs({
        {
            -- test that waitrecv calls a hook func
            func = poll.waitrecv,
            fd = 123,
            deadline = 456,
            ctx = {
                'foo',
                'bar',
            },
            hook = function(ctx, deadline)
                assert.equal(ctx, {
                    'foo',
                    'bar',
                })
                assert.equal(deadline, 456)
                return false, 'hook recv error', true
            end,
            results = {
                ok = false,
                err = 'hook recv error',
                timeout = true,
            },
        },
        {
            -- test that waitsend calls a hook func
            func = poll.waitsend,
            fd = 456,
            deadline = 789,
            ctx = {
                'foo',
                'bar',
            },
            hook = function(ctx, deadline)
                assert.equal(ctx, {
                    'foo',
                    'bar',
                })
                assert.equal(deadline, 789)
                return false, errno.new('ENOTSUP', 'hook send error'), true
            end,
            results = {
                ok = false,
                err = 'hook send error',
                errtype = errno.ENOTSUP,
                timeout = true,
            },
        },
    }) do
        local ok, err, timeout = v.func(v.fd, v.deadline, v.hook, v.ctx)
        assert.equal(ok, v.results.ok)
        assert.equal(timeout, v.results.timeout)
        assert.match(err, v.results.err)
        assert.equal(err.type, v.results.errtype)
    end
end

function testcase.set_poller()
    local fncall = {}
    local poller = {
        pollable = function()
            fncall.pollable = (fncall.pollable or 0) + 1
            return true
        end,
        wait_readable = function()
            fncall.wait_readable = (fncall.wait_readable or 0) + 1
            return true
        end,
        wait_writable = function()
            fncall.wait_writable = (fncall.wait_writable or 0) + 1
            return true
        end,
        unwait_readable = function()
            fncall.unwait_readable = (fncall.unwait_readable or 0) + 1
            return true
        end,
        unwait_writable = function()
            fncall.unwait_writable = (fncall.unwait_writable or 0) + 1
            return true
        end,
        unwait = function()
            fncall.unwait = (fncall.unwait or 0) + 1
            return true
        end,
        read_lock = function()
            fncall.read_lock = (fncall.read_lock or 0) + 1
            return true
        end,
        read_unlock = function()
            fncall.read_unlock = (fncall.read_unlock or 0) + 1
            return true
        end,
        write_lock = function()
            fncall.write_lock = (fncall.write_lock or 0) + 1
            return true
        end,
        write_unlock = function()
            fncall.write_unlock = (fncall.write_unlock or 0) + 1
            return true
        end,
    }

    -- test that the internal poll functions was changed
    poll.set_poller(poller)
    for k, f in ipairs({
        pollable = poll.pollable,
        waitrecv = poll.waitrecv,
        unwaitrecv = poll.unwaitrecv,
        waitsend = poll.waitsend,
        unwaitsend = poll.unwaitsend,
        unwait = poll.unwait,
        readlock = poll.readlock,
        readunlock = poll.readunlock,
        writelock = poll.writelock,
        writeunlock = poll.writeunlock,
    }) do
        assert.equal(f(), true)
        assert.equal(fncall[k], 1)
    end

    -- test that throw an error with invalid argument
    local err = assert.throws(function()
        poll.set_poller({})
    end)
    assert.match(err, 'is not function')
end

