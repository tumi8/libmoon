#pragma once

// rte_time.h doesn't have include guards
#ifndef NO_INCLUDE_RTE_TIME
#include <rte_time.h>
#endif

static void libmoon_reset_timecounter(struct rte_timecounter* tc) {
	tc->nsec = 0;
	tc->nsec_frac = 0;
	tc->cycle_last = 0;
}

uint64_t get_timestamp_dynfield(struct rte_mbuf *m);
void set_timestamp_dynfield(struct rte_mbuf *m, uint64_t timestamp);
void init_timestamp_dynfield_offset();
