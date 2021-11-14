--- ice-specific code
local dev = {}

local dpdkc = require "dpdkc"
local ffi   = require "ffi"
local log   = require "log"
local eth   = require "proto.ethernet"

dev.supportsFdir  				= true
dev.useTimsyncIds 				= false
dev.embeddedTimestampInPacket	= true
dev.customRateLimitPerQueue		= true
dev.skipSync					= true

ffi.cdef[[
int libmoon_ice_reset_timecounters(uint32_t port_id);
]]

-- set global rate liming
function dev:setRate(rate, pktSize)
	local bwLimit = rate

	-- The rate, which is printed by the stats task does not match the rate, which is set in the rate limiting function.
	-- Therfore we added a correction function, which changes the set rate based on the packet size
	if pktSize ~= nil then
		bwLimit = (((pktSize+3.8)/pktSize)-0.045)*rate
	end
	dpdkc.ice_set_bw_limit(self.id, tonumber(bwLimit))
	
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

-- initalize the PTP hardware (same as for single packets in dev:enableRxTimestamps)
function dev:enableRxTimestampsAllPackets()
	dpdkc.ice_init_timer(self.id)
end

-- initalize the PTP hardware 
function dev:enableRxTimestamps(queue, udpPort)
	ffi.C.libmoon_ice_reset_timecounters(self.id)
	dpdkc.ice_init_timer(self.id)
end

-- initalize the PTP hardware and initialize variables for handling TX timestamp overflow
function dev:enableTxTimestamps(queue)
	self.tx_prev_ts = ffi.new("uint64_t[1]")
	self.tx_prev_ts[0] = 0
	self.tx_wraparound_ctr = ffi.new("uint64_t[1]")
	self.tx_wraparound_ctr[0] = 0

	dpdkc.ice_init_timer(self.id)
end

function dev:resetTimeCounters() 
	if(self.tx_prev_ts) then
		self.tx_prev_ts[0] = 0
		self.tx_wraparound_ctr[0] = 0
	end
	ffi.C.libmoon_ice_reset_timecounters(self.id)
end

-- read TX timestamp slot 0 from the PHY registers
function dev:getTxTimestamp(queue, wait)
	return tonumber(dpdkc.ice_tx_timestamps_read(self.id, 0, self.tx_prev_ts, self.tx_wraparound_ctr))
end

-- return timer value of the PTP timer on the E810 controller
function dev:readTime()
	return tonumber(dpdkc.ice_read_current_timer(self.id))
end

dev.timeRegisters = {0, 0, 0, 0}

function dev:hasRxTimestamp() return 1 end

-- this function is called from the filter module to get a DPDK generic flow API
-- pattern list to match UDP PTP packets, which works on E810 NICs (tested on E810-C)
function dev:getUdpTimestampFilter(ptpType, ver)
	-- set the flow items (filters)
	local rawPattern = ffi.new("uint8_t[2]")
	local rawMask = ffi.new("uint8_t[2]")
	rawPattern[0] = ptpType
	rawPattern[1] = ver
	rawMask[0] = 0xFF
	rawMask[1] = 0xFF

	-- match IPv4, with an ethertype corresponding to UDP, which an addional flex byte filter
	-- the offset of the RAW pattern is specified from the start of the ethernet frame
	local filters = ffi.new("struct rte_flow_item[4]", {
		ffi.new("struct rte_flow_item", {
			type = ffi.C.RTE_FLOW_ITEM_TYPE_ETH,
		}),
		ffi.new("struct rte_flow_item", {
			type = ffi.C.RTE_FLOW_ITEM_TYPE_IPV4,
			spec = ffi.new("struct rte_flow_item_ipv4", {
				hdr = {
					next_proto_id = 0x11,
				}
			}),
			mask = ffi.new("struct rte_flow_item_ipv4", {
				hdr = {
					next_proto_id = 0xFF,
				}
			})
		}),
		ffi.new("struct rte_flow_item", {
			type = ffi.C.RTE_FLOW_ITEM_TYPE_RAW,
			spec = ffi.new("struct rte_flow_item_raw", {
				relative = 0,
				search = 0,
				reserved = 0,
				offset = 42,
				limit = 0,
				length = 2,
				pattern = rawPattern
			}),
			mask = ffi.new("struct rte_flow_item_raw", {
				relative = 1,
				search = 1,
				reserved = 0,
				offset = ffi.cast("uint32_t", 4294967295), -- = 0xFFFFFFFF as unsigned int
				limit = 0xffff,
				length = 0xffff,
				pattern = rawMask
			})
		}),
		ffi.new("struct rte_flow_item", { type = ffi.C.RTE_FLOW_ITEM_TYPE_END })
	})

	return filters
end

return dev
