#include <Timer.h> 
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/neighborTable.h"


generic module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as neighborTimer;
    uses interface Random;
    uses interface Receive;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<table>;
}

implementation {
    pack sendPackage;
    int sequenceNum = 0;
    uint16_t i;
    table t;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    command void NeighborDiscovery.findNeighbors(){
        call neighborTimer.startPeriodic(30000+ (call Random.rand16() % 300));
    }

    void ping(uint16_t destination, uint8_t *payload){
        // dbg(NEIGHBOR_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, 15, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, destination);
    }

    void pingReply(uint16_t destination, uint8_t *payload){
        // dbg(NEIGHBOR_CHANNEL, "PING Reply EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, 15, 1, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, destination);
    }

    task void search(){
        //"logic: send the msg, if somebody responds, save its id inside table."
        //call neighborTimer.startOneShot(100+ (call Random.rand16() % 300));
        sequenceNum++;
        // dbg(NEIGHBOR_CHANNEL, "Sequence Number: %d\n", sequenceNum);
        ping(AM_BROADCAST_ADDR, "pack");
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        // dbg(NEIGHBOR_CHANNEL, "NODE %d: Packet Received\n", TOS_NODE_ID);
        if(len==sizeof(pack)){
            pack* myMsg=(pack*) payload;
            if( myMsg->protocol == 1){
                // dbg(NEIGHBOR_CHANNEL, "Recieved Message From: %d\n", myMsg->src);
                t.seq = (call Hashmap.get(myMsg->src)).seq + 1;
                t.isActive = TRUE;
                call Hashmap.insert(myMsg->src, t);
                call NeighborDiscovery.printNeighbors();
            }
            else{
                pingReply(myMsg->src, "pack");
            }

            return msg;
        }
        dbg(NEIGHBOR_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

    event void neighborTimer.fired(){
        post search();
    }

    void updateActive(){
        uint32_t* keys = call Hashmap.getKeys();
        uint16_t j = 0;
        uint32_t integrity;
        for(j; j < call Hashmap.size(); j++){
            t.seq = (call Hashmap.get(keys[j])).seq;
            integrity = (t.seq*100) / sequenceNum;
            if(integrity < 80){
                t.isActive = FALSE;
                call Hashmap.insert(keys[j], t);
            }
        }
        return;
    }


    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
   }


    command void NeighborDiscovery.printNeighbors(){
        uint32_t* keys = call Hashmap.getKeys();
        uint16_t j = 0;
        uint32_t integrity;
        updateActive();
        dbg(NEIGHBOR_CHANNEL, "NODE %d Neigbors:\n", TOS_NODE_ID);
        for(j; j < call Hashmap.size(); j++){
            t = call Hashmap.get(keys[j]);
            if(t.isActive == TRUE){
                integrity = (t.seq*100) / sequenceNum;
                dbg(NEIGHBOR_CHANNEL, "     NODE %d: Integrity: %d%%\n", keys[j], integrity);
            }
        }
    }
}