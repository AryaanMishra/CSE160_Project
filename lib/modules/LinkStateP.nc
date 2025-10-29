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
    bool isSteady = false; 
    
    command lsa_pack* LinkState.build_LSA_pack(){
        lsa_pack payload;
        uint8_t maxSize = 6;
        uint8_t j = call Hashmap.size()-1;
        uint32_t* keys = call Hashmap.getKeys();
        while(j > 0)

    }
}