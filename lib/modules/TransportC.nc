<<<<<<< HEAD
#include "../../includes/transport_header.h"
#include "../../includes/packet.h"

configuration TransportC {
    provides interface Transport;
}

implementation {
    components TransportP;
    components new SimpleSendC(AM_PACK) as SendC;
    components new TimerMilliC() as Timer0;
    components new TimerMilliC() as Timer1;
    components new TimerMilliC() as Timer2;
    components new TimerMilliC() as Timer3;
    components new TimerMilliC() as Timer4;
    components new TimerMilliC() as Timer5;
    components new TimerMilliC() as Timer6;
    components new TimerMilliC() as Timer7;
    components new TimerMilliC() as Timer8;
    components new TimerMilliC() as Timer9;

    Transport = TransportP;
    TransportP.SimpleSend -> SendC;
    TransportP.RetransmitTimer[0] -> Timer0;
    TransportP.RetransmitTimer[1] -> Timer1;
    TransportP.RetransmitTimer[2] -> Timer2;
    TransportP.RetransmitTimer[3] -> Timer3;
    TransportP.RetransmitTimer[4] -> Timer4;
    TransportP.RetransmitTimer[5] -> Timer5;
    TransportP.RetransmitTimer[6] -> Timer6;
    TransportP.RetransmitTimer[7] -> Timer7;
    TransportP.RetransmitTimer[8] -> Timer8;
    TransportP.RetransmitTimer[9] -> Timer9;
}
=======
configuration TransportC {
    provides interface Transport;
}
implementation {
    components TransportP;
    components new SimpleSendC(AM_PACK) as SimpleSend;
    components new TimerMilliC() as RetransmitTimer0;
    components new TimerMilliC() as RetransmitTimer1;
    
    Transport = TransportP.Transport;
    
    TransportP.SimpleSend -> SimpleSend;
    TransportP.RetransmitTimer0 -> RetransmitTimer0;
    TransportP.RetransmitTimer1 -> RetransmitTimer1;
}
>>>>>>> 04eaa24aae3f71d24f7c1c3dc07b9343b245b8d2
