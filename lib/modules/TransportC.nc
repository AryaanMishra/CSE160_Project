#include "../../includes/packet.h"
#include "../../includes/socket.h"

generic configuration TransportC(){
    provides interface Transport;
}
implementation{
    components new TransportP();
    Transport = TransportP.Transport;


    components new QueueC(tcp_payload_t, 20) as connectionQueue;
    TransportP.connectionQueue -> connectionQueue;
}