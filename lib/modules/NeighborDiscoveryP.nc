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
    uses interface Timer<TMilli> as updateTimer;
    uses interface Random;
    uses interface SimpleSend as Sender;
    uses interface Hashmap<table>;
    uses interface LinkLayer;
    uses interface LinkState;
}

implementation {
    uint32_t sequenceNum = 0;
    table t;
    bool isSteady = FALSE;
    void updateActive();
    command void NeighborDiscovery.setSteady(){
        isSteady = TRUE;
        //dbg(NEIGHBOR_CHANNEL, "%u is steady\n", TOS_NODE_ID);
        call LinkState.build_and_flood_LSA();
    }


// Calls neighbor discovery on a timer
    command void NeighborDiscovery.findNeighbors(){
        call neighborTimer.startPeriodic(30000+ (call Random.rand16() % 300));
        call updateTimer.startPeriodic(50000+ (call Random.rand16() % 300));
    }


    event void updateTimer.fired(){
        updateActive();
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
        ping(AM_BROADCAST_ADDR, (uint8_t*)"pack");
    }

// Main functionality: When a node recieves a package, if it recieved a ping is will return a ping reply, otherwise it will hash the 
//neighbor node with the node id as the key, and the monotonically increasing times that this neighbor has responded to pings. The node is set to active.

    command message_t* NeighborDiscovery.neighborReceive(message_t* msg, void* payload, uint8_t len){
        if(len==sizeof(pack)){
            ll_header* ll = (ll_header*)payload;
            nd_header* nd = (nd_header*)ll->payload;
            if(nd->protocol == PROTOCOL_PINGREPLY){
                //dbg(NEIGHBOR_CHANNEL, "Received PINGREPLY from Node %d\n", ll->src);
                bool wasInactive = FALSE;
                bool isNew = FALSE;

                if(call Hashmap.contains(ll->src)){
                    t.seq = (call Hashmap.get(ll->src)).seq + 1;
                    wasInactive = !(call Hashmap.get(ll->src)).isActive;
                } else{
                    t.seq = 1;
                    isNew = TRUE;
                }
                t.isActive = TRUE;
                call Hashmap.insert(ll->src, t);

                // Trigger LSA if new neighbor or reactivated neighbor
                if((isNew || wasInactive) && isSteady){
                    //dbg(NEIGHBOR_CHANNEL, "NODE %u: New/reactivated neighbor %u, triggering LSA\n", TOS_NODE_ID, ll->src);
                    call LinkState.build_and_flood_LSA();
                }

            }
            else if (nd->protocol == PROTOCOL_PING){
                //dbg(NEIGHBOR_CHANNEL, "Received PING from Node %d, sending reply\n", ll->src);
                pingReply(ll->src, (uint8_t*)"pack");  // Reply to the sender, not broadcast
            }

            return msg;
        }
       // dbg(NEIGHBOR_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

    event void neighborTimer.fired(){
        post search();
    }

//If the nodes reply/sent ration is less than 80% it will be set to inactive
    void updateActive(){
        uint32_t* keys = call Hashmap.getKeys();
        uint16_t j;
        uint32_t integrity;
        bool changed = FALSE;
        uint16_t size = call Hashmap.size();

        for(j = 0; j < size; j++){

            t.seq = (call Hashmap.get(keys[j])).seq;
            integrity = (t.seq*100) / sequenceNum;

            if(integrity < 30 && (call Hashmap.get(keys[j])).isActive == TRUE){
                t.isActive = FALSE;
                call Hashmap.insert(keys[j], t);
                changed = TRUE;
               // dbg(NEIGHBOR_CHANNEL, "NODE %u: Neighbor %u became inactive\n", TOS_NODE_ID, keys[j]);
            }
        }

        if(changed && isSteady){
            //dbg(NEIGHBOR_CHANNEL, "NODE %u: Neighbor table changed, triggering LSA\n", TOS_NODE_ID);
            call LinkState.build_and_flood_LSA();
        }
        return;
    }



//Prints the nodes neighbor and the integrity of the connection
    command void NeighborDiscovery.printNeighbors(){

        uint32_t* keys = call Hashmap.getKeys();
        uint16_t j;
        uint32_t integrity;
        uint16_t size = call Hashmap.size();

        updateActive();
        //dbg(NEIGHBOR_CHANNEL, "NODE %d Neigbors:\n", TOS_NODE_ID);

        for(j = 0; j < size; j++){
            t = call Hashmap.get(keys[j]);

            if(t.isActive == TRUE){
                integrity = (t.seq*100) / sequenceNum;
                //dbg(NEIGHBOR_CHANNEL, "     NODE %d: Integrity: %d%%\n", keys[j], integrity);
            }
        }
    }

    command uint32_t* NeighborDiscovery.getActiveNeighborKeys(){
        static uint32_t active_keys[20];
        uint32_t* all_keys = call Hashmap.getKeys();
        uint32_t i, active_count =0;
        table neighbor_info;
        uint16_t size = call Hashmap.size();

        updateActive();

        //filter out only active neighbors
        for(i = 0; i < size && active_count < 20; i++){
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
        uint16_t size = call Hashmap.size();

        updateActive();

        //count only active neighbors
        for(i = 0; i < size; i++){
            neighbor_info = call Hashmap.get(all_keys[i]);
            if(neighbor_info.isActive == TRUE){
                active_count++;
            }
        }
        return active_count;
    }

}