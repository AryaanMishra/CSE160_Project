#include "../../includes/am_types.h"
#include "../../includes/neighborTable.h"

generic configuration LinkLayerC(){
    provides interface LinkLayer;
}

implementation{
    components new LinkLayerP();
    LinkLayer = LinkLayerP.LinkLayer;

    components new AMReceiverC(AM_PACK) as GeneralReceive;
    LinkLayerP.Receive -> GeneralReceive;

    components new NeighborDiscoveryC(AM_PACK);
    LinkLayerP.ND -> NeighborDiscoveryC;

    components new FloodingC();
    LinkLayerP.Flood -> FloodingC;
}