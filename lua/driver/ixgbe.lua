--- ixgbe-specific code
local dev = {}

local dpdkc = require "dpdkc"
local ffi   = require "ffi"
local log   = require "log"

-- rx stats
local GPRC	= 0x00004074
local GORCL = 0x00004088
local GORCH	= 0x0000408C

-- tx stats
local GPTC      = 0x00004080
local GOTCL     = 0x00004090
local GOTCH     = 0x00004094

-- timestamping
local RXMTRL     = 0x00005120
local TSYNCRXCTL = 0x00005188
local RXSATRH    = 0x000051A8
local SYSTIMEL   = 0x00008C0C
local SYSTIMEH   = 0x00008C10
local TIMEADJL   = 0x00008C18
local TIMEADJH   = 0x00008C1C
local ETQS_3     = 0x0000EC00 + 4 * 3

local TSYNCRXCTL_RXTT            = 1
local TSYNCRXCTL_TYPE_OFFS       = 1
local TSYNCRXCTL_TYPE_MASK       = bit.lshift(7, TSYNCRXCTL_TYPE_OFFS)
local TSYNCRXCTL_TSIP_UT_EN_OFFS = 23
local TSYNCRXCTL_TSIP_UP_EN_OFFS = 24

local ETQS_RX_QUEUE_OFFS   = 16
local ETQS_QUEUE_ENABLE    = bit.lshift(1, 31)

dev.driverInfo = {}

dev.supportsFdir  = true
dev.timeRegisters = {SYSTIMEL, SYSTIMEH, TIMEADJL, TIMEADJH}
dev.crcPatch      = true

-- magic values for the CRC based rate control in moongen
dev.minPacketSize = 14   -- yes, this NIC can send out packets that are that small without padding :)
dev.maxPacketRate = 16.4 -- maximum rate with illegally small packets

-- ixgbe does not count bytes dropped due to buffer space and the packet drop counters seem to be empty
-- however, we want to count all packets *at the NIC level* regardless whether they were fetched by the driver or not
-- this behavior is consistent with other drivers and more useful
function dev:getRxStats()
	-- these counters are clear-on-read
	self.rxPkts = (self.rxPkts or 0ULL) + dpdkc.read_reg32(self.id, GPRC)
	self.rxBytes = (self.rxBytes or 0ULL) + dpdkc.read_reg32(self.id, GORCL) + dpdkc.read_reg32(self.id, GORCH) * 2^32
	return tonumber(self.rxPkts), tonumber(self.rxBytes)
end

-- clear RX counters.  We want to clear the s/w statistics and also reg read to clear the h/w level
function dev:clearRxStats()
	dpdkc.read_reg32(self.id, GPRC)
	dpdkc.read_reg32(self.id, GORCL)
	dpdkc.read_reg32(self.id, GORCH)
	self.rxPkts = 0ULL
	self.rxBytes = 0ULL
	return
end

-- clear TX counters.  We want to clear the s/w statistics and also reg read to clear the h/w level
function dev:clearTxStats()
       -- Read the hardware registers to clear them
       dpdkc.read_reg32(self.id, GPTC)
       dpdkc.read_reg32(self.id, GOTCL)
       dpdkc.read_reg32(self.id, GOTCH)
       -- Reset the software accumulation counters
       self.txPkts = 0ULL
       self.txBytes = 0ULL
       return
end

-- necessary because of clear-on-read registers and the interaction with the normal rte_eth_stats_get() call
function dev:getTxStats()
	self.txPkts = (self.txPkts or 0ULL) + dpdkc.read_reg32(self.id, GPTC)
	self.txBytes = (self.txBytes or 0ULL) + dpdkc.read_reg32(self.id, GOTCL) + dpdkc.read_reg32(self.id, GOTCH) * 2^32
	return tonumber(self.txPkts), tonumber(self.txBytes)
end

ffi.cdef[[
int libmoon_ixgbe_reset_timecounters(uint32_t port_id);
]]

function dev:resetTimeCounters()
	ffi.C.libmoon_ixgbe_reset_timecounters(self.id)
end

-- just rte_eth_timesync_enable doesn't do the trick :(
function dev:enableRxTimestamps(queue, udpPort)
	udpPort = udpPort or 319
	dpdkc.rte_eth_timesync_enable(self.id)
	-- enable timestamping UDP packets as well
	local val = dpdkc.read_reg32(self.id, TSYNCRXCTL)
	val = bit.band(val, bit.bnot(TSYNCRXCTL_TYPE_MASK))
	val = bit.bor(val, bit.lshift(2, TSYNCRXCTL_TYPE_OFFS))
	dpdkc.write_reg32(self.id, TSYNCRXCTL, val)
	-- configure UDP port
	-- fun fact: the register is initialized to 0x319 instead of 319
	dpdkc.write_reg32(self.id, RXMTRL, bit.lshift(udpPort, 16))
end

-- could skip a few registers here, but doesn't matter
dev.enableTxTimestamps = dev.enableRxTimestamps

function dev:hasRxTimestamp()
	if bit.band(dpdkc.read_reg32(self.id, TSYNCRXCTL), TSYNCRXCTL_RXTT) == 0 then
		return nil
	end
	-- this register is undocumented on X550 but it seems to work just fine
	local res = bswap16(bit.rshift(dpdkc.read_reg32(self.id, RXSATRH), 16))
	return res
end

function dev:filterL2Timestamps(queue)
	-- DPDK's init function configures ETQF3 to enable PTP L2 timestamping, so use this one
	dpdkc.write_reg32(self.id, ETQS_3, bit.bor(ETQS_QUEUE_ENABLE, bit.lshift(queue.qid, ETQS_RX_QUEUE_OFFS)))
end

function dev:enableRxTimestampsAllPackets(queue)
	dpdkc.rte_eth_timesync_enable(self.id)
	local val = dpdkc.read_reg32(self.id, TSYNCRXCTL)
	val = bit.band(val, bit.bnot(TSYNCRXCTL_TYPE_MASK))
	val = bit.bor(val, bit.lshift(4, TSYNCRXCTL_TYPE_OFFS))
	val = bit.bor(val, bit.lshift(1, TSYNCRXCTL_TSIP_UT_EN_OFFS))
	-- not necessary unless you configure some weird stuff
	val = bit.bor(val, bit.lshift(0xFF, TSYNCRXCTL_TSIP_UP_EN_OFFS))
	dpdkc.write_reg32(self.id, TSYNCRXCTL, val)
end

dev.embeddedTimestampAtEndOfBuffer = true

-- this function is called from the filter module to get a DPDK generic flow API
-- pattern list to match UDP PTP packets, which works on X500 NICs (tested on X550)
function dev:getUdpTimestampFilter(ptpType, ver)
	-- set the flow items (filters)
	local rawPattern = ffi.new("uint8_t[2]")
	local rawMask = ffi.new("uint8_t[2]")
	rawPattern[0] = ptpType
	rawPattern[1] = ver
	rawMask[0] = 0xFF
	rawMask[1] = 0xFF

	-- the offset of the RAW pattern is specified from the start of ethernet frame
	-- On X550 NICs it is not possible to use a flex byte filters while masking
	-- all bytes of the UDP ports. Therfore one bit of the UDP destination port
	-- is matched. Two filters are added to cover all possible values of this bit.
	-- This idea was taken from http://mails.dpdk.org/archives/dev/2016-May/039720.html
	local firstFilter = ffi.new("struct rte_flow_item[5]", {
		ffi.new("struct rte_flow_item", {
			type = ffi.C.RTE_FLOW_ITEM_TYPE_IPV4,
			spec = ffi.new("struct rte_flow_item_ipv4", {
				hdr = {}
			}),
			mask = ffi.new("struct rte_flow_item_ipv4", {
				hdr = {}
			})
		}),
		ffi.new("struct rte_flow_item", {
			type = ffi.C.RTE_FLOW_ITEM_TYPE_UDP,
			spec = ffi.new("struct rte_flow_item_udp", {
				hdr = {
					dst_port = hton16(1)
				}
			}),
			mask = ffi.new("struct rte_flow_item_udp", {
				hdr = {
					dst_port = hton16(1)
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

	local secondFilter = ffi.new("struct rte_flow_item[5]", {
		ffi.new("struct rte_flow_item", {
			type = ffi.C.RTE_FLOW_ITEM_TYPE_IPV4,
			spec = ffi.new("struct rte_flow_item_ipv4", {
				hdr = {}
			}),
			mask = ffi.new("struct rte_flow_item_ipv4", {
				hdr = {}
			})
		}),
		ffi.new("struct rte_flow_item", {
			type = ffi.C.RTE_FLOW_ITEM_TYPE_UDP,
			spec = ffi.new("struct rte_flow_item_udp", {
				hdr = {
					dst_port = hton16(0)
				}
			}),
			mask = ffi.new("struct rte_flow_item_udp", {
				hdr = {
					dst_port = hton16(1)
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

	return {firstFilter, secondFilter}
end

return dev

