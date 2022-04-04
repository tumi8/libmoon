#include <rte_config.h>
#include <rte_ethdev.h>

#include <ice_type.h>
#include <ice_common.h>
#include <ice_sbq_cmd.h>
#include <ice_ethdev.h>
#include <ice_sched.h>
#include <ice_status.h>
#include <ice_rxtx.h>
#include <ice_ptp_hw.h>

void ice_take_timer_ownership(int port){
	struct ice_hw *hw;
	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	hw->func_caps.ts_func_info.src_tmr_owned = true;
}

void ice_reset_timer(int port){
	struct ice_hw *hw;
	enum ice_status status;

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);

	status = ice_ptp_init_time(hw, 0);

	if(status != ICE_SUCCESS){
		printf("Error while resetting PHY and Controller time registers!\n");
	}
}

// set rate limting for a single queue
void ice_set_q_bw_limit(int port, int queue, uint32_t bw){
	struct ice_hw *hw;
	struct ice_pf *pf;
	enum ice_status status;

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	pf = ICE_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private);

	status = ice_cfg_q_bw_lmt(hw->port_info, pf->main_vsi->idx, 0, queue, ICE_MAX_BW, bw);

	if(status != ICE_SUCCESS){
		printf("Could not set max bandwidth limit for queue %d!\n", queue);
	}
}

// set rate limting for the device
void ice_set_bw_limit(int port, uint32_t bw){
	struct ice_hw *hw;
	struct ice_pf *pf;
	enum ice_status status;

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	pf = ICE_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private);

	status = ice_cfg_vsi_bw_lmt_per_tc(hw->port_info, pf->main_vsi->idx, 0, ICE_MAX_BW, bw);

	if(status != ICE_SUCCESS){
		printf("Could not set max bandwidth limit for port %d!\n", port);
	}
}

// read timer value of the PTP counter on the controller
uint64_t ice_read_current_timer(int port){
	u32 timeL, timeL2;
	u32 timeH;
	u8 tmr_index_owned;
	struct ice_hw *hw;

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	tmr_index_owned = 0;

	//read captured time (similar procedure as in ice 1.6.4 driver function: ice_ptp_read_src_clk_reg)
	timeL = rd32(hw, GLTSYN_TIME_L(tmr_index_owned));
	timeH = rd32(hw, GLTSYN_TIME_H(tmr_index_owned));
	timeL2 = rd32(hw, GLTSYN_TIME_L(tmr_index_owned));

	if(timeL2 < timeL){
		timeL = rd32(hw, GLTSYN_TIME_L(tmr_index_owned));
		timeH = rd32(hw, GLTSYN_TIME_H(tmr_index_owned));
	}

	return ((u64)timeH << 32) | timeL;
}