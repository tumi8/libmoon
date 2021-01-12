--- ice-specific code
local dev = {}

local dpdkc = require "dpdkc"
local ffi   = require "ffi"
local log   = require "log"

function dev:enableRxTimestampsAllPackets(queue)
	dpdkc.ice_init_timer(self.id)
end

return dev

