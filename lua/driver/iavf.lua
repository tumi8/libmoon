--- iavf-specific code
local dev = {}

local ffi   = require "ffi"
local dpdkc = require "dpdkc"

dev.timeRegisters = {0, 0, 0, 0}
function dev:enableRxTimestamps(self, udpPort) end
function dev:enableTxTimestamps(queue) end
function dev:hasRxTimestamp() return 1 end
-- not needed(?) but avoids some log spam
function dev:getTxTimestamp(self, wait) return 0 end
function dev:resetTimeCounters() return 1 end

return dev