#ifndef MG_RING_H
#define MG_RING_H

#include <rte_config.h>
#include <rte_common.h>
#include <rte_ring.h>

#ifdef __cplusplus
extern "C" {
#endif

  struct rte_ring* create_ring(uint32_t count, int32_t socket);
  int ring_enqueue(struct rte_ring* r, void* const* obj, int n);
  int ring_dequeue(struct rte_ring* r, void** obj, int n);
  int ring_dequeue_single(struct rte_ring* r, void** obj);
  int ring_count(struct rte_ring* r);
  int my_ring_sc_dequeue(struct rte_ring* r, void** obj_p);
  unsigned int my_ring_sc_dequeue_bulk(struct rte_ring* r, void** obj_p, unsigned int n, unsigned int* available);
#ifdef __cplusplus
}
#endif

#endif
