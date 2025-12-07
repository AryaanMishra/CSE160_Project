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

    components new TimerMilliC() as retransmit_timer;
    TransportP.retransmit_timer -> retransmit_timer;

    components new TimerMilliC() as send_timer;
    TransportP.send_timer -> send_timer;

    components new QueueC(packet_send_t, 100) as resend_queue;
    TransportP.resend_queue -> resend_queue;

    TransportP.IP = IP;

    components new QueueC(new_conn_t, 20) as connectionQueue;
    TransportP.connectionQueue -> connectionQueue;

}