--- ice-specific code
local dev = {}

local dpdkc = require "dpdkc"
local ffi   = require "ffi"
local log   = require "log"

function dev:enableRxTimestampsAllPackets()
	dpdkc.ice_init_timer(self.id)
end

function dev:enableTxTimestamps(queue)
	dpdkc.ice_init_timer(self.id)

	self.tx_prev_ts = ffi.new("uint64_t[1]")
	self.tx_prev_ts[0] = 0
	self.tx_wraparound_ctr = ffi.new("uint64_t[1]")
	self.tx_wraparound_ctr[0] = 0
end


function dev:getTxTimestamp(queue, wait)
	return tonumber(dpdkc.ice_tx_timestamps_read(self.id, 0, self.tx_prev_ts, self.tx_wraparound_ctr))
end

function dev:readTime()
	return tonumber(dpdkc.ice_read_current_timer(self.id))
end

-- yes, this card supports timestamping
-- (TODO might want to implement something here)
dev.timeRegisters = {0, 0, 0, 0}
function dev:enableRxTimestamps(self, udpPort) end
function dev:hasRxTimestamp() return 1 end

return dev
