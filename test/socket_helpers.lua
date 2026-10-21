local assert = require('assert')
local device = require('net.device')

-- find the loopback interface name; used to prove that an embedded NUL
-- used to redirect an operation to the prefix interface
local function loopback_ifname()
    local ifs = assert(device.getifaddrs())
    for name, info in pairs(ifs) do
        if info.loopback then
            return name
        end
    end
end

return {
    loopback_ifname = loopback_ifname,
}
