#include <Timer.h> 

generic module NeighborDiscoveryP(){
    provides interface NeighborDiscovery;

    uses interface Timer<TMilli> as neighborTimer;
    uses interface Random;
}

implementation {

    command void NeighborDiscovery.findNeighbors(){
        call neighborTimer.startOneShot(100+ (call Random.rand16() % 300));
    }

    task void search(){
        "logic: send the msg, if somebody responds, save its id inside table."
        call neighborTimer.startOneShot(100+ (call Random.rand16() % 300));

    }

    event void neighborTimer.fired(){
        post search();
    }

    command void NeighborDiscovery.printNeighbors();
}