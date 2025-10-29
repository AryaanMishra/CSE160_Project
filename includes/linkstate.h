#ifndef LINKSTATE_H
#define LINKSTATE_H

// Routing table entry - stores how to reach each destination
typedef nx_struct route_entry {
    nx_uint16_t destination;      // Where we want to go
    nx_uint16_t next_hop;         // First hop to get there
    nx_uint8_t cost;              // Total cost to destination
    nx_uint16_t backup_next_hop;  // Alternative route (optional)
    nx_uint8_t backup_cost;       // Cost of backup route
} route_entry_t;

// LSA cache entry - prevents processing old LSA updates
typedef nx_struct lsa_cache_entry {
    nx_uint16_t node_id;          // Which node sent this LSA
    nx_uint16_t sequence_number;  // Latest seq number we've seen
    nx_uint32_t timestamp;        // When we received it
} lsa_cache_entry_t;

// Dijkstra algorithm - represents each node in the network
typedef struct dijkstra_node {
    nx_uint16_t node_id;          // Node identifier
    nx_uint8_t distance;          // Current shortest distance from source
    nx_uint16_t previous;         // Previous node in shortest path
    nx_bool visited;              // Has Dijkstra processed this node?
} dijkstra_node_t;

enum {
    MAX_NODES = 20,               // Maximum nodes in network
    INFINITE_COST = 255,          // Represents unreachable
    INVALID_NODE = 0xFFFF         // Invalid node ID
};

#endif /* LINKSTATE_H */
