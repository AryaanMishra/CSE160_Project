#include "../../includes/packet.h"
#include "../../includes/socket.h"

generic configuration TransportC(){
    provides interface Transport;
    uses interface IP;
}
implementation{
    components new TransportP();
    Transport = TransportP.Transport;

    components RandomC as Random;
    TransportP.Random -> Random; 

    TransportP.IP = IP;

    components new QueueC(tcp_payload_t, 20) as connectionQueue;
    TransportP.connectionQueue -> connectionQueue;
}