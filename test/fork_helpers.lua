local xpcall = require('testcase.xpcall')
local exit = require('testcase.exit').exit

-- The runner exits forked processes successfully even after an assertion
-- fails. Report the result explicitly before control returns to it.
return function(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        io.stderr:write(tostring(err), '\n')
    end
    exit(ok and 0 or 1)
end
