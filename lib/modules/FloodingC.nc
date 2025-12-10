#include "../../includes/am_types.h"


generic configuration FloodingC(){
    provides interface Flooding;
    uses interface LinkLayer;
    uses interface LinkState;
    uses interface NeighborDiscovery as ND;
}

implementation{
    components new FloodingP();
    Flooding = FloodingP.Flooding;

    components new SimpleSendC(AM_PACK);
    FloodingP.Sender -> SimpleSendC;

    components RandomC as Random;
    FloodingP.Random -> Random;

    
    components new HashmapC(uint16_t, 20);
    FloodingP.Hashmap -> HashmapC;

    FloodingP.LinkLayer = LinkLayer;
    FloodingP.LinkState = LinkState;
    FloodingP.ND = ND;

}