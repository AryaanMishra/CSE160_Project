// 1. Node A creates a pack with src=A, dest=B or AM_BROADCAST_ADDR, TTL=0 (or not set).
// 2. It calls call Flooding.flood(msg, AM_BROADCAST_ADDR).
// 3. Flooding.flood() sets seq=1 (since src==TOS_NODE_ID) and TTL=15 (MAX_TTL) and sends it.
// 4. Node B receives the message:
//      - receive() sees p->src == A, p->seq == 1. Cache doesn't have A: insert A->1.
//      - If dest==B, it logs "Packet for me".
//      - Decrement TTL to 14 and rebroadcast.
// 5. Node C receives the rebroadcast from B:
//      - It sees A->1 for the first time, accepts and rebroadcasts with TTL 13.
// 6. If C later receives the same packet via another path, it will compare seq to cache and drop it because 1 <= maxSeq.


#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include <string.h>

generic module FloodingP(){
    provides interface Flooding;

    uses interface Receive;
    uses interface SimpleSend as Sender;
    uses interface Random;
    uses interface Timer<TMilli> as activeTimer;
}

implementation{
    // Simple cache: for each possible origin node, record largest seq seen
    enum { MAX_NODES = 64 };
    typedef struct {
        uint16_t nodeId;
        uint16_t maxSeq;
        bool used;
    } seqEntry_t;
    uint32_t seq = 0;
    seqEntry_t seqCache[MAX_NODES];

    // searches the cache: If it finds an entry with nodeId == node, it returns its index ifnot it returns the first free slot index
    int findEntry(uint16_t node){
        int freeIdx = -1;
        int i;
        for(i=0;i<MAX_NODES;i++){
            if(seqCache[i].used && seqCache[i].nodeId == node){
                return i;
            }
            if(!seqCache[i].used){
                freeIdx = i;
                break;
            } 
        }
        return freeIdx; // may be -1 if full
    }


    command void Flooding.flood(pack msg, uint16_t dest){
        // declare locals first (C89 requirement)
        error_t err;

        // If the packet was created on this node, the module assigns it a sequence number which makes new packets unique.
        if(msg.src == TOS_NODE_ID){
            seq++;
            msg.seq = seq;
        }

        // Set initial TTL if not set or zero
        if(msg.TTL == 0) msg.TTL = MAX_TTL;

        // dest is typically AM_BROADCAST_ADDR for a broadcast, or a specific node id if you wanted to limit. (hop-by-hop link layer will use dest)
        err = call Sender.send(msg, dest);
        if(err != SUCCESS){
            dbg(FLOODING_CHANNEL, "Send failed: %d\n", err);
        } else {
            dbg(FLOODING_CHANNEL, "Sent flood from %hu seq %hu to %hu (TTL=%hhu)\n", msg.src, msg.seq, dest, msg.TTL);
        }

        // Start a short timer to print active nodes after flooding spreads
        call activeTimer.startPeriodic(200);
    }

    // Timer fired: evaluate and print active nodes
    event void activeTimer.fired(){
        // determine global max seq across origins
        int i;

        // threshold for active neighbor
        const uint16_t THRESH = 5;

        dbg(FLOODING_CHANNEL, "Active nodes (within %u of global max %u):\n", THRESH, seq);
        for(i=0;i<MAX_NODES;i++){
            if(seqCache[i].used){
                uint16_t diff = seq - seqCache[i].maxSeq;
                if(diff <= THRESH){
                    dbg(FLOODING_CHANNEL, "  Node %hu (maxSeq=%hu, diff=%hu)\n", seqCache[i].nodeId, seqCache[i].maxSeq, diff);
                }
            }
        }
    }

    // When a packet is received, decide whether to rebroadcast
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
        // declare locals first (C89)
        pack* p;
        int idx;
        error_t err;
        pack out;

        dbg(FLOODING_CHANNEL, "Packet Received\n");
        if(len != sizeof(pack)){
            dbg(FLOODING_CHANNEL, "Unknown Packet Type %d\n", len);
            return msg;
        }

        //Cast the payload to lets us access the header fields like p->src, p->seq, p->TTL
        p = (pack*) payload;

        // Check cache: if we've seen this (origin, seq) already, drop it
        idx = findEntry(p->src);
        if(idx >= 0 && seqCache[idx].used){
            //old packeet = drop
            if(p->seq <= seqCache[idx].maxSeq){
                dbg(FLOODING_CHANNEL, "Duplicate/old packet from %hu seq %hu (maxSeen=%hu)\n", p->src, p->seq, seqCache[idx].maxSeq);
                return msg;
            }
            // new sequence, update
            seqCache[idx].maxSeq = p->seq;
        } else if(idx >= 0){
            // insert new entry
            seqCache[idx].used = TRUE;
            seqCache[idx].nodeId = p->src;
            seqCache[idx].maxSeq = p->seq;
        } else {
            // cache full; ignore caching and still process
            dbg(FLOODING_CHANNEL, "Cache full, processing packet from %hu seq %hu\n", p->src, p->seq);
        }

        // If this node is the destination, consume
        if(p->dest == TOS_NODE_ID){
            dbg(FLOODING_CHANNEL, "Packet for me from %hu seq %hu\n", p->src, p->seq);
            // Application-level handling 
        }

        // Decrement TTL and rebroadcast if TTL>1
        if(p->TTL > 0){
            p->TTL--;
            if(p->TTL > 0){
                // rebroadcast to all neighbors
                out = *p; // make a local copy to send
                err = call Sender.send(out, AM_BROADCAST_ADDR);
                if(err != SUCCESS){
                    dbg(FLOODING_CHANNEL, "Rebroadcast failed: %d\n", err);
                } else {
                    dbg(FLOODING_CHANNEL, "Rebroadcasted packet from %hu seq %hu (new TTL=%hhu)\n", out.src, out.seq, out.TTL);
                }
            }
        }

        return msg;
    }

    command void Flooding.printCache(){
        int i;
        dbg(FLOODING_CHANNEL, "Flood cache:\n");
        for(i=0;i<MAX_NODES;i++){
            if(seqCache[i].used){
                dbg(FLOODING_CHANNEL, "Node %hu -> maxSeq %hu\n", seqCache[i].nodeId, seqCache[i].maxSeq);
            }
        }
    }

    command void Flooding.test(){
        dbg(FLOODING_CHANNEL, "FLOODING WORKING?\n");
    }

}