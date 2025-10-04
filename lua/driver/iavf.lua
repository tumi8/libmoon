--- iavf-specific code
local dev = {}

local ffi   = require "ffi"
local dpdkc = require "dpdkc"
local eth   = require "proto.ethernet"
local log   = require "log"

dev.txStatsIgnoreCrc			= true

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