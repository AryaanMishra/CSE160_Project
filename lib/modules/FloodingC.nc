#include "../../includes/am_types.h"


generic configuration FloodingC(){
    provides interface Flooding;
}

implementation{
    components new FloodingP();
    Flooding = FloodingP.Flooding;

    components new AMReceiverC(AM_PACK) as GeneralReceive;
    FloodingP.Receive -> GeneralReceive;

    components new SimpleSendC(AM_PACK);
    FloodingP.Sender -> SimpleSendC;

    components RandomC as Random;
    FloodingP.Random -> Random;

    
    components new HashmapC(floodTable, 20);
    FloodingP.Hashmap -> HashmapC;

}