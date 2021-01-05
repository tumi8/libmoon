#include <rte_config.h>
#include <rte_ethdev.h> 
// required for i40e_type.h
// (structs have a different layout if left undefined....)

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

//int dpdk_get_i40e_vsi_seid(int port) {
//	return I40E_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private)->main_vsi->seid;
//}

