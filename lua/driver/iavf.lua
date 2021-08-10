--- iavf-specific code
local dev = {}

local ffi   = require "ffi"
local dpdkc = require "dpdkc"
local eth   = require "proto.ethernet"

dev.supportsFdir  				= true
dev.useTimsyncIds 				= false
dev.embeddedTimestampInPacket	= true
dev.skipSync					= true

dev.timeRegisters = {0, 0, 0, 0}

-- timestamps are automatically enabled for all RX and TX queues,
-- when using the modified version of the ice driver
function dev:enableRxTimestamps(self, udpPort) end

-- resetting the counter from a virtual function is not possible 
function dev:resetTimeCounters() return 1 end

-- rx timestamps are captured for all received packets
-- (if using the modified ice driver)
function dev:hasRxTimestamp() return 1 end

function dev:enableTxTimestamps(queue)
	self.tx_prev_ts = ffi.new("uint64_t[1]")
	self.tx_prev_ts[0] = 0
	self.tx_wraparound_ctr = ffi.new("uint64_t[1]")
	self.tx_wraparound_ctr[0] = 0
end

function dev:getTxTimestamp(queue, wait)
	return tonumber(dpdkc.iavf_tx_timestamps_read(self.id, 0, self.tx_prev_ts, self.tx_wraparound_ctr))
end

function dev:filterL2Timestamps(queue)
	local qid = type(queue) == "number" and queue or queue.qid
	if qid == 0 then
		self:flushFilter()
	else
		self:l2Filter(eth.TYPE_PTP, queue)
	end
end

return dev