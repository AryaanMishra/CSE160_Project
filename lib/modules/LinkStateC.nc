#include "../../includes/am_types.h"
#include "../../includes/neighborTable.h"

generic configuration LinkStateC{
    provides interface LinkState;

    uses interface NeighborDiscovery as ND;
    uses interface Flooding as Flood;
}

implementation{
    components new LinkStateP();
    LinkState = LinkStateP.LinkState;

    LinkStateP.ND -> ND;
    LinkStateP.Flood -> Flood;

    components new TimerMilliC() as LSATimer;
    LinkStateP.LSATimer -> LSATimer;
    
    components new HashmapC(route_entry_t, 20) as RoutingTable;
    LinkStateP.RoutingTable -> RoutingTable;
    
    components new HashmapC(lsa_cache_entry_t, 20) as LSACache;
    LinkStateP.LSACache -> LSACache;

    components new HashmapC(lsa_pack, 20) as NetworkTopology;
    LinkStateP.NetworkTopology -> NetworkTopology;
}