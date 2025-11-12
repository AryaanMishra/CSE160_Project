#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/neighborTable.h"
#include "../../includes/protocol.h"
#include "../../includes/ip_header.h"
#include "../../includes/ll_header.h"
#include "../../includes/tcp_payload.h"

generic module ipP(){
    provides interface IP;

    uses interface LinkLayer;
    uses interface LinkState;
    uses interface SimpleSend as Sender;
    uses interface Transport;
}

implementation{

    command void IP.buildIP(uint16_t dest, uint8_t protocol, tcp_payload_t* payload){
        uint8_t buffer[28];
        uint16_t next_hop;
        ll_header* ll;
        ip_header* iph;
        tcp_payload_t* payloadPtr;

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

        iph = (ip_header*)call LinkLayer.buildLLHeader(protocol, buffer, next_hop);
        ll = (ll_header*)buffer;
        iph->src = TOS_NODE_ID;
        iph->dest = dest;
        iph->TTL = 30;

        payloadPtr = (tcp_payload_t *)iph->payload;
        *payloadPtr = *payload;

        dbg(ROUTING_CHANNEL, "NODE %u: Sending IP packet to %u via next hop %u (TTL: %u)\n",
            TOS_NODE_ID, dest, next_hop, iph->TTL);

        call Sender.send(*(pack*)&buffer, ll->dest);
    }



    command message_t* IP.ipRecieve(message_t* msg, void* payload, uint8_t len, uint8_t protocol){
        uint16_t next_hop;
        ll_header* ll = (ll_header*)payload;
        ip_header* iph = (ip_header*)ll->payload;
        error_t status;

        dbg(ROUTING_CHANNEL, "NODE %u: Received IP packet from %u to %u (TTL: %u)\n",
            TOS_NODE_ID, iph->src, iph->dest, iph->TTL);

        if(TOS_NODE_ID == iph->dest){
            if(ll->protocol == PROTOCOL_IP || ll->protocol == PROTOCOL_TCP){
                dbg(ROUTING_CHANNEL, "NODE %u: Packet arrived at destination\n", TOS_NODE_ID);
                if(ll->protocol == PROTOCOL_TCP){
                    status = call Transport.receive((tcp_payload_t*)iph->payload);
                    if(status == FAIL){
                        dbg(TRANSPORT_CHANNEL, "Packet could not be handled\n");
                    }
                }
            }
            return msg;
        }

        iph->TTL -= 1;

        if(iph->TTL <= 0){
            dbg(ROUTING_CHANNEL, "NODE %u: Packet TTL expired, dropping packet from %u to %u\n",
                TOS_NODE_ID, iph->src, iph->dest);
            return msg;
        }

        next_hop = call LinkState.get_next_hop(iph->dest);

        if(next_hop == 0 || !call LinkState.has_route_to(iph->dest)){
            dbg(ROUTING_CHANNEL, "NODE %u: No route to destination %u, dropping packet\n",
                TOS_NODE_ID, iph->dest);
            return msg;
        }

        dbg(ROUTING_CHANNEL, "NODE %u: Forwarding packet from %u to %u via next hop %u\n",
            TOS_NODE_ID, iph->src, iph->dest, next_hop);

        ll->dest = next_hop;
        ll->src = TOS_NODE_ID;

        call Sender.send(*(pack*)payload, ll->dest);

        return msg;
    }
}