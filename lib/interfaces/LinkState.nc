interface LinkState{
    // LSA Management
    command void build_and_flood_LSA();
    command void process_received_LSA(lsa_pack* lsa, uint16_t src_node);
    
    // Routing Table Access
    command uint16_t get_next_hop(uint16_t destination);
    command uint8_t get_route_cost(uint16_t destination);
    command bool has_route_to(uint16_t destination);
    
    // Dijkstra Algorithm
    command void compute_shortest_paths();
    
    // Initialization and Events
    command void start();
    event void neighbor_table_changed();
}