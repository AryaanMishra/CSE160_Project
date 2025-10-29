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


}

implementation{
    // State variables for the module
    uint16_t my_sequence_number = 0;    // Our LSA sequence number (increases each update)
    bool topology_ready = FALSE;        // Do we have enough LSAs to compute routes?
    uint8_t nodes_heard_from = 0;       // How many nodes have sent us LSAs?
    uint8_t expected_total_nodes = 0;   // Total nodes we expect in network
    uint16_t adj[20][20] = {0};
    
    //Forward Declaration of internal functions
    void build_and_send_LSA();
    bool is_newer_LSA(uint16_t node_id, uint16_t seq_num);
    void process_LSA_update(lsa_pack* lsa, uint16_t source_node, uint16_t seq_num);
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

    bool is_newer_LSA(uint16_t node_id, uint16_t seq_num) {
        lsa_cache_entry_t cached_entry;
        if (!call LSACache.contains(node_id)) {
            return TRUE;
        }
        cached_entry = call LSACache.get(node_id);
        return (seq_num > cached_entry.sequence_number);
    }

    void addEdge(uint16_t u, uint16_t v, uint8_t cost){
        adj[u][v] = cost;
        adj[v][u] = cost;
    }

    void process_LSA_update(lsa_pack* lsa, uint16_t source_node, uint16_t seq_num) {
        lsa_cache_entry_t cache_entry;
        lsa_pack stored_lsa;
        uint8_t i;

        cache_entry.node_id = source_node;
        cache_entry.sequence_number = seq_num;
        cache_entry.timestamp = 0;
        call LSACache.insert(source_node, cache_entry);

        //Create Adjanceny Matrix
    

        for (i = 0; i < lsa->num_entries; i++) {
            addEdge(source_node, lsa->entries[i].node, lsa->entries[i].cost);
        }
    }

    command void LinkState.process_received_LSA(lsa_pack* lsa, uint16_t src_node) {
        uint16_t seq_num = my_sequence_number;  // Placeholder for now
        
        dbg(ROUTING_CHANNEL, "NODE %u: Received LSA from node %u\n", TOS_NODE_ID, src_node);
        
        if(is_newer_LSA(src_node, seq_num)) {
            process_LSA_update(lsa, src_node, seq_num);
        } else {
            dbg(ROUTING_CHANNEL, "NODE %u: Ignoring old LSA from %u\n", TOS_NODE_ID, src_node);
        }
    }

    // Routing table access commands
    command uint16_t LinkState.get_next_hop(uint16_t destination) {
        route_entry_t route;
        if(call RoutingTable.contains(destination)) {
            route = call RoutingTable.get(destination);
            return route.next_hop;
        }
        return 0; // No route found
    }

    command uint8_t LinkState.get_route_cost(uint16_t destination) {
        route_entry_t route;
        if(call RoutingTable.contains(destination)) {
            route = call RoutingTable.get(destination);
            return route.cost;
        }
        return 255; // Infinite cost
    }

    command bool LinkState.has_route_to(uint16_t destination) {
        return call RoutingTable.contains(destination);
    }

    uint16_t minDistance(uint8_t dist[], bool visited[]){
        uint8_t min = 255;
        uint16_t i = 0;
        uint16_t index = 0;
        for(i = 0; i < 20; i++){
            if(visited[i] == FALSE && dist[i] <= min){
                min = dist[i];
                index = i;
            }
        }
        return index;
    }

    void dijkstra(){
        uint8_t dist[20];
        bool visited[20];
        uint16_t previous[20];
        uint16_t i;
        uint16_t j;
        uint16_t u;
        uint16_t alt;
        route_entry_t route;

        for(i = 0; i < 20; i++){
            dist[i] = 255;
            visited[i] = FALSE;
            previous[i] = 255;  // INVALID_NODE
        }
        dist[TOS_NODE_ID] = 0;

        for(i = 0; i < 19; i++){
            u = minDistance(dist, visited);
            visited[u] = TRUE;

            for(j = 0; j < 20; j++){
                if(visited[j] == FALSE && adj[u][j] != 0 && adj[u][j] != 255){
                    alt = dist[u] + adj[u][j];
                    if(alt < dist[j]){
                        dist[j] = alt;
                        previous[j] = u;
                    }
                }
            }
        }

        for(i = 0; i < 20; i++){
            if(i != TOS_NODE_ID && dist[i] != 255){
                uint16_t node = i;
                uint16_t next = i;

                while(previous[node] != TOS_NODE_ID && previous[node] != 255){
                    next = node;
                    node = previous[node];
                }

                if(previous[node] == TOS_NODE_ID){
                    route.destination = i;
                    route.next_hop = next;
                    route.cost = dist[i];
                    call RoutingTable.insert(i, route);
                    dbg(ROUTING_CHANNEL, "NODE %u: Route to %u via %u (cost %u)\n",
                        TOS_NODE_ID, i, next, dist[i]);
                }
            }
        }
    }

    command void LinkState.compute_shortest_paths() {
        dbg(ROUTING_CHANNEL, "NODE %u: Running Dijkstra algorithm\n", TOS_NODE_ID);
        dijkstra();
    }

    command void LinkState.start() {
        dbg(ROUTING_CHANNEL, "NODE %u: Starting LinkState module\n", TOS_NODE_ID);
        // Initialize and start periodic LSA updates
        call LSATimer.startPeriodic(3000000); // Send LSA every 30 seconds
    }

    event void LSATimer.fired() {
        // Periodically send our LSA
        build_and_send_LSA();
    }

    // Event for neighbor table changes
    default event void LinkState.neighbor_table_changed() {
        // Default implementation - can be overridden
    }
    
}