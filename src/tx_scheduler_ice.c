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

// start of copied code from ice_sched.c
/**
 * ice_aqc_send_sched_elem_cmd - send scheduling elements cmd
 * @hw: pointer to the HW struct
 * @cmd_opc: cmd opcode
 * @elems_req: number of elements to request
 * @buf: pointer to buffer
 * @buf_size: buffer size in bytes
 * @elems_resp: returns total number of elements response
 * @cd: pointer to command details structure or NULL
 *
 * This function sends a scheduling elements cmd (cmd_opc)
 */
static enum ice_status
ice_aqc_send_sched_elem_cmd(struct ice_hw *hw, enum ice_adminq_opc cmd_opc,
			    u16 elems_req, void *buf, u16 buf_size,
			    u16 *elems_resp, struct ice_sq_cd *cd)
{
	struct ice_aqc_sched_elem_cmd *cmd;
	struct ice_aq_desc desc;
	enum ice_status status;

	cmd = &desc.params.sched_elem_cmd;
	ice_fill_dflt_direct_cmd_desc(&desc, cmd_opc);
	cmd->num_elem_req = CPU_TO_LE16(elems_req);
	desc.flags |= CPU_TO_LE16(ICE_AQ_FLAG_RD);
	status = ice_aq_send_cmd(hw, &desc, buf, buf_size, cd);
	if (!status && elems_resp)
		*elems_resp = LE16_TO_CPU(cmd->num_elem_resp);

	return status;
}

/**
 * ice_aq_cfg_sched_elems - configures scheduler elements
 * @hw: pointer to the HW struct
 * @elems_req: number of elements to configure
 * @buf: pointer to buffer
 * @buf_size: buffer size in bytes
 * @elems_cfgd: returns total number of elements configured
 * @cd: pointer to command details structure or NULL
 *
 * Configure scheduling elements (0x0403)
 */
static enum ice_status
ice_aq_cfg_sched_elems(struct ice_hw *hw, u16 elems_req,
		       struct ice_aqc_txsched_elem_data *buf, u16 buf_size,
		       u16 *elems_cfgd, struct ice_sq_cd *cd)
{
	return ice_aqc_send_sched_elem_cmd(hw, ice_aqc_opc_cfg_sched_elems,
					   elems_req, (void *)buf, buf_size,
					   elems_cfgd, cd);
}

/**
 * ice_sched_update_elem - update element
 * @hw: pointer to the HW struct
 * @node: pointer to node
 * @info: node info to update
 *
 * Update the HW DB, and local SW DB of node. Update the scheduling
 * parameters of node from argument info data buffer (Info->data buf) and
 * returns success or error on config sched element failure. The caller
 * needs to hold scheduler lock.
 */
static enum ice_status
ice_sched_update_elem(struct ice_hw *hw, struct ice_sched_node *node,
		      struct ice_aqc_txsched_elem_data *info)
{
	struct ice_aqc_txsched_elem_data buf;
	enum ice_status status;
	u16 elem_cfgd = 0;
	u16 num_elems = 1;

	buf = *info;
	/* For TC nodes, CIR config is not supported */
	if (node->info.data.elem_type == ICE_AQC_ELEM_TYPE_TC)
		buf.data.valid_sections &= ~ICE_AQC_ELEM_VALID_CIR;
	/* Parent TEID is reserved field in this aq call */
	buf.parent_teid = 0;
	/* Element type is reserved field in this aq call */
	buf.data.elem_type = 0;
	/* Flags is reserved field in this aq call */
	buf.data.flags = 0;

	/* Update HW DB */
	/* Configure element node */
	status = ice_aq_cfg_sched_elems(hw, num_elems, &buf, sizeof(buf),
					&elem_cfgd, NULL);
	if (status || elem_cfgd != num_elems) {
		ice_debug(hw, ICE_DBG_SCHED, "Config sched elem error\n");
		return ICE_ERR_CFG;
	}

	/* Config success case */
	/* Now update local SW DB */
	/* Only copy the data portion of info buffer */
	node->info.data = info->data;
	return status;
}

/**
 * ice_sched_get_first_node - get the first node of the given layer
 * @pi: port information structure
 * @parent: pointer the base node of the subtree
 * @layer: layer number
 *
 * This function retrieves the first node of the given layer from the subtree
 */
static struct ice_sched_node *
ice_sched_get_first_node(struct ice_port_info *pi,
			 struct ice_sched_node *parent, u8 layer)
{
	return pi->sib_head[parent->tc_num][layer];
}

/**
 * ice_sched_get_agg_layer - get the current aggregator layer number
 * @hw: pointer to the HW struct
 *
 * This function returns the current aggregator layer number
 */
static u8 ice_sched_get_agg_layer(struct ice_hw *hw)
{
	/* Num Layers       aggregator layer
	 *     9               4
	 *     7 or less       sw_entry_point_layer
	 */
	/* calculate the aggregator layer based on number of layers. */
	if (hw->num_tx_sched_layers > ICE_AGG_LAYER_OFFSET + 1) {
		u8 layer = hw->num_tx_sched_layers - ICE_AGG_LAYER_OFFSET;

		if (layer > hw->sw_entry_point_layer)
			return layer;
	}
	return hw->sw_entry_point_layer;
}

/**
 * ice_sched_get_agg_node - Get an aggregator node based on aggregator ID
 * @pi: pointer to the port information structure
 * @tc_node: pointer to the TC node
 * @agg_id: aggregator ID
 *
 * This function retrieves an aggregator node for a given aggregator ID from
 * a given TC branch
 */
static struct ice_sched_node *
ice_sched_get_agg_node(struct ice_port_info *pi, struct ice_sched_node *tc_node,
		       u32 agg_id)
{
	struct ice_sched_node *node;
	struct ice_hw *hw = pi->hw;
	u8 agg_layer;

	if (!hw)
		return NULL;
	agg_layer = ice_sched_get_agg_layer(hw);
	node = ice_sched_get_first_node(pi, tc_node, agg_layer);

	/* Check whether it already exists */
	while (node) {
		if (node->agg_id == agg_id)
			return node;
		node = node->sibling;
	}

	return node;
}

/**
 * ice_sched_get_node_by_id_type - get node from ID type
 * @pi: port information structure
 * @id: identifier
 * @agg_type: type of aggregator
 * @tc: traffic class
 *
 * This function returns node identified by ID of type aggregator, and
 * based on traffic class (TC). This function needs to be called with
 * the scheduler lock held.
 */
static struct ice_sched_node *
ice_sched_get_node_by_id_type(struct ice_port_info *pi, u32 id,
			      enum ice_agg_type agg_type, u8 tc)
{
	struct ice_sched_node *node = NULL;
	struct ice_sched_node *child_node;

	switch (agg_type) {
	case ICE_AGG_TYPE_VSI: {
		struct ice_vsi_ctx *vsi_ctx;
		u16 vsi_handle = (u16)id;

		if (!ice_is_vsi_valid(pi->hw, vsi_handle))
			break;
		/* Get sched_vsi_info */
		vsi_ctx = ice_get_vsi_ctx(pi->hw, vsi_handle);
		if (!vsi_ctx)
			break;
		node = vsi_ctx->sched.vsi_node[tc];
		break;
	}

	case ICE_AGG_TYPE_AGG: {
		struct ice_sched_node *tc_node;

		tc_node = ice_sched_get_tc_node(pi, tc);
		if (tc_node)
			node = ice_sched_get_agg_node(pi, tc_node, id);
		break;
	}

	case ICE_AGG_TYPE_Q:
		/* The current implementation allows single queue to modify */
		node = ice_sched_get_node(pi, id);
		break;

	case ICE_AGG_TYPE_QG:
		/* The current implementation allows single qg to modify */
		child_node = ice_sched_get_node(pi, id);
		if (!child_node)
			break;
		node = child_node->parent;
		break;

	default:
		break;
	}

	return node;
}

// end of copied code from ice_sched.c

enum ice_status ice_get_port_tx_scheduler_elem(int port, struct ice_aqc_txsched_elem_data* buf, struct ice_sched_node **node){
	struct ice_hw *hw;
	struct ice_pf *pf;
	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	pf = ICE_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private);

	struct ice_port_info *pi = hw->port_info;

	// start of copied and modified code from "ice_sched_set_node_bw_lmt_per_tc" in ice_sched.c
	enum ice_status status = ICE_ERR_PARAM;

	if (!pi)
		return status;

	ice_acquire_lock(&pi->sched_lock);
	(*node) = ice_sched_get_node_by_id_type(pi, pf->main_vsi->idx, ICE_AGG_TYPE_VSI, 0);
	if (!(*node)) {
		ice_debug(pi->hw, ICE_DBG_SCHED, "Wrong id, agg type, or tc\n");
		goto exit_set_node_bw_lmt_per_tc;
	}
	
	*buf = (*node)->info;
	status = ICE_SUCCESS;

exit_set_node_bw_lmt_per_tc:
	ice_release_lock(&pi->sched_lock);
	return status;
	// end of copied and modified code from "ice_sched_set_node_bw_lmt_per_tc" in ice_sched.c
} 

enum ice_status ice_get_queue_tx_scheduler_elem(int port, int queue, struct ice_aqc_txsched_elem_data* buf, struct ice_sched_node **node){
	struct ice_hw *hw;
	struct ice_pf *pf;
	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	pf = ICE_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private);

	struct ice_port_info *pi = hw->port_info;

	// start of copied and modified code from "ice_sched_set_q_bw_lmt" in ice_sched.c
	enum ice_status status = ICE_ERR_PARAM;
	struct ice_q_ctx *q_ctx;

	if (!ice_is_vsi_valid(pi->hw, pf->main_vsi->idx))
		return ICE_ERR_PARAM;
	ice_acquire_lock(&pi->sched_lock);
	q_ctx = ice_get_lan_q_ctx(pi->hw, pf->main_vsi->idx, 0, queue);
	if (!q_ctx)
		goto exit_q_bw_lmt;
	*node = ice_sched_find_node_by_teid(pi->root, q_ctx->q_teid);
	if (!(*node)) {
		ice_debug(pi->hw, ICE_DBG_SCHED, "Wrong q_teid\n");
		goto exit_q_bw_lmt;
	}

	/* Return error if it is not a leaf node */
	if ((*node)->info.data.elem_type != ICE_AQC_ELEM_TYPE_LEAF)
		goto exit_q_bw_lmt;

	*buf = (*node)->info;
	status = ICE_SUCCESS;

exit_q_bw_lmt:
	ice_release_lock(&pi->sched_lock);
	return status;
	// end of copied and modified code from "ice_sched_set_q_bw_lmt" in ice_sched.c
} 

void ice_tx_sched_set_pps_port(int port, bool pps){
	enum ice_status status;
	struct ice_aqc_txsched_elem_data buf;
	struct ice_aqc_txsched_elem *data;
	struct ice_sched_node *node;
	struct ice_hw *hw;

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);

	status = ice_get_port_tx_scheduler_elem(port, &buf, &node);

	if(status!=0){
		printf("ice: could not set PPS scheduling on device %d!\n", port);
		return;
	}

	data = &buf.data;

	if(pps){
		data->generic |= ICE_AQC_ELEM_GENERIC_MODE_M;
	}else{
		data->generic &= ~(ICE_AQC_ELEM_GENERIC_MODE_M);
	}
	
	status = ice_sched_update_elem(hw, node, &buf);

	if(status!=0){
		printf("ice: could not set PPS scheduling on device %d!\n", port);
		return;
	}
}

void ice_tx_sched_set_pps_queue(int port, int queue, bool pps){
	enum ice_status status;
	struct ice_aqc_txsched_elem_data buf;
	struct ice_aqc_txsched_elem *data;
	struct ice_sched_node *node;
	struct ice_hw *hw;

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);

	status = ice_get_queue_tx_scheduler_elem(port, queue, &buf, &node);

	if(status!=0){
		printf("ice: could not set PPS scheduling on device %d for queue %d!\n", port, queue);
		return;
	}

	data = &buf.data;

	if(pps){
		data->generic |= ICE_AQC_ELEM_GENERIC_MODE_M;
	}else{
		data->generic &= ~(ICE_AQC_ELEM_GENERIC_MODE_M);
	}
	
	status = ice_sched_update_elem(hw, node, &buf);

	if(status!=0){
		printf("ice: could not set PPS scheduling on device %d for queue %d!\n", port, queue);
		return;
	}
}