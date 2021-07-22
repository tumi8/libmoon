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

ffi.cdef[[
int libmoon_ice_reset_timecounters(uint32_t port_id);
]]

function dev:setRate(rate)
	dpdkc.ice_set_bw_limit(self.id, tonumber(rate))
end

function dev:filterL2Timestamps(queue)
	local qid = type(queue) == "number" and queue or queue.qid
	if qid == 0 then
		self:flushFilter()
	else
		self:l2Filter(eth.TYPE_PTP, queue)
	end
end

function dev:enableRxTimestampsAllPackets()
	dpdkc.ice_init_timer(self.id)
end

function dev:enableRxTimestamps(queue, udpPort)
	ffi.C.libmoon_ice_reset_timecounters(self.id)
	dpdkc.ice_init_timer(self.id)

	if udpPort ~= nil then
		self:udpFilter({dst_port = udpPort}, queue.qid)
	end
end

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


function dev:getTxTimestamp(queue, wait)
	return tonumber(dpdkc.ice_tx_timestamps_read(self.id, 0, self.tx_prev_ts, self.tx_wraparound_ctr))
end

function dev:readTime()
	return tonumber(dpdkc.ice_read_current_timer(self.id))
end

-- yes, this card supports timestamping
-- (TODO might want to implement something here)
dev.timeRegisters = {0, 0, 0, 0}

function dev:hasRxTimestamp() return 1 end

function dev:getUdpTimestampFilter(ptpType, ver)
	-- set the flow items (filters)
	local rawPattern = ffi.new("uint8_t[2]")
	local rawMask = ffi.new("uint8_t[2]")
	rawPattern[0] = ptpType
	rawPattern[1] = ver
	rawMask[0] = 0xFF
	rawMask[1] = 0xFF

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
