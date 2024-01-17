#include <rte_config.h>
#include <rte_ethdev.h> 
// required for i40e_type.h
// (structs have a different layout if left undefined....)
#define X722_SUPPORT
#define X722_A0_SUPPORT

// i40e_ethdev.h depends on lots of stuff that it doesn't include
#define PF_DRIVER
#include <base/i40e_register.h>
#include <base/i40e_prototype.h>
#include <i40e_type.h>
#include <virtchnl.h>
#include <i40e_ethdev.h>

void* dpdk_get_i40e_dev(int port) {
	return I40E_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
}

int dpdk_get_i40e_hw_port(int port) {
	struct i40e_hw* hw = I40E_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	return hw->port;
}

int dpdk_get_i40e_vsi_seid(int port) {
	return I40E_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private)->main_vsi->seid;
}

// aq link status parsing partially copied from the function "update_link_aq" in i40e_ethdev.c of DPDK 22.11
void i40e_get_link_status_workaround(int port, struct rte_eth_link* link) {
	struct i40e_hw* hw = I40E_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	struct i40e_link_status link_status;
	memset(&link_status, 0, sizeof(link_status));
	i40e_aq_get_link_info(hw, false, &link_status, NULL);

	link->link_status = link_status.link_info & I40E_AQ_LINK_UP;

	/* Parse the link status */
	switch (link_status.link_speed) {
	case I40E_LINK_SPEED_100MB:
		link->link_speed = RTE_ETH_SPEED_NUM_100M;
		break;
	case I40E_LINK_SPEED_1GB:
		link->link_speed = RTE_ETH_SPEED_NUM_1G;
		break;
	case I40E_LINK_SPEED_10GB:
		link->link_speed = RTE_ETH_SPEED_NUM_10G;
		break;
	case I40E_LINK_SPEED_20GB:
		link->link_speed = RTE_ETH_SPEED_NUM_20G;
		break;
	case I40E_LINK_SPEED_25GB:
		link->link_speed = RTE_ETH_SPEED_NUM_25G;
		break;
	case I40E_LINK_SPEED_40GB:
		link->link_speed = RTE_ETH_SPEED_NUM_40G;
		break;
	default:
		if (link->link_status)
			link->link_speed = RTE_ETH_SPEED_NUM_UNKNOWN;
		else
			link->link_speed = RTE_ETH_SPEED_NUM_NONE;
		break;
	}

	// code from i40e_dev_link_update in i40e_ethdev.c of DPDK 22.11
	link->link_duplex = RTE_ETH_LINK_FULL_DUPLEX;
	link->link_autoneg = !(rte_eth_devices[port].data->dev_conf.link_speeds & RTE_ETH_LINK_SPEED_FIXED);
}
