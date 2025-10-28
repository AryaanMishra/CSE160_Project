// Module
#include ../../includes/channels.h

#define BEACON_PERIOD 1000

module NeighborDiscoveryP{
	/// uses interface
	uses interface Timer<TMilli> as beaconTimer;

	// provides intefaces
}

Implementation{
	command void NeighborDiscovery.start(){
		// one shot timer and include random element to it.
		call beaconTimer.startPeriodic(BEACON_PERIOD);
}

command void NeighborDiscovery.print(){
	dbg(NEIGHBOR_CHANNEL, “Hello world!”);
}


event void beaconTimer.fired(){
	// Remove later, here for debuging
	dbg(NEIGHBOR_CHANNEL, Boop\n);
	// BROADCAST MESSAGE;

	// decrement all of the time since last response
	// if any == 0 remove from neighbor list.
}

Command Receive(){
	// If the destination is AM_BROADCAST, then respond directly
	send(msg, msg.src);
	// else
		add neighborlist
	//
}

// each neighbor time since last response. ( lets set it to 5)


}

