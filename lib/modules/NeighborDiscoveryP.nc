#include <Timer.h> 
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"


generic module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as neighborTimer;
    uses interface Random;
    uses interface Receive;
    uses interface SimpleSend as Sender;
}

implementation {
    pack sendPackage;

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    command void NeighborDiscovery.findNeighbors(){
        call neighborTimer.startOneShot(100+ (call Random.rand16() % 300));
    }

    void ping(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, 15, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, destination);
    }

    void pingReply(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING Reply EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, 15, 1, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, destination);
    }

    task void search(){
        //"logic: send the msg, if somebody responds, save its id inside table."
        //call neighborTimer.startOneShot(100+ (call Random.rand16() % 300));
        ping(AM_BROADCAST_ADDR, "HELLO");
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        dbg(NEIGHBOR_CHANNEL, "NODE %d: Packet Received\n", TOS_NODE_ID);
        if(len==sizeof(pack)){
            pack* myMsg=(pack*) payload;
            if( myMsg->protocol == 1){
                dbg(FLOODING_CHANNEL, "%d is my neighbor\n", myMsg->src);
            }
            else{
                dbg(FLOODING_CHANNEL, "Recieved Message From: %d\n", myMsg->src);
                pingReply(myMsg->src, "I am a neighbor");
            }

            return msg;
        }
        dbg(FLOODING_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

    event void neighborTimer.fired(){
        post search();
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
        
    }
}