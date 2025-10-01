#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/protocol.h"

generic module FloodingP(){
    provides interface Flooding;

    uses interface Receive;
    uses interface SimpleSend as Sender;
    uses interface Random;
    uses interface Hashmap<uint16_t>;
}

implementation{
    uint32_t sequenceNum = 0;
    pack sendPackage;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    command void Flooding.flood(){
        sequenceNum++;
        call Hashmap.insert(TOS_NODE_ID, sequenceNum);
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 30, PROTOCOL_FLOODING, sequenceNum, "Hello World", PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        dbg(FLOODING_CHANNEL, "NODE %u: STARTED FLOODING\n", TOS_NODE_ID);
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack)){
            pack* myMsg=(pack*) payload;
            if(myMsg->protocol != PROTOCOL_FLOODING){
                return msg;
            }
            myMsg->TTL--;
            if(myMsg->TTL <= 0){
                return msg;
            }
            else{
                if(call Hashmap.contains(myMsg->src)){
                    if(call Hashmap.get(myMsg->src) < myMsg->seq){
                        call Hashmap.insert(myMsg->src, myMsg->seq);
                        dbg(FLOODING_CHANNEL, "NODE %u: SENT A MESSAGE, Sequence: %u\n", TOS_NODE_ID, myMsg->seq);
                        call Sender.send(*myMsg, AM_BROADCAST_ADDR);
                    }
                    else{
                        dbg(FLOODING_CHANNEL, "NODE %u: DROPPED A MESSAGE\n", TOS_NODE_ID);
                        return msg;
                    }
                }
                else{
                    call Hashmap.insert(myMsg->src, sequenceNum);
                    call Sender.send(*myMsg, AM_BROADCAST_ADDR);
                    dbg(FLOODING_CHANNEL, "NODE %u: SENT A MESSAGE, Sequence: %u\n", TOS_NODE_ID, myMsg->seq);
                }
            }

            return msg;
        }
        dbg(NEIGHBOR_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }



    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
   }
}