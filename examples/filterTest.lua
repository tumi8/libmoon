--- Forward packets between two ports
local lm     = require "libmoon"
local device = require "device"
local stats  = require "stats"
local log    = require "log"
local memory = require "memory"
local dpdkc  = require "dpdkc"

function configure(parser)
	parser:argument("dev", "Devices to use"):args(2):convert(tonumber)
	return parser:parse()
end

function master(args)
	-- configure devices
	if args.dev[1] == args.dev[2] then
		print('you need to enter two different interfaces')
		return
	end

	for i, dev in ipairs(args.dev) do
		args.dev[i] = device.config{
			port = dev,
			txQueues = 1,
			rxQueues = 2,
			--rssQueues = args.threads
		}
	end
	device.waitForLinks()

	-- start forwarding tasks
	--lm.startTask("txSlaveEthPTP", args.dev[1]:getTxQueue(0))

	--filter = {
	--	protocol = 0x11
	--}
	--args.dev[2]:fiveTupleFilter(filter, 1)
	args.dev[2]:filterUdpTimestamps(1)
	args.dev[2]:dumpFilters()

	lm.startTask("txSlavePTP", args.dev[1]:getTxQueue(0))
	
	lm.startTask("rxSlave", args.dev[2]:getRxQueue(0))
	lm.startTask("rxSlave", args.dev[2]:getRxQueue(1))
	lm.waitForTasks()
end

function rxSlave(rxQueue)
	--rxQueue.dev:dumpFilters()
	-- a bufArray is just a list of buffers that we will use for batched forwarding
	local bufs = memory.bufArray()
	while lm.running() do -- check if Ctrl+c was pressed
		-- receive one or more packets from the queue
		local count = rxQueue:recv(bufs)
		for i = 1, count do
            print("received packet on queue: "..tostring(rxQueue.qid))
            bufs[i]:dump()
		end
	end
end

local DST_MAC       = "11:bb:cc:00:00:00"
local PKT_LEN       = 60
local SRC_IP        = "10.0.0.10"
local DST_IP        = "10.1.0.10"
local SRC_PORT_BASE = 1234
local DST_PORT      = 1234
local NUM_FLOWS     = 1000

local packetFunctions = {
	(function (packet) 
		packet.ptp:setVersion(1)
	end),

	(function (packet) 
		packet.udp:setDstPort(4543)
	end),

	(function (packet) 
		packet.ip4:setDstString("192.168.178.1")
	end),

	(function (packet) 
		packet.eth:setType(0x0806)
	end)
}

function txSlaveEthPTP(queue)
	-- memory pool with default values for all packets, this is our archetype
	local mempool = memory.createMemPool(function(buf)
		buf:getPtpPacket():fill{
		}
	end)

	-- a bufArray is just a list of buffers from a mempool that is processed as a single batch
	local bufs = mempool:bufArray(1)

	for i=1,#packetFunctions do
		if not lm.running() then break end

		-- this actually allocates some buffers from the mempool the array is associated with
		-- this has to be repeated for each send because sending is asynchronous, we cannot reuse the old buffers here
		bufs:alloc(PKT_LEN)
		-- packet framework allows simple access to fields in complex protocol stacks
		-- send out all packets and frees old bufs that have been sent
		queue:send(bufs)
		print('sent packet')
        lm.sleepMillisIdle(1000)
	end
end

function txSlavePTP(queue)
	-- memory pool with default values for all packets, this is our archetype
	local mempool = memory.createMemPool(function(buf)
		buf:getUdpPtpPacket():fill{
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

	for i=1,#packetFunctions do
		if not lm.running() then break end

		-- this actually allocates some buffers from the mempool the array is associated with
		-- this has to be repeated for each send because sending is asynchronous, we cannot reuse the old buffers here
		bufs:alloc(PKT_LEN)
		-- packet framework allows simple access to fields in complex protocol stacks
		local pkt = bufs[1]:getUdpPtpPacket()
		packetFunctions[i](pkt)
		-- UDP checksums are optional, so using just IPv4 checksums would be sufficient here
		-- UDP checksum offloading is comparatively slow: NICs typically do not support calculating the pseudo-header checksum so this is done in SW
		-- bufs:offloadUdpChecksums()
		-- send out all packets and frees old bufs that have been sent
		queue:send(bufs)
		print('sent packet')
        lm.sleepMillisIdle(1000)
	end
end
