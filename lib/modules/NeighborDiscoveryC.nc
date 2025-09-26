#include "../../includes/am_types.h"

generic configuration NeighborDiscoveryC(int channel){
    provides interface NeighborDiscovery;
}

implementation{
    components new NeighborDiscoveryP();
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new AMReceiverC(AM_PACK) as GeneralReceive;

    components new TimerMilliC() as neighborTimer;
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components RandomC as Random;
    NeighborDiscoveryP.Random -> Random;    

    components new SimpleSendC(AM_PACK);
    NeighborDiscoveryP.Sender -> SimpleSendC;

    NeighborDiscoveryP.Receive -> GeneralReceive;
}

