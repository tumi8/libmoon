--- Forward packets between two ports
local lm     = require "libmoon"
local device = require "device"
local stats  = require "stats"
local log    = require "log"
local memory = require "memory"
local dpdkc  = require "dpdkc"

-- set addresses here
local DST_MAC       = "11:bb:cc:00:00:00"
local PKT_LEN       = 60
local SRC_IP        = "10.0.0.10"
local DST_IP        = "10.1.0.10"
local SRC_PORT_BASE = 1234
local DST_PORT      = 1234
local NUM_FLOWS     = 1000

function configure(parser)
	parser:argument("dev", "Devices to use"):args(1):convert(tonumber)
	parser:option("-o --output", "File to output statistics to")
	return parser:parse()
end

function master(args)
	-- configure devices
	
	args.dev = device.config({
		port = args.dev,
		txQueues = 1,
		rxQueues = 1,
		--rssQueues = args.threads
	})
	device.waitForLinks()

	-- print stats
	stats.startStatsTask{devices = args.dev, file = args.output}

	-- start forwarding tasks
	lm.startTask("txSlave", args.dev:getTxQueue(0))
	lm.waitForTasks()
end

function txSlave(queue)
	queue.dev:enableRxTimestampsAllPackets()
	-- memory pool with default values for all packets, this is our archetype
	local mempool = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			-- fields not explicitly set here are initialized to reasonable defaults
			ethSrc = queue, -- MAC of the tx device
			ethDst = DST_MAC,
			ip4Src = SRC_IP,
			ip4Dst = DST_IP,
			udpSrc = SRC_PORT,
			udpDst = DST_PORT,
			pktLength = PKT_LEN
		}
	end)
	-- a bufArray is just a list of buffers from a mempool that is processed as a single batch
	local bufs = mempool:bufArray(1)
	while lm.running() do -- check if Ctrl+c was pressed
		-- this actually allocates some buffers from the mempool the array is associated with
		-- this has to be repeated for each send because sending is asynchronous, we cannot reuse the old buffers here
		bufs:alloc(PKT_LEN)
		for i, buf in ipairs(bufs) do
			-- packet framework allows simple access to fields in complex protocol stacks
			buf:enableIceTxTimestamp(0)
			local pkt = buf:getUdpPacket()
			pkt.udp:setSrcPort(SRC_PORT_BASE + math.random(0, NUM_FLOWS - 1))
		end
		-- UDP checksums are optional, so using just IPv4 checksums would be sufficient here
		-- UDP checksum offloading is comparatively slow: NICs typically do not support calculating the pseudo-header checksum so this is done in SW
		bufs:offloadUdpChecksums()
		-- send out all packets and frees old bufs that have been sent
		queue:send(bufs)
		print(tonumber(dpdkc.ice_tx_timestamps_read(1, 0)))

		lm.sleepMillisIdle(1000)
		print('sent packet')
	end
end

