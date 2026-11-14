local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local fileno = require('io.fileno')
local socket = require('net.socket')

local SOCKS, FILES, PATHS

function testcase.before_each()
    FILES, PATHS = {}, {}
    SOCKS = assert(socket.pair({socktype = 'stream'}))
end

function testcase.after_each()
    for _, file in ipairs(FILES) do
        file:close()
    end
    for _, sock in ipairs(SOCKS) do
        sock:close()
    end
    for _, path in ipairs(PATHS) do
        os.remove(path)
    end
end

local function new_file(contents, mode)
    local path = os.tmpname()
    PATHS[#PATHS + 1] = path
    local file = assert(io.open(path, mode))
    FILES[#FILES + 1] = file
    assert(file:write(contents))
    assert(file:flush())
    return file
end

function testcase.sendfile_rejects_write_only_input_when_reading()
    local file = new_file('abc', 'w')
    for _, offset in ipairs({0, 2}) do
        for _, input in ipairs({file, fileno(file)}) do
            local sent, err, again = SOCKS[1]:sendfile(input, 1, offset)
            assert.is_nil(sent)
            assert(err)
            assert.equal(err.type, errno.EBADF)
            assert.is_nil(again)
        end
    end
end

function testcase.sendfile_rejects_closed_output_at_eof()
    local file = new_file('', 'w+')
    assert(SOCKS[1]:close())
    for _, offset in ipairs({0, 7}) do
        local sent, err, again = SOCKS[1]:sendfile(file, 1, offset)
        assert.is_nil(sent)
        assert(err)
        assert.equal(err.type, errno.EBADF)
        assert.is_nil(again)
    end
end

function testcase.sendfile_readable_empty_input_is_eof()
    local file = new_file('', 'w+')
    for _, offset in ipairs({0, 7}) do
        local sent, err, again = SOCKS[1]:sendfile(file, 1, offset)
        assert.equal(sent, 0)
        assert.is_nil(err)
        assert.is_nil(again)
    end
end
