--- iavf-specific code
local dev = {}

local ffi   = require "ffi"
local dpdkc = require "dpdkc"
local eth   = require "proto.ethernet"
local log   = require "log"

dev.supportsFdir  				= true
dev.useTimsyncIds 				= false
dev.embeddedTimestampInPacket	= true
dev.skipSync					= true

dev.timeRegisters = {0, 0, 0, 0}

-- timestamps are automatically enabled for all RX and TX queues,
-- when using the modified version of the ice driver
function dev:enableRxTimestamps(self, udpPort)
	if not dpdkc.iavf_modified_driver_detected(self.id) then
		log:fatal("rx timestamping for E810 VFs requires a modified version of the PF driver")
	end
end

function dev:enableRxTimestampsAllPackets()
	if not dpdkc.iavf_modified_driver_detected(self.id) then
		log:fatal("rx timestamping for E810 VFs requires a modified version of the PF driver")
	end
end

-- resetting the counter from a virtual function is not possible 
function dev:resetTimeCounters() return 1 end

-- rx timestamps are captured for all received packets
-- (if using the modified ice driver)
function dev:hasRxTimestamp() return 1 end

function dev:enableTxTimestamps(queue)
	if not dpdkc.iavf_modified_driver_detected(self.id) then
		log:fatal("tx timestamping for E810 VFs requires a modified version of the PF driver")
	end
	self.tx_prev_ts = ffi.new("uint64_t[1]")
	self.tx_prev_ts[0] = 0
	self.tx_wraparound_ctr = ffi.new("uint64_t[1]")
	self.tx_wraparound_ctr[0] = 0
end

function dev:getTxTimestamp(queue, wait)
	return tonumber(dpdkc.iavf_tx_timestamps_read(self.id, 0, self.tx_prev_ts, self.tx_wraparound_ctr))
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

-- this function is called from the filter module to get a DPDK generic flow API
-- pattern list to match UDP PTP packets, which works on E810 VFs. This only works
-- with a modified version of the DPDK VF and PF drivers
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