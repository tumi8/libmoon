-- mlx5-specific code
local dev = {}

local dpdkc = require "dpdkc"
local ffi =  require "ffi"
local log = require "log"

local C = ffi.C

dev.embeddedTimestampInPacket	= true
dev.supportsFdir  				= true
dev.skipSync					= true

--- Function which sets all mlx5 specific values, is automatically called at program startup
function dev:init()
	
	-- to enable statistics which count all packets fetched by the driver or not we have to use the xstats
	-- of the device
	-- first retrieve the IDs of the required xstat fields
	-- in case any of those stats is missing, proper packet/byte counting is not possible
	-- last resort in this case is to comment out dev:getRxStats() to default to the normal counting behavior
	local id = ffi.new("uint64_t[1]", 1337)
	
	local ok = C.rte_eth_xstats_get_id_by_name(self.id, "rx_unicast_bytes", id)
	self.uc_byte_id = tonumber(id[0])
	if ok ~= 0 then log:fatal("Failed to extract xstats. Uniform packet counting not possible.") end
	
	ok = C.rte_eth_xstats_get_id_by_name(self.id, "rx_multicast_bytes", id)
	self.mc_byte_id = tonumber(id[0])
	if ok ~= 0 then log:fatal("Failed to extract xstats. Uniform packet counting not possible.") end

	ok = C.rte_eth_xstats_get_id_by_name(self.id, "rx_broadcast_bytes", id)
	self.bc_byte_id = tonumber(id[0])
	if ok ~= 0 then log:fatal("Failed to extract xstats. Uniform packet counting not possible.") end

	ok = C.rte_eth_xstats_get_id_by_name(self.id, "rx_unicast_packets", id)
	self.uc_pkt_id = tonumber(id[0])
	if ok ~= 0 then log:fatal("Failed to extract xstats. Uniform packet counting not possible.") end

	ok = C.rte_eth_xstats_get_id_by_name(self.id, "rx_multicast_packets", id)
	self.mc_pkt_id = tonumber(id[0])
	if ok ~= 0 then log:fatal("Failed to extract xstats. Uniform packet counting not possible.") end

	ok = C.rte_eth_xstats_get_id_by_name(self.id, "rx_broadcast_packets", id)
	self.bc_pkt_id = tonumber(id[0])
	if ok ~= 0 then log:fatal("Failed to extract xstats. Uniform packet counting not possible.") end

	-- retrieve the number of available xstats
	self.numxstats = 0
	local xstats = ffi.new("struct rte_eth_xstat[?]", self.numxstats)
	
	-- because there is no easy function which returns the number of xstats we try to retrieve
	-- the xstats with a zero sized array
	-- if result > numxstats (0 in this case), then result equals the real number of xstats
	local result = C.rte_eth_xstats_get(self.id, xstats, self.numxstats)
	
	-- result will be at least 6, otherwise the above statements would have failed
	self.numxstats = tonumber(result)

end

--- Retrieve RxStats which are comparable between most devices
--- All packets are considered, regardless of memory errors, wrong CRCs etc.
function dev:getRxStats()
	-- the function "rte_eth_xstats_get_by_id" does not seem to work properly. It always returns the first xstat entry, ignoring the IDs
	-- so we get all xstats and use the IDs as index

	-- this function is called once every second or so. Performance penalty should be negligible

	-- only allocate xstats once
	if not self.xstats then
		self.xstats = ffi.new("struct rte_eth_xstat[?]", self.numxstats)
	end
        C.rte_eth_xstats_get(self.id, self.xstats, self.numxstats)

	-- sum of all recieved unicast, multicast and broadcast bytes/packets
	self.rxPkts = (self.xstats[self.uc_pkt_id].value or 0ULL) + (self.xstats[self.mc_pkt_id].value or 0ULL) + (self.xstats[self.bc_pkt_id].value or 0ULL)
	self.rxBytes =  (self.xstats[self.uc_byte_id].value or 0ULL) + (self.xstats[self.mc_byte_id].value or 0ULL) + (self.xstats[self.bc_byte_id].value or 0ULL)
	return tonumber(self.rxPkts), tonumber( self.rxBytes)
end

--- Custom RSS Setup for Mellanox ConnectX 6 NICS -> The RETA size can be changed -> use 64
function dev:setRssQueues(n, baseQueue)
	baseQueue = baseQueue or 0
	assert(n > 0)
	if bit.band(n, n - 1) ~= 0 then
		log:warn("RSS distribution to queues will not be balanced as the number of queues (%d) is not a power of two.", n)
	end
	local retaSize = 64
	local entries = ffi.new("struct rte_eth_rss_reta_entry64[?]", retaSize / 64)
	local queue = baseQueue
	for i = 0, retaSize / 64 - 1 do
		entries[i].mask = 0xFFFFFFFFFFFFFFFFULL
		for j = 0, 63 do
			entries[i].reta[j] = queue
			queue = queue + 1
			if queue == baseQueue + n then
				queue = baseQueue
			end
		end
	end
	local ret = ffi.C.rte_eth_dev_rss_reta_update(self.id, entries, retaSize)
	if ret ~= 0 then
		log:fatal("Error setting up RETA table: " .. strError(ret))
	end
end

-- the timestamping counters on mlx5 devices are enabled by default
-- timestamps are added to all received packets automatically, when the corresponding
-- RX offload flag is set
function dev:enableRxTimestampsAllPackets(queue) end
function dev:enableRxTimestamps(queue, udpPort) end

return dev
