#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/protocol.h"
#include "../../includes/flood_header.h"

generic module FloodingP(){
    provides interface Flooding;

    uses interface SimpleSend as Sender;
    uses interface Random;
    uses interface Hashmap<uint16_t>;
    uses interface LinkLayer;
}

implementation{
    uint32_t sequenceNum = 0;

    command void Flooding.flood(lsa_pack* payload){
        uint8_t buffer[28];
        flood_header* fh = (flood_header*)call LinkLayer.buildLLHeader(PROTOCOL_FLOODING, buffer, AM_BROADCAST_ADDR);
        sequenceNum++;
        fh->flood_src = TOS_NODE_ID;
        fh->seq = sequenceNum;
        fh->TTL = 30;
        call Hashmap.insert(TOS_NODE_ID, sequenceNum);
        call Sender.send(*(pack*)&buffer, AM_BROADCAST_ADDR);
        dbg(FLOODING_CHANNEL, "NODE %u: STARTED FLOODING??\n", TOS_NODE_ID);
    }

    command message_t* Flooding.floodReceive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack)){
            flood_header* myMsg = (flood_header*)call LinkLayer.buildLLHeader(PROTOCOL_FLOODING, payload, AM_BROADCAST_ADDR);
            myMsg->TTL--;
            if(myMsg->TTL <= 0){
                return msg;
            }
            else{
                if(call Hashmap.contains(myMsg->flood_src)){
                    if(call Hashmap.get(myMsg->flood_src) < myMsg->seq){
                        call Hashmap.insert(myMsg->flood_src, myMsg->seq);
                        dbg(FLOODING_CHANNEL, "NODE %u: SENT A MESSAGES, Sequence: %u\n", TOS_NODE_ID, myMsg->seq);
                        call Sender.send(*(pack*)payload, AM_BROADCAST_ADDR);
                    }
                    else{
                        dbg(FLOODING_CHANNEL, "NODE %u: DROPPED A MESSAGE\n", TOS_NODE_ID);
                        return msg;
                    }
                }
                else{
                    call Hashmap.insert(myMsg->flood_src, myMsg->seq);
                    call Sender.send(*(pack*)payload, AM_BROADCAST_ADDR);
                    dbg(FLOODING_CHANNEL, "NODE %u: SENT A MESSAGE, Sequence: %u\n", TOS_NODE_ID, myMsg->seq);
                }
            }

            return msg;
        }
        dbg(NEIGHBOR_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

}