#include <Timer.h> 
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/neighborTable.h"
#include "../../includes/protocol.h"
#include "../../includes/ip_header.h"
#include "../../includes/nd_header.h"

generic module ipP(){
    provides implementation ip;
}

implementation{

    

    command message_t* ip.ipRecieve(message_t* msg, void* payload, uint8_t len){
        ll_header* ll = (ll_header*)payload;
        ip_header* iph = (ip_header*)ll->payload;
        iph->TTL--;
        if(TOS_NODE_ID == iph->src){
            dbg(ROUTING_CHANNEL, "Your packet has arrived at %d", TOS_NODE_ID);
            return msg;
        }
        else if(iph->TTL < 0){
            dbg(ROUTING_CHANNEL, "Your packet failed to arrive, last node was %d", TOS_NODE_ID);
        }
        else{
            
        }
    }
}