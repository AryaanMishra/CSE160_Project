#include "../../includes/am_types.h"
#include "../../includes/neighborTable.h"

generic configuration LinkStateC(){
    provides interface LinkState;

    uses interface NeighborDiscovery as ND;
    uses interface Hashmap<table> as NeighborTable;
    uses interface Flooding as Flood;
}

implementation{
    components new LinkStateP();
    LinkState = LinkStateP.LinkState;

    LinkStateP.ND = ND;
    LinkStateP.Flood = Flood;
    LinkStateP.Hashmap = NeighborTable;
}