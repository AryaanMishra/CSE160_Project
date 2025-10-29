#include <Timer.h> 
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/neighborTable.h"
#include "../../includes/protocol.h"
#include "../../includes/ll_header.h"
#include "../../includes/nd_header.h"


generic module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as neighborTimer;
    uses interface Random;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<table>;
    uses interface LinkLayer;
}

implementation {
    uint32_t sequenceNum = 0;
    table t;


// Calls neighbor discovery on a timer
    command void NeighborDiscovery.findNeighbors(){
        call neighborTimer.startPeriodic(30000+ (call Random.rand16() % 300));
    }

// Broadcasts a package from the source node to all neighbors
    void ping(uint16_t destination, uint8_t *payload){
        uint8_t buffer[28];
        nd_header* nd = (nd_header*)call LinkLayer.buildLLHeader(PROTOCOL_PING, buffer, destination);
        nd->protocol = PROTOCOL_PING;
        nd->seq = sequenceNum;
        call Sender.send(*(pack*)&buffer, destination);
    }
// Sends a reply to the source node
    void pingReply(uint16_t destination, uint8_t *payload){
        uint8_t buffer[28];
        nd_header* nd = (nd_header*)call LinkLayer.buildLLHeader(PROTOCOL_PINGREPLY, buffer, destination);
        nd->protocol = PROTOCOL_PINGREPLY;
        nd->seq = sequenceNum;
        call Sender.send(*(pack*)&buffer, destination);
    }

//When the task is posted it will send a package to all enighbors
    task void search(){
        sequenceNum++;
        ping(AM_BROADCAST_ADDR, "pack");
    }

// Main functionality: When a node recieves a package, if it recieved a ping is will return a ping reply, otherwise it will hash the 
//neighbor node with the node id as the key, and the monotonically increasing times that this neighbor has responded to pings. The node is set to active.

    command message_t* NeighborDiscovery.neighborReceive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack)){
            ll_header* ll = (ll_header*)payload;
            nd_header* nd = (nd_header*)ll->payload;
            if(nd->protocol == PROTOCOL_PINGREPLY){
                //dbg(NEIGHBOR_CHANNEL, "Received PINGREPLY from Node %d\n", ll->src);

                if(call Hashmap.contains(ll->src)){
                    t.seq = (call Hashmap.get(ll->src)).seq + 1;
                } else{
                    t.seq = 1;
                }
                t.isActive = TRUE;
                call Hashmap.insert(ll->src, t);

            }
            else if (nd->protocol == PROTOCOL_PING){
                //dbg(NEIGHBOR_CHANNEL, "Received PING from Node %d, sending reply\n", ll->src);
                pingReply(ll->src, "pack");  // Reply to the sender, not broadcast
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

    command uint32_t* NeighborDiscovery.getActiveNeighborKeys(){
        static uint32_t active_keys[20];
        uint32_t* all_keys = call Hashmap.getKeys();
        uint32_t i, active_count =0;
        table neighbor_info;

        updateActive();

        //filter out only active neighbors
        for(i = 0; i < call Hashmap.size() && active_count < 20; i++){
            neighbor_info = call Hashmap.get(all_keys[i]);
            if(neighbor_info.isActive == TRUE){
                active_keys[active_count] = all_keys[i];
                active_count++;
            }
        }
        return active_keys;
    }

    command uint16_t NeighborDiscovery.getNumActiveNeighbors(){
        uint32_t* all_keys = call Hashmap.getKeys();
        uint32_t i, active_count =0;
        table neighbor_info;

        updateActive();

        //count only active neighbors
        for(i = 0; i < call Hashmap.size(); i++){
            neighbor_info = call Hashmap.get(all_keys[i]);
            if(neighbor_info.isActive == TRUE){
                active_count++;
            }
        }
        return active_count;
    }

    command uint8_t NeighborDiscovery.getNeighborCost(uint16_t neighbor_id){
        uint32_t integrity;
        table neighbor_info;

        if(!call Hashmap.contains(neighbor_id)){
            return 255; // Unknown neighbor
        }

        updateActive();

        neighbor_info = call Hashmap.get(neighbor_id);
        if(!neighbor_info.isActive){
            return 255; // Inactive neighbor
        }

        integrity = (neighbor_info.seq * 100) / sequenceNum;

        if(integrity >= 95){
            return 1; // Best cost
        } else if(integrity >= 90){
            return 2; // Higher cost
        } else if(integrity >= 85){
            return 3; // Medium cost
        } else if(integrity >= 80){
            return 4; // Medium cost
        }else {
            return 5; // Lower cost
        }
    }
}