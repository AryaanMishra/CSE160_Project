#include <Timer.h> 
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/CommandMsg.h"
#include "../../includes/sendInfo.h"
#include "../../includes/neighborTable.h"
#include "../../includes/protocol.h"

generic module LinkStateP(){
    provides interface LinkState;

    uses interface Hashmap<table>;
}

implementation{
    command lsa_pack* build_LSA_pack(table t, uint8_t i){
        lsa_pack payload;

    }
}