#include <rte_config.h>
#include <rte_ethdev.h> 

// i40e_ethdev.h depends on lots of stuff that it doesn't include
//#define PF_DRIVER
//#include <base/i40e_register.h>
//#include <base/i40e_prototype.h>
#include <ice_type.h>
#include <ice_common.h>
#include <ice_sbq_cmd.h>
//#include <virtchnl.h>
#include <ice_ethdev.h>

#define ETH_GLTSYN_ENA(_i)		(0x03000348 + ((_i) * 4))

void* dpdk_get_ice_dev(int port) {
	printf("dpdk_get_ice_dev() called");
	return ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
}

void* dpdk_get_ice_dev_hw_addr(int port) {
	printf("dpdk_get_ice_dev() called");
	return ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private)->hw_addr;
}

void ice_init_timer(int port) {
	printf("ice_init_timer(port=%i) start\n", port);
	
	u32 regval, addr;
	u8 master_idx, tmr_idx;
        struct ice_sbq_msg_input phy_msg;
	struct ice_hw *hw;
	struct ice_pf *pf;
	enum ice_status status;

	master_idx = 0;

	/**
         *  The following code is based on ice_ptp_init() in ice_ptp.c of non-DPDK ice driver.
         */

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	pf = ICE_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private);
	
	wrp32(hw, GLTSYN_SYNC_DLAY, 0);
	/* Enable master clocks */
	wrp32(hw, GLTSYN_ENA(master_idx), GLTSYN_ENA_TSYN_ENA_M);

	/* communicate with PHY */
        tmr_idx = 0; //hw->func_caps.ts_func_info.tmr_index_owned; does not exist in dpdk driver :(
	addr = ETH_GLTSYN_ENA(tmr_idx);
	phy_msg.dest_dev = 0x2;
        phy_msg.msg_addr_low = ICE_LO_WORD(addr);
        phy_msg.msg_addr_high = ICE_HI_WORD(addr);
        phy_msg.opcode = ice_sbq_msg_wr;
        phy_msg.data = GLTSYN_ENA_TSYN_ENA_M;
	printf("send message to phy: {\n dest_dev=%i, opcode=%i, msg_addr_low=%i, msg_addr_high=%i, data=%i\n }\n", phy_msg.dest_dev, phy_msg.opcode, phy_msg.msg_addr_low, phy_msg.msg_addr_high, phy_msg.data);
	status = ice_sbq_rw_reg(hw, &phy_msg);

        regval = rd32(hw, GLTSYN_STAT(master_idx));

        /* Do not touch the reserved bits and set other bits
         * to zero
         */
        regval &= 0xFFFFFF08;
        wrp32(hw, GLTSYN_STAT(master_idx), regval);

        regval = rd32(hw, GLINT_TSYN_PHY);
        /* Do not touch the reserved bits and set other bits
         * to zero
         */
        regval &= 0xFFFFFFE0;
        wrp32(hw, GLINT_TSYN_PHY, regval);

	//#define PF_SB_REM_DEV_CTL_PHY0  BIT(2)
        //if (ice_is_generic_mac(hw)) {
        //      regval = rd32(hw, PF_SB_REM_DEV_CTL);
        //      regval |= PF_SB_REM_DEV_CTL_PHY0;
        //      wr32(hw, PF_SB_REM_DEV_CTL, regval);
        //}
        /* Write the increment time value to PHY and LAN */
//status = ice_ptp_set_increment(pf, 0);
        //if (status)
        //        goto err_exit;
        
        /* Acquire the global hardware lock */
        //if (!ice_ptp_lock(pf)) {
        //        status = ICE_ERR_IN_USE;
        //        goto err_exit;
        //}

	printf("ice_init_timer(port=%i) stop\n", port);
	return;
}

//int dpdk_get_i40e_vsi_seid(int port) {
//	return I40E_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private)->main_vsi->seid;
//}

