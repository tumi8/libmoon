#include <rte_config.h>
#include <rte_ethdev.h>
#include <iavf.h>

uint64_t iavf_tx_timestamp_read_raw(int port){
    struct iavf_adapter *adapter = IAVF_DEV_PRIVATE_TO_ADAPTER(rte_eth_devices[port].data->dev_private);
	//request tx timestamp from PF
    //return iavf_get_ieee1588_tmst(adapter);
	return 0;
}

int iavf_config_rate_limit_port(int port, uint64_t bw, bool pps){
	struct iavf_adapter *adapter = IAVF_DEV_PRIVATE_TO_ADAPTER(rte_eth_devices[port].data->dev_private);
	return 0;
	/*
	enum iavf_status ret = iavf_config_bw_limit_port(adapter, bw, pps);
	if(ret!=IAVF_SUCCESS){
		return -1;
	}
	return 0;‚
	*/
}

void iavf_config_rate_limit_queue(int port, int queue, uint64_t bw, bool pps){
	struct iavf_adapter *adapter = IAVF_DEV_PRIVATE_TO_ADAPTER(rte_eth_devices[port].data->dev_private);
	/*
	enum iavf_status ret = iavf_config_bw_limit_queue(adapter, queue, bw, pps);
	if(ret!=IAVF_SUCCESS){
		printf("Could not set max bandwidth limit for port %d and queue %d!\n", port, queue);
	}
	*/
}

bool iavf_modified_driver_detected(int port){
	struct iavf_adapter *adapter = IAVF_DEV_PRIVATE_TO_ADAPTER(rte_eth_devices[port].data->dev_private);
	//if the modified DPDK driver could not request the VF ID using 
	// a custom VF command, a wrong PF driver may be used
    //return adapter->vf.vf_id != -1;
	return false;
}

uint64_t iavf_tx_timestamps_read(int port, int slot, uint64_t* tx_prev_ts, uint64_t* tx_wraparound_ctr){
    uint64_t hw_ts = iavf_tx_timestamp_read_raw(port);

	//remove sub nanosecond part and valid bit	
	uint64_t ts = (hw_ts>>8);

	//handle TX wraparound
	if ((*tx_prev_ts) > ts) {
		(*tx_wraparound_ctr)++;	
	}
	(*tx_prev_ts) = ts;

	return ((*tx_wraparound_ctr) << 32) | ts;
}