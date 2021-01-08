--- ixgbe-specific code
local dev = {}

local dpdkc = require "dpdkc"
local ffi   = require "ffi"
local log   = require "log"

local GLTSYN_SYNC_DLAY = 0x00088818

local GLTSYN_ENA0 = 0x00088808
local GLTSYN_ENA1 = 0x0008880C

local GLTSYN_INCVAL_H0 = 0x00088920 
local GLTSYN_INCVAL_H1 = 0x00088924 
local GLTSYN_INCVAL_L0 = 0x00088918
local GLTSYN_INCVAL_L1 = 0x0008891C

local GLTSYN_STAT0 = 0x000888C0
local GLTSYN_STAT1 = 0x000888C4

local GLINT_TSYN_PHY = 0x0016CC50
local GLINT_TSYN_PFMSTR0 = 0x0016CCC0
local GLINT_TSYN_PFMSTR1 = 0x0016CCC4

local GLINT_TSYN_PHY = 0x0016CC50
local PF_SB_REM_DEV_CTL = 0x002300F0

print("icedriver")

function dev:readAndSet(value, name, setVal)
	dpdkc.write_reg32(self.id, value, setVal)
	self:onlyRead(value, name)
end

function dev:onlyRead(value, name)
	local val = dpdkc.read_reg32(self.id, value)
	print(name .. ' ' .. val .. ', self.id: ' .. self.id)
end

function dev:enableRxTimestampsAllPackets(queue)
	dpdkc.ice_init_timer()
	print('has RX timestamp all packets')

	--udpPort = udpPort or 319
	--dpdkc.rte_eth_timesync_enable(self.id)
	
	--val = bit.band(val, bit.bnot(TSYNCRXCTL_TYPE_MASK))
	--val = bit.bor(val, bit.lshif9t(2, TSYNCRXCTL_TYPE_OFFS))
	--dpdkc.write_reg32(self.id, TSYNCRXCTL, val)
	--self:readAndSet(GLTSYN_SYNC_DLAY, 'GLTSYN_SYNC_DLAY', 0x0)

	--self:onlyRead(GLTSYN_ENA0, 'GLTSYN_ENA0')
	--self:onlyRead(GLTSYN_ENA1, 'GLTSYN_ENA1')
	--self:readAndSet(GLTSYN_ENA0, 'GLTSYN_ENA0', 0x1)
	--self:readAndSet(GLTSYN_ENA1, 'GLTSYN_ENA1', 0x1)

	--local val = dpdkc.read_reg32(self.id, GLTSYN_STAT0)
	--val = bit.band(val, 0xFFFFFF08)
	--self:readAndSet(GLTSYN_STAT0, 'GLTSYN_STAT0', val)
	--local val = dpdkc.read_reg32(self.id, GLTSYN_STAT1)
	--val = bit.band(val, 0xFFFFFF08)
	--self:readAndSet(GLTSYN_STAT1, 'GLTSYN_STAT1', val)

	--local val = dpdkc.read_reg32(self.id, GLINT_TSYN_PHY)
	--val = bit.band(val, 0xFFFFFFE0)
	--self:readAndSet(GLINT_TSYN_PHY, 'GLINT_TSYN_PHY', val)

	--local val = dpdkc.read_reg32(self.id, PF_SB_REM_DEV_CTL)
        --local val = bit.bor(val, 0x2) -- PF_SB_REM_DEV_CTL_PHY0
	--self:readAndSet(PF_SB_REM_DEV_CTL, 'PF_SB_REM_DEV_CTL', val)
        
	--self:readAndSet(GLINT_TSYN_PFMSTR0, 'GLINT_TSYN_PFMSTR0', 0x0)
	--self:readAndSet(GLINT_TSYN_PFMSTR1, 'GLINT_TSYN_PFMSTR1', 0x0)

	--self:onlyRead(GLTSYN_INCVAL_H0, 'GLTSYN_INCVAL_H0')
	--self:onlyRead(GLTSYN_INCVAL_H1, 'GLTSYN_INCVAL_H1')
	--self:readAndSet(GLTSYN_INCVAL_H0, 'GLTSYN_INCVAL_H0', 0xF)
	--self:readAndSet(GLTSYN_INCVAL_L0, 'GLTSYN_INCVAL_L0', 0xF)
	--self:readAndSet(GLTSYN_INCVAL_H1, 'GLTSYN_INCVAL_H1', 0xFFFF)
	--self:readAndSet(GLTSYN_INCVAL_L1, 'GLTSYN_INCVAL_L1', 0xFFFF)
	
	print('written')
end

dev.embeddedTimestampAtEndOfBuffer = true

return dev

