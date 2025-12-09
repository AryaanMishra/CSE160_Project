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
    uses interface Fixed_Point;
}

implementation {
    uint8_t sequenceNum = 0;
    table t;
    bool isSteady = FALSE;
    const uint16_t alpha = 76; //This corresponds to 0.3, have to hard code as we don't use floats
    const uint16_t fixed_1 = 256; //1
    const uint16_t thresh = 128; //30
    void updateActive();


    command void NeighborDiscovery.setSteady(){
        isSteady = TRUE;
        //dbg(NEIGHBOR_CHANNEL, "%u is steady\n", TOS_NODE_ID);
        call LinkState.build_and_flood_LSA();
    }


// Calls neighbor discovery on a timer
    command void NeighborDiscovery.findNeighbors(){
        call neighborTimer.startPeriodic(10000+ (call Random.rand16() % 300));
        call updateTimer.startPeriodic(10000+ (call Random.rand16() % 300));
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
                bool isNew = FALSE;

                if(call Hashmap.contains(ll->src)){
                    uint8_t diff;
                    uint8_t i;
                    t = call Hashmap.get(ll->src);
                    
                    diff = (uint8_t)sequenceNum - t.seq;
                    
                    if (diff > 0) { 
                        for(i = 0; i < diff - 1; i++){
                            t.integrity = call Fixed_Point.fixed_ewma_calc(0, t.integrity, alpha);
                        }
                    }
                    
                    t.integrity = call Fixed_Point.fixed_ewma_calc(fixed_1, t.integrity, alpha);
                    t.seq = sequenceNum;

                    if (t.isActive == FALSE) {
                        t.isActive = TRUE;
                        isNew = TRUE; 
                    }
                    
                    t = t; 
                }
                else {
                    t.seq = nd->seq;
                    t.isActive = TRUE;
                    t.integrity = fixed_1;
                    isNew = TRUE;
                }
                call Hashmap.insert(ll->src, t);

                // Trigger LSA if new neighbor or reactivated neighbor
                if(isNew && isSteady){
                    call LinkState.build_and_flood_LSA();
                }

            }
            else if (nd->protocol == PROTOCOL_PING){
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

//If the nodes reply/sent ratio is less than 80% it will be set to inactive
    void updateActive(){
        uint32_t* keys = call Hashmap.getKeys();
        uint16_t j;
        bool changed = FALSE;
        uint16_t size = call Hashmap.size();

        for(j = 0; j < size; j++){

            t = (call Hashmap.get(keys[j]));

            if(t.integrity < thresh && (call Hashmap.get(keys[j])).isActive == TRUE){
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
        uint16_t size = call Hashmap.size();
        uint16_t cost;
        uint16_t diff;

        updateActive();
        //dbg(NEIGHBOR_CHANNEL, "NODE %d Neigbors:\n", TOS_NODE_ID);

        for(j = 0; j < size; j++){
            t = call Hashmap.get(keys[j]);

                cost = call Fixed_Point.u_fixed_div(fixed_1, t.integrity);
                diff = sequenceNum - t.seq;
                dbg(NEIGHBOR_CHANNEL, "     NODE %d: Integrity: %d, Cost %u, Cost Fixed: %u, diff: %u, seq: %u\n", keys[j], t.integrity, call Fixed_Point.fixed_to_uint16(cost), cost, diff, sequenceNum);

        }
    }

    command uint16_t NeighborDiscovery.getCost(uint16_t id){
        table curr = call Hashmap.get(id);
        uint16_t cost = call Fixed_Point.u_fixed_div(fixed_1, curr.integrity);
        // cost = call Fixed_Point.fixed_to_uint16(cost);
        return cost;
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