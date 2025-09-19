#include "../../includes/am_types.h"

generic configuration NeighborDiscoveryC(int channel){
    provides interface;
}

implementation{
    components new NeighborDiscoveryP();
    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    components new TimerMillic() as neighborTimer;
    NeighborDiscoveryP.neighborTimer -> neighborTimer;

    components RandomC as random;
    NeighborDiscoveryP.random -> random;


}

