--- ice-specific code
local dev = {}

local dpdkc = require "dpdkc"
local ffi   = require "ffi"
local log   = require "log"

function dev:enableRxTimestampsAllPackets(self)
	dpdkc.ice_init_timer(self.id)
end

-- yes, this card supports timestamping
-- (TODO might want to implement something here)
dev.timeRegisters = {0, 0, 0, 0}
function dev:enableRxTimestamps(self, udpPort) end
function dev:enableTxTimestamps(queue) end
function dev:hasRxTimestamp() return 1 end
-- not needed(?) but avoids some log spam
function dev:getTxTimestamp(self, wait) return 0 end


return dev
