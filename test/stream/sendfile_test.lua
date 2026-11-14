local testcase = require('testcase')
local assert = require('assert')
local errno = require('errno')
local unix = require('net.stream.unix')

local SOCKS, FILES, PATHS

function testcase.before_each()
    FILES, PATHS = {}, {}
    SOCKS = assert(unix.pair())
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

function testcase.sendfile_rejects_false_offset_without_sending()
    local file = new_file('AB', 'w+')
    assert.throws(function()
        SOCKS[1]:sendfile(file, 1, false)
    end)
    local data, err, again = SOCKS[2].sock:recv(1)
    assert.is_nil(data)
    assert.is_nil(err)
    assert.is_true(again)
end

function testcase.sendfile_optional_and_integer_offsets()
    local file = new_file('AB', 'w+')
    for i = 1, 3 do
        local sent, err, timeout
        if i == 1 then
            sent, err, timeout = SOCKS[1]:sendfile(file, 1)
        elseif i == 2 then
            sent, err, timeout = SOCKS[1]:sendfile(file, 1, nil)
        else
            sent, err, timeout = SOCKS[1]:sendfile(file, 1, 1)
        end
        assert.equal(sent, 1)
        assert.is_nil(err)
        assert.is_nil(timeout)
        assert.equal(SOCKS[2]:recv(1), i == 3 and 'B' or 'A')
    end
end

function testcase.sendfile_reports_write_only_input_error_when_reading()
    local file = new_file('abc', 'w')
    local sent, err, timeout = SOCKS[1]:sendfile(file, 1, 0)
    assert.equal(sent, 0)
    assert(err)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
end

function testcase.sendfile_reports_closed_output_error_at_eof()
    local file = new_file('', 'w+')
    assert(SOCKS[1]:close())
    local sent, err, timeout = SOCKS[1]:sendfile(file, 1, 0)
    assert.equal(sent, 0)
    assert(err)
    assert.equal(err.type, errno.EBADF)
    assert.is_nil(timeout)
end
