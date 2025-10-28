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
}

implementation{

    command void LinkLayer.testing(){
        dbg(NEIGHBOR_CHANNEL, "is this working");
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        //dbg(GENERAL_CHANNEL, "Packet Received\n");
        if(len==sizeof(pack)){
            default_pack* myMsg=(default_pack*) payload;
            dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
            if(myMsg->protocol == PROTOCOL_PING || myMsg->protocol == PROTOCOL_PINGREPLY){
                call ND.neighborReceive(msg, payload, len);
            }
            else if(myMsg->protocol == PROTOCOL_FLOODING){
                call Flood.floodReceive(msg, payload, len);
            }

            return msg;
        }
        return msg;
    }
}