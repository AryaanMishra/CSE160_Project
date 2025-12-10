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
    uses interface NeighborDiscovery as ND;
}

implementation{
    uint32_t sequenceNum = 0;

    command void Flooding.flood(lsa_pack* payload, uint8_t protocol){
        uint8_t buffer[28];
        flood_header* fh = (flood_header*)call LinkLayer.buildLLHeader(protocol, buffer, AM_BROADCAST_ADDR);
        lsa_pack* lsa_ptr;
        
        // Safety check for NULL payload
        if(payload == NULL) {
           // dbg(FLOODING_CHANNEL, "NODE %u: Cannot flood NULL payload\n", TOS_NODE_ID);
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
        //dbg(FLOODING_CHANNEL, "NODE %u: STARTED FLOODING, Sequence: %u\n", TOS_NODE_ID, sequenceNum);
    }

    void forward_pack(pack* payload, uint16_t src){
        uint32_t* neighbor_keys = call ND.getActiveNeighborKeys();
        uint16_t num_active_neighbors = call ND.getNumActiveNeighbors();
        uint16_t i;
        for(i = 0; i < num_active_neighbors; i++){
            if(neighbor_keys[i] != src){
                call Sender.send(*payload, neighbor_keys[i]);
            }
        }
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
                        forward_pack((pack*)payload, ll->src);
                        if(protocol == PROTOCOL_LINKSTATE){
                            call LinkState.process_received_LSA((lsa_pack*)myMsg->payload, myMsg->flood_src, myMsg->seq);
                        }
                    } else{
                        return msg;
                    }
                }else{
                    call Hashmap.insert(myMsg->flood_src, myMsg->seq);
                    forward_pack((pack*)payload, ll->src);
                    if(protocol == PROTOCOL_LINKSTATE){
                        call LinkState.process_received_LSA((lsa_pack*)myMsg->payload, myMsg->flood_src, myMsg->seq);
                    }
                }
                
            }          
            return msg;
        }
        //dbg(NEIGHBOR_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

}