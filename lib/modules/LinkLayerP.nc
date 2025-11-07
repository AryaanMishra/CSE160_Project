#include <Timer.h> 
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/neighborTable.h"
#include "../../includes/protocol.h"

generic module LinkLayerP(){
    provides interface LinkLayer;

    uses interface Receive;

    uses interface NeighborDiscovery as ND;

    uses interface Flooding as Flood;

    uses interface IP as IP;
}

implementation{

    command nx_uint8_t* LinkLayer.buildLLHeader(nx_uint8_t protocol, uint8_t* buffer, nx_uint16_t dest){
        ll_header* ll = (ll_header*)buffer;
        ll->src = TOS_NODE_ID;
        ll->dest = dest;
        ll->protocol = protocol;
        return ll->payload;
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        //dbg(GENERAL_CHANNEL, "Packet Received\n");
        if(len==sizeof(pack)){
            ll_header* ll = (ll_header*)payload;
            //dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
            if(ll->protocol == PROTOCOL_PING || ll->protocol == PROTOCOL_PINGREPLY){
                call ND.neighborReceive(msg, payload, len);
            }
            else if(ll->protocol == PROTOCOL_FLOODING || ll->protocol == PROTOCOL_LSA){
                call Flood.floodReceive(msg, payload, len, ll->protocol);
            }
            else if(ll->protocol == PROTOCOL_IP || ll->protocol == PROTOCOL_IPACK){
                call IP.ipRecieve(msg, payload, len, ll->protocol);
            }

            return msg;
        }
        return msg;
    }
}