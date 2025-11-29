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

    components new TimerMilliC() as timer_wait;
    TransportP.timer_wait -> timer_wait;

    components new TimerMilliC() as send_timer;
    TransportP.send_timer -> send_timer;

    TransportP.IP = IP;

    components new QueueC(new_conn_t, 20) as connectionQueue;
    TransportP.connectionQueue -> connectionQueue;

}