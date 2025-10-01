#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/floodTable.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/protocol.h"

generic module FloodingP(){
    provides interface Flooding;

    uses interface Receive;
    uses interface SimpleSend as Sender;
    uses interface Random;
    uses interface Hashmap<floodTable>;
}

implementation{
    uint32_t sequenceNum = 0;
    floodTable t;
    pack sendPackage;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    command void Flooding.flood(){
        sequenceNum++;
        t.seq = sequenceNum;
        t.srcNode = TOS_NODE_ID;
        call Hashmap.insert(TOS_NODE_ID, t);
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, PROTOCOL_PING, sequenceNum, "Hello World", PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack)){
            pack* myMsg=(pack*) payload;
            myMsg->TTL--;
            if(myMsg->TTL <= 0){
                return msg;
            }
            else{
                call Hashmap.insert(TOS_NODE_ID, t);
                t = call Hashmap.get(TOS_NODE_ID);
                if(call Hashmap.contains() && t.seq <= myMsg->seq){
                    t.seq = myMsg->seq;
                    call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                }
                else{
                    return msg;
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