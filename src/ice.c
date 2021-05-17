#include <rte_config.h>
#include <rte_ethdev.h>

#include <ice_type.h>
#include <ice_common.h>
#include <ice_sbq_cmd.h>
#include <ice_ethdev.h>

// XXX start of copied (and modified) ice driver code
#define cpu_to_le16(o) rte_cpu_to_le_16(o)
#define cpu_to_le32(o) rte_cpu_to_le_32(o)
#define le32_to_cpu(c) rte_le_to_cpu_32(c)

// TODO the truth is more complicated; this was a function
#define ice_get_sbq(hw)	(&hw->adminq)

static enum ice_status ice_sbq_send_cmd(struct ice_hw *hw, struct ice_sbq_cmd_desc *desc, void *buf, u16 buf_size, struct ice_sq_cd *cd) {
	return ice_sq_send_cmd(hw, ice_get_sbq(hw), (struct ice_aq_desc *)desc, buf, buf_size, cd);
}
enum ice_status ice_sbq_rw_reg_lp(struct ice_hw *hw, struct ice_sbq_msg_input *in, bool lock) {
	struct ice_sbq_cmd_desc desc = {0};
	struct ice_sbq_msg_req msg = {0};
	enum ice_status status;
	u16 msg_len;

	msg_len = sizeof(msg);

	msg.dest_dev = in->dest_dev;
	msg.opcode = in->opcode;
	msg.flags = ICE_SBQ_MSG_FLAGS;
	msg.sbe_fbe = ICE_SBQ_MSG_SBE_FBE;
	msg.msg_addr_low = cpu_to_le16(in->msg_addr_low);
	msg.msg_addr_high = cpu_to_le32(in->msg_addr_high);

	if (in->opcode)
		msg.data = cpu_to_le32(in->data);
	else
		/* data read comes back in completion, so shorten the struct by
		 * sizeof(msg.data)
		 */
		msg_len -= sizeof(msg.data);

	desc.flags = cpu_to_le16(ICE_AQ_FLAG_RD);
	desc.opcode = cpu_to_le16(ice_sbq_opc_neigh_dev_req);
	desc.param0.cmd_len = cpu_to_le16(msg_len);
	// XXX ignore other case since we don't need it
	//if (lock)
		status = ice_sbq_send_cmd(hw, &desc, &msg, msg_len, NULL);
	//else
	//	status = ice_sbq_send_cmd_nolock(hw, &desc, &msg, msg_len, NULL);
	if (!status && !in->opcode) {
		in->data = le32_to_cpu
			(((struct ice_sbq_msg_cmpl *)&msg)->data);
	}
	return status;
}
enum ice_status ice_sbq_rw_reg(struct ice_hw *hw, struct ice_sbq_msg_input *in) {
	return ice_sbq_rw_reg_lp(hw, in, true);
}
static enum ice_status ice_ptp_send_msg_to_phy_ext(struct ice_hw *hw, struct ice_pf *pf, u8 port, struct ice_sbq_msg_input *phy_msg) {
	enum ice_status status;
	phy_msg->dest_dev = port; // valid choices: rmn_0, rmn_1, rmn_2;
	//printf("send message to phy: { dest_dev=%i, opcode=%i, msg_addr_low=%i, msg_addr_high=%i, data=%i }\n", phy_msg->dest_dev, phy_msg->opcode, phy_msg->msg_addr_low, phy_msg->msg_addr_high, phy_msg->data);
	status = ice_sbq_rw_reg(hw, phy_msg);
	if (status) { printf("PTP failed to send msg to phy %d\n", status); }
	return status;
}
static enum ice_status ice_phy_port_reg_write(struct ice_hw *hw, struct ice_pf *pf, u8 port, u32 addr, u32 val) {
	struct ice_sbq_msg_input phy_msg;
	phy_msg.msg_addr_low = ICE_LO_WORD(addr);
	phy_msg.msg_addr_high = ICE_HI_WORD(addr);
	phy_msg.opcode = ice_sbq_msg_wr;
	phy_msg.data = val;
	return ice_ptp_send_msg_to_phy_ext(hw, pf, port, &phy_msg);
}

static int ice_phy_port_reg_read(struct ice_hw *hw, struct ice_pf *pf, u8 port, u32 addr, u32 *val){
	struct ice_sbq_msg_input phy_msg;
	int err;

	phy_msg.msg_addr_low = ICE_LO_WORD(addr);
	phy_msg.msg_addr_high = ICE_HI_WORD(addr);
	phy_msg.opcode = ice_sbq_msg_rd;

	err = ice_ptp_send_msg_to_phy_ext(hw, pf, port, &phy_msg);
	if (err)
		return err;

	*val = phy_msg.data;

	return 0;
}

static int ice_phy_quad_reg_read_ext(struct ice_hw *hw, struct ice_pf *pf, u32 addr, u32 *val){
	struct ice_sbq_msg_input phy_msg;
	int err;

	phy_msg.msg_addr_low = ICE_LO_WORD(addr);
	phy_msg.msg_addr_high = ICE_HI_WORD(addr);
	phy_msg.opcode = ice_sbq_msg_rd;

	err = ice_ptp_send_msg_to_phy_ext(hw, pf, rmn_0, &phy_msg);
	if (!err)
		*val = phy_msg.data;

	return err;
}

#define BYTES_PER_IDX_ADDR_L_U		8
#define BYTES_PER_IDX_ADDR_L		4
#define TS_EXT(_a, _port, _idx) ((_a) + (0x1000 * (_port)) + ((_idx) * BYTES_PER_IDX_ADDR_L_U))
#define LOW_TX_MEMORY_BANK_START	0x03090000
#define HIGH_TX_MEMORY_BANK_START	0x03090004

// XXX end of copied (and modified) ice driver code

// adapted from "ice_ptp_tx_hwtstamp_ext" from ice driver
uint64_t ice_tx_timestamps_read_register(int port, int slot){
	struct ice_hw *hw;
	struct ice_pf *pf;
	u32 addr;
	u32 val = 0;
	u8 lport;
	int err;
	u64 ts;

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	pf = ICE_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private);
	lport = hw->port_info->lport;

	addr = TS_EXT(LOW_TX_MEMORY_BANK_START, lport, slot);
	err = ice_phy_quad_reg_read_ext(hw, pf, addr, &val);
	if (err){
		printf("Error on LOW READ; slot-%d", slot);
		//TODO:: error?
	}

	ts = val;

	addr = TS_EXT(HIGH_TX_MEMORY_BANK_START, lport, slot);
	err = ice_phy_quad_reg_read_ext(hw, pf, addr, &val);
	if (err){
		printf("Error on HIGH READ; slot-%d", slot);
		//TODO:: error?
		if(!ts){
			printf("Continue anyway?");
		}
	}

	ts |= ((u64)val) << 32;

	return ts;
}

uint64_t ice_tx_timestamps_read(int port, int slot, uint64_t* tx_prev_ts, uint64_t* tx_wraparound_ctr){
	uint64_t hw_ts = ice_tx_timestamps_read_register(port, slot);

	//remove sub nanosecond part and valid bit	
	uint64_t ts = (hw_ts>>8);

	if ((*tx_prev_ts) > ts) {
		(*tx_wraparound_ctr)++;	
	}
	(*tx_prev_ts) = ts;
	return ((*tx_wraparound_ctr) << 32) | ts;
}

uint64_t ice_read_current_timer(int port){
	u32 timeL;
	u32 timeH;
	u8 tmr_index_owned;
	struct ice_hw *hw;

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	tmr_index_owned = 0;

	// run GLTSYN_CMD_READ_TIME command
#define GLTSYN_CMD_READ_TIME		BIT(7)
#define SYNC_EXEC_CMD			0x3


	
	wr32(hw, GLTSYN_CMD, GLTSYN_CMD_READ_TIME);
	wr32(hw, GLTSYN_CMD_SYNC, SYNC_EXEC_CMD);

	//read captured time
	timeL = rd32(hw, GLTSYN_SHTIME_H(tmr_index_owned));
	timeH = rd32(hw, GLTSYN_HHTIME_L(tmr_index_owned));

	printf("LOW: %d\n",timeL);
	printf("HIGH: %d\n",timeH);

	return ((u64)timeH << 32) | timeL;
}

void ice_init_timer(int port) {
	u32 regval;
	u8 tmr_index_owned;
	struct ice_sbq_msg_input;
	struct ice_hw *hw;
	struct ice_pf *pf;

	hw = ICE_DEV_PRIVATE_TO_HW(rte_eth_devices[port].data->dev_private);
	pf = ICE_DEV_PRIVATE_TO_PF(rte_eth_devices[port].data->dev_private);

	tmr_index_owned = 0;

	wr32(hw, GLTSYN_SYNC_DLAY, 0);
	wr32(hw, GLTSYN_ENA(tmr_index_owned), GLTSYN_ENA_TSYN_ENA_M);
#define ETH_GLTSYN_ENA(_i)		(0x03000348 + ((_i) * 4))
	ice_phy_port_reg_write(hw, pf, rmn_0, ETH_GLTSYN_ENA(tmr_index_owned), GLTSYN_ENA_TSYN_ENA_M);

	// 9.7.4.3 Initializing the 1588 Timers and the INCVAL
	// 9.7.4.3 1. Read the PFTSYN_SEM.BUSY flag until it is zero (0b).
#define PFTSYN_SEM_BYTES	4
	u32 hw_lock;
	hw_lock = rd32(hw, PFTSYN_SEM + (PFTSYN_SEM_BYTES * hw->pf_id));
	hw_lock = hw_lock & PFTSYN_SEM_BUSY_M;
	if (hw_lock) { return; /* TODO pf device locked, now what? */ }

	// 9.7.4.3 2. Program the CMD registers and the shadow registers of all
	//            the relevant PHY ports that should be tied to the
	//            selected master using the Read/Write 1588 PHY sideband
	//            Admin Queue command with the following parameters (both
	//            the Tx and Rx PHY registers):
	// 9.7.4.3 2a. CMD register = INIT INCVAL + TIMER at SYNC
#define GLTSYN_CMD_INIT_TIME_INCVAL	(BIT(0) | BIT(1))
#define ETH_GLTSYN_CMD			0x03000344
	regval = GLTSYN_CMD_INIT_TIME_INCVAL;
	ice_phy_port_reg_write(hw, pf, rmn_0, ETH_GLTSYN_CMD, regval);
	// 9.7.4.3 2b. Set the SHTIME_L register (32 bits) // Equivalent to GLTSYN_SHTIME_0 of the master.
#define ETH_GLTSYN_SHTIME_0(_i)		(0x03000368 + ((_i) * 32))
	regval = 0; // shadow time, initial value of the timer
	ice_phy_port_reg_write(hw, pf, rmn_0, ETH_GLTSYN_SHTIME_0(tmr_index_owned), regval);
	// 9.7.4.3 2c. Set the SHTIME_H register (32 bits) // Equivalent to GLTSYN_SHTIME_L of the master.
#define ETH_GLTSYN_SHTIME_L(_i)		(0x0300036C + ((_i) * 32))
	regval = 0; // shadow time, initial value of the timer
	ice_phy_port_reg_write(hw, pf, rmn_0, ETH_GLTSYN_SHTIME_L(tmr_index_owned), regval);
	// 9.7.4.3 2d. Set the SHADJ_L register (32 bits) // Same as GLTSYN_SHADJ_L of the master.
#define DEFAULT_INCVAL_EXT		0x13b13b13bULL
#define TS_LOW_MASK			0xFFFFFFFF
#define ETH_GLTSYN_SHADJ_L(_i)		(0x03000378 + ((_i) * 32))
	regval = (u32)(DEFAULT_INCVAL_EXT & TS_LOW_MASK); // XXX cf. fig. 9-68 re time adjust
	ice_phy_port_reg_write(hw, pf, rmn_0, ETH_GLTSYN_SHADJ_L(tmr_index_owned), regval);
	// 9.7.4.3 2e. Set the SHADJ_H register (32 bits) // Same as GLTSYN_SHADJ_H of the master.
#define ETH_GLTSYN_SHADJ_H(_i)		(0x0300037C + ((_i) * 32))
	regval = (u32)(DEFAULT_INCVAL_EXT >> 32); // XXX cf. fig. 9-68 re time adjust
	ice_phy_port_reg_write(hw, pf, rmn_0, ETH_GLTSYN_SHADJ_H(tmr_index_owned), regval);

	// 9.7.4.3 3. Set the GLTSYN_SHTIME (0, L, and H) and GLTSYN_SHADJ (L
	//            and H) registers of the master timer in the E810.
	u64 startVal = 0;
	wr32(hw, GLTSYN_SHTIME_L(tmr_index_owned), (u32)(startVal & TS_LOW_MASK));
	wr32(hw, GLTSYN_SHTIME_H(tmr_index_owned), (u32)(startVal >> 32));
	wr32(hw, GLTSYN_SHTIME_0(tmr_index_owned), 0);

	// 9.7.4.3 4. Set the CMD to INIT INCVAL + TIMER and the SEL_MASTER as
	//            needed in the GLTSYN_CMD register in the E810. The
	//            Sel_Master signal is driven to the master and the PHYs.
	regval = GLTSYN_CMD_INIT_TIME_INCVAL;
	wr32(hw, GLTSYN_CMD, regval);

	// 9.7.4.3 5. Set the SYNC field in the GLTSYN_CMD_SYNC register to 11b.
#define SYNC_EXEC_CMD			0x3
	regval = SYNC_EXEC_CMD;
	wr32(hw, GLTSYN_CMD_SYNC, regval);
	// 9.7.4.3 5a. As a response, the E810 drives the sync signals to the
	//             masters and the PHYs.
	// 9.7.4.3 5b. The programmed values are loaded to the master timer and
	//             the PHY timers: The SHTIME registers are loaded to the
	//             TIME registers and the SHADJ registers are loaded to the
	//             INCVAL registers.
	// 9.7.4.3 5c. After the sync signals are generated, the SYNC field is
	//             auto-cleared in the GLTSYN_CMD_SYNC register.

	// 9.7.4.3 6. Clear the PFTSYN_SEM.BUSY flag, enabling other software
	//            drivers to access the 1588 logic.
	hw_lock = rd32(hw, PFTSYN_SEM + (PFTSYN_SEM_BYTES * hw->pf_id));
	hw_lock = hw_lock & ~PFTSYN_SEM_BUSY_M;
	wr32(hw, PFTSYN_SEM + (PFTSYN_SEM_BYTES * hw->pf_id), hw_lock);
	return;
}
