interface NeighborDiscovery {
    command void findNeighbors();
    command void printNeighbors();
    command message_t* neighborReceive(message_t* msg, void* payload, uint8_t len);
    command table getNeighborTable();
}