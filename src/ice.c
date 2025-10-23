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

#include <math.h>

void ice_keep_link_up(int port){
	struct ice_pf *pf = ICE_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private);
	pf->init_link_up = true;
}

// Copied and modified code from ice_ethtool.c from the ice Linux driver 1.7.16
/**
 * ice_get_module_eeprom - fill buffer with SFF EEPROM contents
 * @netdev: network interface device structure
 * @ee: EEPROM dump request structure
 * @data: buffer to be filled with EEPROM contents
 */
static int ice_get_module_eeprom(struct ice_hw *hw, u32 ee_offset, u32 ee_len, u8 *data){
#define SFF_READ_BLOCK_SIZE 8
#define ICE_I2C_EEPROM_DEV_ADDR		0xA0
#define ICE_I2C_EEPROM_DEV_ADDR2	0xA2
#define ICE_MODULE_TYPE_SFP		0x03
#define ETH_MODULE_SFF_8079_LEN		256
#define ETH_MODULE_SFF_8436_LEN		256
	u8 value[SFF_READ_BLOCK_SIZE] = {0};
	u8 addr = ICE_I2C_EEPROM_DEV_ADDR;
	enum ice_status status;
	bool is_sfp = false;
	unsigned int i, j;
	u16 offset = 0;
	u8 page = 0;

	if (!ee_len || !data)
		return -EINVAL;

	status = ice_aq_sff_eeprom(hw, 0, addr, offset, page, 0, value, 1, 0,
				   NULL);
	if (status)
		return -EIO;

	if (value[0] == ICE_MODULE_TYPE_SFP)
		is_sfp = true;

	memset(data, 0, ee_len);
	for (i = 0; i < ee_len; i += SFF_READ_BLOCK_SIZE) {
		offset = i + ee_offset;
		page = 0;

		/* Check if we need to access the other memory page */
		if (is_sfp) {
			if (offset >= ETH_MODULE_SFF_8079_LEN) {
				offset -= ETH_MODULE_SFF_8079_LEN;
				addr = ICE_I2C_EEPROM_DEV_ADDR2;
			}
		} else {
			while (offset >= ETH_MODULE_SFF_8436_LEN) {
				/* Compute memory page number and offset. */
				offset -= ETH_MODULE_SFF_8436_LEN / 2;
				page++;
			}
		}

		/* Bit 2 of eeprom address 0x02 declares upper
		 * pages are disabled on QSFP modules.
		 * SFP modules only ever use page 0.
		 */
		if (page == 0 || !(data[0x2] & 0x4)) {
			/* If i2c bus is busy due to slow page change or
			 * link management access, call can fail. This is normal.
			 * So we retry this a few times.
			 */
			for (j = 0; j < 4; j++) {
				status = ice_aq_sff_eeprom(hw, 0, addr, offset, page,
							   !is_sfp, value,
							   SFF_READ_BLOCK_SIZE,
							   0, NULL);
				if (status) {
					usleep_range(1500, 2500);
					memset(value, 0, SFF_READ_BLOCK_SIZE);
					continue;
				}
				break;
			}

			/* Make sure we have enough room for the new block */
			if ((i + SFF_READ_BLOCK_SIZE) <= ee_len)
				memcpy(data + i, value, SFF_READ_BLOCK_SIZE);
		}
	}
	return 0;
}
// End of copied code

float ice_get_qsfp_temp(int port){
	struct ice_hw *hw;
	u8 data[8];

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);

	// temperature offset and format specified in https://members.snia.org/document/dl/26418
	if(ice_get_module_eeprom(hw, 96+256, 8, data) != 0)return NAN;
	return (256*data[0]+data[1]) / 256.0f;
}

void ice_take_timer_ownership(int port){
	struct ice_hw *hw;
	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	hw->func_caps.ts_func_info.src_tmr_owned = true;

	// use timer 0 regardless of what the NVM configuration says.
	// Without this settings, no RX or TX timestamps could be captured on the
	// tested E810 XXV NICs on the second port
	hw->func_caps.ts_func_info.tmr_index_owned = 0;
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
	tmr_index_owned = hw->func_caps.ts_func_info.tmr_index_owned;

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