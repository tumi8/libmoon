--- iavf-specific code
local dev = {}

local ffi   = require "ffi"
local dpdkc = require "dpdkc"
local eth   = require "proto.ethernet"
local log   = require "log"

dev.e810_vf						= true
dev.supportsFdir  				= true
dev.txStatsIgnoreCrc			= true

-- timestamps are automatically enabled for all RX and TX queues,
-- when using the modified version of the ice driver
function dev:enableRxTimestamps(self, udpPort)
	log:warn("Timestamping for E810 VFs is not supported in this version of Moongen. Use the older version (branch dpdk-21.11) instead")
end

function dev:enableRxTimestampsAllPackets()
	log:warn("Timestamping for E810 VFs is not supported in this version of Moongen. Use the older version (branch dpdk-21.11) instead")
end

-- resetting the counter from a virtual function is not possible 
function dev:resetTimeCounters() return 1 end

function dev:hasRxTimestamp() return 0 end

function dev:enableTxTimestamps(queue)
	log:warn("Timestamping for E810 VFs is not supported in this version of Moongen. Use the older version (branch dpdk-21.11) instead")
end

-- remove previous filters and add new filter to direct L2 PTP packets to the specified queue
function dev:filterL2Timestamps(queue)
	local qid = type(queue) == "number" and queue or queue.qid
	if qid == 0 then
		self:flushFilter()
	else
		self:l2Filter(eth.TYPE_PTP, queue)
	end
end

return dev