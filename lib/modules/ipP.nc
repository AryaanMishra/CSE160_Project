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
        ll_header* ll;
        ip_header* iph;

        // Check if we have a route to the destination
        if(!call LinkState.has_route_to(dest)){
            dbg(ROUTING_CHANNEL, "NODE %u: No route to destination %u, cannot send packet\n",
                TOS_NODE_ID, dest);
            return;
        }

        next_hop = call LinkState.get_next_hop(dest);

        if(next_hop == 0){
            dbg(ROUTING_CHANNEL, "NODE %u: Invalid next hop for destination %u\n",
                TOS_NODE_ID, dest);
            return;
        }

        // Build IP packet
        iph = (ip_header*)call LinkLayer.buildLLHeader(PROTOCOL_IP, buffer, next_hop);
        ll = (ll_header*)buffer;
        iph->src = TOS_NODE_ID;
        iph->dest = dest;
        iph->TTL = 30;

        dbg(ROUTING_CHANNEL, "NODE %u: Sending IP packet to %u via next hop %u (TTL: %u)\n",
            TOS_NODE_ID, dest, next_hop, iph->TTL);

        call Sender.send(*(pack*)&buffer, ll->dest);
    }



    command message_t* IP.ipRecieve(message_t* msg, void* payload, uint8_t len, uint8_t protocol){
        uint16_t next_hop;
        ll_header* ll = (ll_header*)payload;
        ip_header* iph = (ip_header*)ll->payload;

        dbg(ROUTING_CHANNEL, "NODE %u: Received IP packet from %u to %u (TTL: %u)\n",
            TOS_NODE_ID, iph->src, iph->dest, iph->TTL);

        // Check if packet is for us
        if(TOS_NODE_ID == iph->dest){
            dbg(ROUTING_CHANNEL, "NODE %u: Packet arrived at destination\n", TOS_NODE_ID);
            return msg;
        }

        // Decrement TTL
        iph->TTL--;

        // Check TTL
        if(iph->TTL <= 0){
            dbg(ROUTING_CHANNEL, "NODE %u: Packet TTL expired, dropping packet from %u to %u\n",
                TOS_NODE_ID, iph->src, iph->dest);
            return msg;
        }

        // Forward packet - get next hop from routing table
        next_hop = call LinkState.get_next_hop(iph->dest);

        if(next_hop == 0 || !call LinkState.has_route_to(iph->dest)){
            dbg(ROUTING_CHANNEL, "NODE %u: No route to destination %u, dropping packet\n",
                TOS_NODE_ID, iph->dest);
            return msg;
        }

        dbg(ROUTING_CHANNEL, "NODE %u: Forwarding packet from %u to %u via next hop %u\n",
            TOS_NODE_ID, iph->src, iph->dest, next_hop);

        // Update link layer header for forwarding
        ll->dest = next_hop;
        ll->src = TOS_NODE_ID;

        // Forward the packet
        call Sender.send(*(pack*)payload, ll->dest);

        return msg;
    }
}