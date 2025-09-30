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
    table t;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

// Calls neighbor discovery on a timer
    command void NeighborDiscovery.findNeighbors(){
        call neighborTimer.startPeriodic(30000+ (call Random.rand16() % 300));
    }

// Broadcasts a package from the source node to all neighbors
    void ping(uint16_t destination, uint8_t *payload){
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, sequenceNum, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, destination);
    }
// Sends a reply to the source node
    void pingReply(uint16_t destination, uint8_t *payload){
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PINGREPLY, sequenceNum, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, destination);
    }

//When the task is posted it will send a package to all enighbors
    task void search(){
        sequenceNum++;
        ping(AM_BROADCAST_ADDR, "pack");
    }

// Main functionality: When a node recieves a package, if it recieved a ping is will return a ping reply, otherwise it will hash the 
//neighbor node with the node id as the key, and the monotonically increasing times that this neighbor has responded to pings. The node is set to active.

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack)){
            pack* myMsg=(pack*) payload;
            if( myMsg->protocol == PROTOCOL_PINGREPLY){

                // dbg(NEIGHBOR_CHANNEL, "Recieved Message From: %d\n", myMsg->src);

                t.seq = (call Hashmap.get(myMsg->src)).seq + 1;
                t.isActive = TRUE;
                call Hashmap.insert(myMsg->src, t);
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

//If the nodes reply/sent ration is less than 80% it will be set to inactive
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

//Prints the nodes neighbor and the integrity of the connection
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