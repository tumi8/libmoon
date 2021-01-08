#include <rte_config.h>
#include <rte_ethdev.h> 

// i40e_ethdev.h depends on lots of stuff that it doesn't include
//#define PF_DRIVER
//#include <base/i40e_register.h>
//#include <base/i40e_prototype.h>
#include <ice_type.h>
//#include <virtchnl.h>
#include <ice_ethdev.h>

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
	
	u32 regval;
	u8 master_idx;

	master_idx = 0;

	/**
         *  The following code is based on ice_ptp_init() in ice_ptp.c of non-DPDK ice driver.
         */

	struct ice_hw *hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	wr32(hw, GLTSYN_SYNC_DLAY, 0);
	/* Enable master clocks */
	wr32(hw, GLTSYN_ENA(master_idx), GLTSYN_ENA_TSYN_ENA_M);

	//status = ice_ptp_ena_phy_time_syn_ext(pf);

        regval = rd32(hw, GLTSYN_STAT(master_idx));

        /* Do not touch the reserved bits and set other bits
         * to zero
         */
        regval &= 0xFFFFFF08;
        wr32(hw, GLTSYN_STAT(master_idx), regval);

        regval = rd32(hw, GLINT_TSYN_PHY);
        /* Do not touch the reserved bits and set other bits
         * to zero
         */
        regval &= 0xFFFFFFE0;
        wr32(hw, GLINT_TSYN_PHY, regval);

	//#define PF_SB_REM_DEV_CTL_PHY0  BIT(2)
        //if (ice_is_generic_mac(hw)) {
        //      regval = rd32(hw, PF_SB_REM_DEV_CTL);
        //      regval |= PF_SB_REM_DEV_CTL_PHY0;
        //      wr32(hw, PF_SB_REM_DEV_CTL, regval);
        //}
        /* Write the increment time value to PHY and LAN */
        status = ice_ptp_set_increment(pf, 0);
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

