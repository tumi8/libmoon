
#include <rte_config.h>
#include <rte_ethdev.h>

// Ignore deprecation warnings. These are caused by ixgbe_ethdev.h, which includes the rte_security.h header.
// This header uses experimental features, which are not used in Moongen. Because of this, these warnings can be ignored.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
// This define is required, because some elements of the ixgbe_adapter struct are only optionally included.
// Without this, the structs from dpdk and libmoon do not align.
#define RTE_LIBRTE_IXGBE_BYPASS
#include <ixgbe_ethdev.h>
#pragma GCC diagnostic pop


#define NO_INCLUDE_RTE_TIME
#include "timestamping.h"
#undef NO_INCLUDE_RTE_TIME

int libmoon_ixgbe_reset_timecounters(uint32_t port_id) {
	RTE_ETH_VALID_PORTID_OR_ERR_RET(port_id, -ENODEV);
	struct rte_eth_dev* dev = &rte_eth_devices[port_id];
	struct ixgbe_adapter* adapter = (struct ixgbe_adapter*) dev->data->dev_private;
	libmoon_reset_timecounter(&adapter->systime_tc);
	libmoon_reset_timecounter(&adapter->rx_tstamp_tc);
	libmoon_reset_timecounter(&adapter->tx_tstamp_tc);
	return 0;
}
