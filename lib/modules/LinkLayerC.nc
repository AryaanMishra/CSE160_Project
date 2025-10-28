#include "../../includes/am_types.h"
#include "../../includes/neighborTable.h"

generic configuration LinkLayerC(){
    provides interface LinkLayer;
    uses interface NeighborDiscovery as ND;
    uses interface Flooding as Flood;
}

implementation{
    components new LinkLayerP();
    LinkLayer = LinkLayerP.LinkLayer;

    components new AMReceiverC(AM_PACK) as GeneralReceive;
    LinkLayerP.Receive -> GeneralReceive;

    LinkLayerP.ND = ND;

    LinkLayerP.Flood = Flood;
}