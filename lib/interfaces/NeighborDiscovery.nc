// Neighbor discovery interface
#include "../../includes/packet.h"
#include "../../includes/neighborTable.h"

interface NeighborDiscovery {
    command void findNeighbors();
    command void printNeighbors();
    command message_t* neighborReceive(message_t* msg, void* payload, uint8_t len);
    // Note: removed getNeighborTable() - exposing internal Hashmap/interface
    // as a return value is not valid in nesC interfaces. If external
    // access to the neighbor table is required, add explicit commands
    // (e.g., getNeighbor(uint16_t id) or iterate APIs) instead.
    command uint32_t* getActiveNeighborKeys();
    command uint16_t getNumActiveNeighbors();
    command uint8_t getNeighborCost(uint16_t neighbor_id);
}