#include "../../includes/channels.h"

generic module FloodingP(){
    provides interface Flooding;
}

implementation{
    command void Flooding.test(){
        dbg(FLOODING_CHANNEL, "NODE %D: FLOODING WORKING?\n", TOS_NODE_ID);
    }
}