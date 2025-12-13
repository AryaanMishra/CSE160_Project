#include "../../includes/am_types.h"
#include "../../includes/neighborTable.h"

generic configuration NeighborDiscoveryC(int channel){
    provides interface NeighborDiscovery;
    uses interface LinkLayer;
    uses interface LinkState;
    uses interface SimpleSend as Sender;
}

implementation{
    components new NeighborDiscoveryP();
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new TimerMilliC() as neighborTimer;
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components new TimerMilliC() as updateTimer;
    NeighborDiscoveryP.updateTimer -> updateTimer;

    components RandomC as Random;
    NeighborDiscoveryP.Random -> Random;    

    NeighborDiscoveryP.Sender = Sender;

    components new HashmapC(table, 20);
    NeighborDiscoveryP.Hashmap -> HashmapC;

    components new Fixed_PointC() as Fixed_Point;
    NeighborDiscoveryP.Fixed_Point -> Fixed_Point;

    NeighborDiscoveryP.LinkLayer = LinkLayer;
    NeighborDiscoveryP.LinkState = LinkState;


}

