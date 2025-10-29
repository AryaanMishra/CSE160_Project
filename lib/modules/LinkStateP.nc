#include <Timer.h> 
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/neighborTable.h"
#include "../../includes/protocol.h"
#include "../../includes/linkstate.h"

generic module LinkStateP(){
    provides interface LinkState;
    uses interface NeighborDiscovery as ND;
    uses interface Flooding as Flood;
    uses interface Timer<TMilli> as LSATimer;
    uses interface Hashmap<route_entry_t> as RoutingTable;
    uses interface Hashmap<lsa_cache_entry_t> as LSACache;
    uses interface Hashmap<lsa_pack> as NetworkTopology;  // To store received LSAs

}

implementation{
    // State variables for the module
    uint16_t my_sequence_number = 0;    // Our LSA sequence number (increases each update)
    bool topology_ready = FALSE;        // Do we have enough LSAs to compute routes?
    uint8_t nodes_heard_from = 0;       // How many nodes have sent us LSAs?
    uint8_t expected_total_nodes = 0;   // Total nodes we expect in network
    
    //Forward Declaration of internal functions
    void build_and_send_LSA();
    bool is_newer_LSA(uint16_t node_id, uint32_t seq_num);
    void process_LSA_update(lsa_pack* lsa, uint16_t source_node, uint16_t seq_num);
    void run_dijkstra_algorithm();
    void update_routing_table_from_dijkstra();

    void build_and_send_LSA(){
        lsa_pack lsa;
        uint32_t* neighbor_keys;
        uint16_t num_active_neighbors;
        uint8_t i;

        dbg(ROUTING_CHANNEL, "NODE %u: BUILDING LSA\n", TOS_NODE_ID);

        // Get neighbor information from NeighborDiscovery module
        // Note: You'll need to add these methods to NeighborDiscovery interface
        neighbor_keys = call ND.getActiveNeighborKeys(); //getActiveNeighborKeys()?????
        num_active_neighbors = call ND.getNumActiveNeighbors();

        lsa.num_entries = (num_active_neighbors > 6) ? 6 : num_active_neighbors;

        for(i = 0; i < lsa.num_entries; i++){
            lsa.entries[i].node = neighbor_keys[i];
            lsa.entries[i].cost = call ND.getNeighborCost(neighbor_keys[i]); // Assuming uniform cost for simplicity
            dbg(ROUTING_CHANNEL, "  Neighbor: %u, Cost: %u\n", lsa.entries[i].node, lsa.entries[i].cost);
        }

        // Increment our sequence number and flood the LSA
        my_sequence_number++;
        call Flood.flood_LSA(&lsa, my_sequence_number);
        dbg(ROUTING_CHANNEL, "Node %u: Flooded LSA with seq %u\n", TOS_NODE_ID, my_sequence_number);
    }

    command void LinkState.build_and_flood_LSA() {
        build_and_send_LSA();
    }

    bool is_newer_LSA(uint16_t node_id, uint32_t seq_num) {
        lsa_cache_entry_t* cached_entry;
        if (!call LSACache.contains(node_id)) {
            return TRUE;
        }
        cached_entry = call LSACache.get(node_id);
        return (seq_num > cached_entry->sequence_number);
    }

    void process_LSA_update(lsa_pack* lsa, uint16_t source_node, uint16_t seq_num) {
        lsa_cache_entry_t new_entry;
        uint8_t i;
        bool topology_changed = FALSE;

        cache_entry.node_id = source_node;
        cache_entry.sequence_number = seq_num;
        cache_entry.timestamp = call Timer.getNow();
        call LSACache.insert(source_node, cache_entry);

        for (i = 0; i < lsa->num_entries; i++) {
            topology_changed = TRUE; 
        }
        if (topology_changed) {
            dbg(ROUTING_CHANNEL, "NODE %u: TOPOLOGY CHANGED, RUNNING DIJKSTRA\n", TOS_NODE_ID);
            run_dijkstra_algorithm();
        }
    }

    event void Flood.lsa_received(lsa_pack* lsa, uint16_t source_node, uint16_t seq_num) {
        dbg(ROUTING_CHANNEL, "NODE %u: Received LSA from node %u, seq %u\n", 
            TOS_NODE_ID, source_node, seq_num);
        
        if(is_newer_LSA(source_node, seq_num)) {
            call process_received_LSA(lsa, source_node); // Use your interface command
        } else {
            dbg(ROUTING_CHANNEL, "NODE %u: Ignoring old LSA from %u\n", 
                TOS_NODE_ID, source_node);
        }
    }
}