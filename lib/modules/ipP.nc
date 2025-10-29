#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/neighborTable.h"
#include "../../includes/protocol.h"
#include "../../includes/ip_header.h"
#include "../../includes/ll_header.h"

generic module ipP(){
    provides interface IP;

    uses interface LinkLayer;
    uses interface LinkState;
    uses interface SimpleSend as Sender;
}

implementation{

    command void IP.buildIP(uint16_t dest){
        uint8_t buffer[28];
        uint16_t next_hop;
        ip_header* iph;
        ll_header* ll;

        // Check if route exists
        if(!call LinkState.has_route_to(dest)){
            dbg(ROUTING_CHANNEL, "NODE %u: No route to destination %u, dropping packet\n", TOS_NODE_ID, dest);
            return;
        }

        next_hop = call LinkState.get_next_hop(dest);
        dbg(ROUTING_CHANNEL, "NODE %u: Building IP packet to %u via next hop %u\n", TOS_NODE_ID, dest, next_hop);

        iph = (ip_header*)call LinkLayer.buildLLHeader(PROTOCOL_IP, buffer, next_hop);
        ll = (ll_header*)buffer;
        iph->src = TOS_NODE_ID;
        iph->dest = dest;
        iph->TTL = 30;
        call Sender.send(*(pack*)&buffer, ll->dest);
    }



    command message_t* IP.ipRecieve(message_t* msg, void* payload, uint8_t len, uint8_t protocol){
        uint16_t next_hop;
        ll_header* ll = (ll_header*)payload;
        ip_header* iph = (ip_header*)ll->payload;

        dbg(ROUTING_CHANNEL, "NODE %u: Received IP packet from %u to %u (TTL=%u)\n",
            TOS_NODE_ID, iph->src, iph->dest, iph->TTL);

        if(TOS_NODE_ID == iph->dest){
            dbg(ROUTING_CHANNEL, "NODE %u: Packet arrived at destination!\n", TOS_NODE_ID);
            return msg;
        }
        iph->TTL--;

        if(iph->TTL <= 0){
            dbg(ROUTING_CHANNEL, "NODE %u: Packet TTL expired, dropping\n", TOS_NODE_ID);
            return msg;
        }
        
        if(!call LinkState.has_route_to(iph->dest)){
            dbg(ROUTING_CHANNEL, "NODE %u: No route to %u, dropping packet\n", TOS_NODE_ID, iph->dest);
            return msg;
        }

        next_hop = call LinkState.get_next_hop(iph->dest);
        dbg(ROUTING_CHANNEL, "NODE %u: Forwarding packet to %u via next hop %u\n",
            TOS_NODE_ID, iph->dest, next_hop);

        ll->dest = next_hop;
        ll->src = TOS_NODE_ID;
        call Sender.send(*(pack*)payload, ll->dest);
        return msg;
    }
}