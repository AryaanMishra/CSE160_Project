#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/neighborTable.h"
#include "../../includes/protocol.h"

generic module LinkStateP(){
    provides interface LinkState;

    uses interface NeighborDiscovery as ND;
    uses interface Flooding as Flood;
    uses interface Hashmap<table>;
}

implementation{
    bool isSteady = FALSE;

    task void build_LSA_pack(){
        lsa_pack payload;
        node_cost temp;
        uint8_t packCount = 0;
        uint8_t j = call Hashmap.size();
        uint8_t i = 0;
        uint32_t* keys = call Hashmap.getKeys();
        while(i < j){
            temp.node = keys[i];
            temp.cost = 1;
            payload.entries[i - 6*packCount] = temp;
            if((i+1)%6==0){
                packCount++;
                payload.num_entries = 6;
                call Flood.flood(&payload, PROTOCOL_LINKSTATE);
                if(i+1 == j){
                    return;
                }
            }
            i++;
        }
        payload.num_entries = i - 6*packCount;
        call Flood.flood(&payload, PROTOCOL_LINKSTATE);
    }

    command lsa_pack* LinkState.lsReceive(){
        
    }

    command void LinkState.update(){
        post build_LSA_pack();
    }
}