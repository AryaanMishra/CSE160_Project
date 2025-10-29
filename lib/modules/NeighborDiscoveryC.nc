#include "../../includes/am_types.h"
#include "../../includes/neighborTable.h"

generic configuration NeighborDiscoveryC(int channel){
    provides interface NeighborDiscovery;
    uses interface LinkLayer;
    uses interface LinkState;
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

    components new HashmapC(table, 20);
    NeighborDiscoveryP.Hashmap -> HashmapC;

    NeighborDiscoveryP.LinkLayer = LinkLayer;
    NeighborDiscoveryP.LinkState = LinkState;


}

