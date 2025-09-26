#include "../../includes/channels.h"

generic module FloodingP(){
    provides interface Flooding;

}

implementation{
    command void Flooding.test(){
        dbg(FLOODING_CHANNEL, "FLOODING WORKING?\n");
    }

}