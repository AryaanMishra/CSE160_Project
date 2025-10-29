#include "../../includes/am_types.h"
#include "../../includes/neighborTable.h"

generic configuration NeighborDiscoveryC(int channel){
    provides interface NeighborDiscovery;
    provides interface Hashmap<table> as NeighborTable;
    uses interface LinkLayer;
}

implementation{
    components new NeighborDiscoveryP();
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new TimerMilliC() as neighborTimer;
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components RandomC as Random;
    NeighborDiscoveryP.Random -> Random;    

    components new SimpleSendC(AM_PACK);
    NeighborDiscoveryP.Sender -> SimpleSendC;

    components new HashmapC(table, 20) as NeighborHashmap;
    NeighborDiscoveryP.Hashmap -> NeighborHashmap;
    NeighborTable = NeighborHashmap;

    NeighborDiscoveryP.LinkLayer = LinkLayer;

}

