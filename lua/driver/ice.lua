--- ice-specific code
local dev = {}

local dpdkc = require "dpdkc"
local ffi   = require "ffi"
local log   = require "log"
local eth   = require "proto.ethernet"

dev.e810						= true
dev.supportsFdir  				= true
dev.useTimsyncIds 				= false
dev.embeddedTimestampInPacket	= true
dev.customRateLimitPerQueue		= true
dev.skipSync					= true

dev.txStatsIgnoreCrc			= true
dev.rxStatsIgnoreCrc			= true

-- overhead per packet and maximum packet rate for use with crc rate limiting
dev.packetOverhead				= 24 --byte
dev.maxPacketRate				= 30 --Mpps
dev.lineRate 					= 100 --Gbps

-- set global rate liming
function dev:setRate(rate, pktSize)
	local bwLimit = rate

	-- The rate, which is printed by the stats task does not match the rate, which is set in the rate limiting function.
	-- Therfore we use rate limting based on packet rate, if the packet size is known
	if pktSize ~= nil then
		dpdkc.ice_tx_sched_set_pps_port(self.id, true)
		bwLimit =  ((bwLimit * 1e6) / ((pktSize+4)*8)) * 1000 * 2 / 1024
		-- rounding in lua copied from http://lua-users.org/wiki/SimpleRound
		dpdkc.ice_set_bw_limit(self.id, math.floor(bwLimit+0.5))
	else
		dpdkc.ice_tx_sched_set_pps_port(self.id, false)
		-- rounding in lua copied from http://lua-users.org/wiki/SimpleRound
		dpdkc.ice_set_bw_limit(self.id, math.floor(1000*bwLimit+0.5))
	end
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
	dpdkc.rte_eth_timesync_enable(self.id)
	self:resetTimeCounters()
end

-- initalize the PTP hardware 
function dev:enableRxTimestamps(queue, udpPort)
	dpdkc.rte_eth_timesync_enable(self.id)
	self:resetTimeCounters()
end

-- initalize the PTP hardware and initialize variables for handling TX timestamp overflow
function dev:enableTxTimestamps(queue)
	dpdkc.rte_eth_timesync_enable(self.id)
	self:resetTimeCounters()
end

function dev:resetTimeCounters()
	local ts = ffi.new("struct timespec")
	ts.tv_sec = 0
	ts.tv_nsec = 0
	dpdkc.rte_eth_timesync_write_time(self.id, ts)
	dpdkc.ice_reset_timer(self.id)
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

				-- the value of the reserved flag is used by the modified
				-- DPDK ice driver to switch between the modified flex byte filter
				-- and the generic flow offloading implemented by the unmodified
				-- DPDK driver (which is currently not working in moongen)
				-- (reserverd=1 => modified, reserverd=0 => default)
				reserved = 1,

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
