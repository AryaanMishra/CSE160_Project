#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/protocol.h"
#include "../../includes/flood_header.h"
#include "../../includes/ll_header.h"
#include "../../includes/linkstate.h"

generic module FloodingP(){
    provides interface Flooding;

    uses interface SimpleSend as Sender;
    uses interface Random;
    uses interface Hashmap<uint16_t>;
    uses interface LinkLayer;
    uses interface LinkState;
}

implementation{
    uint32_t sequenceNum = 0;

    command void Flooding.flood(lsa_pack* payload, uint8_t protocol){
        uint8_t buffer[28];
        flood_header* fh = (flood_header*)call LinkLayer.buildLLHeader(protocol, buffer, AM_BROADCAST_ADDR);
        lsa_pack* lsa_ptr;
        
        // Safety check for NULL payload
        if(payload == NULL) {
            dbg(FLOODING_CHANNEL, "NODE %u: Cannot flood NULL payload\n", TOS_NODE_ID);
            return;
        }
        
        sequenceNum++;
        fh->flood_src = TOS_NODE_ID;
        fh->seq = sequenceNum;
        fh->TTL = 30;
        
        // Copy LSA payload into the packet
        lsa_ptr = (lsa_pack*)fh->payload;
        *lsa_ptr = *payload;
        
        call Hashmap.insert(TOS_NODE_ID, sequenceNum);
        call Sender.send(*(pack*)&buffer, AM_BROADCAST_ADDR);
        dbg(FLOODING_CHANNEL, "NODE %u: STARTED FLOODING, Sequence: %u\n", TOS_NODE_ID, sequenceNum);
    }

    command message_t* Flooding.floodReceive(message_t* msg, void* payload, uint8_t len, uint8_t protocol){
        if(len==sizeof(pack)){
            ll_header* ll = (ll_header*)payload;// Get Link Layer header first
            
            // Handle regular flooding packets
            flood_header* myMsg = (flood_header*)ll->payload;
            myMsg->TTL -= 1;
            if(myMsg->TTL <= 0){
                return msg;
            }
            else{
                if(call Hashmap.contains(myMsg->flood_src)){
                    if(call Hashmap.get(myMsg->flood_src) < myMsg->seq){
                        call Hashmap.insert(myMsg->flood_src, myMsg->seq);
                        dbg(FLOODING_CHANNEL, "NODE %u: SENT A MESSAGE, Sequence: %u\n", TOS_NODE_ID, myMsg->seq);
                        call Sender.send(*(pack*)payload, AM_BROADCAST_ADDR);
                        if(protocol == PROTOCOL_LSA){
                            call LinkState.process_received_LSA((lsa_pack*)myMsg->payload, myMsg->flood_src, myMsg->seq);
                        }
                    } else{
                        dbg(FLOODING_CHANNEL, "NODE %u: DROPPED A MESSAGE\n", TOS_NODE_ID);
                        return msg;
                    }
                }else{
                    call Hashmap.insert(myMsg->flood_src, myMsg->seq);
                    call Sender.send(*(pack*)payload, AM_BROADCAST_ADDR);
                    dbg(FLOODING_CHANNEL, "NODE %u: SENT A MESSAGE, Sequence: %u\n", TOS_NODE_ID, myMsg->seq);
                    if(protocol == PROTOCOL_LSA){
                        call LinkState.process_received_LSA((lsa_pack*)myMsg->payload, myMsg->flood_src, myMsg->seq);
                    }
                }
                
            }          
            return msg;
        }
        dbg(NEIGHBOR_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

}