#include "../../includes/am_types.h"
#include "../../includes/neighborTable.h"

generic configuration LinkStateC{
    provides interface LinkState;

    uses interface NeighborDiscovery as ND;
    uses interface Flooding as Flood;
}

implementation{
    components new LinkStateC();
    LinkState = LinkStateP.LinkState;

    LinkLayer.ND -> ND;
    LinkLayer.Flood -> Flood;
}