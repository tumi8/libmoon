#include <rte_config.h>
#include <rte_ethdev.h>
#include <iavf.h>

uint64_t iavf_tx_timestamp_read_raw(int port){
    struct iavf_adapter *adapter = IAVF_DEV_PRIVATE_TO_ADAPTER(rte_eth_devices[port].data->dev_private);
	//request tx timestamp from PF
    //return iavf_get_ieee1588_tmst(adapter);
	return 0;
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