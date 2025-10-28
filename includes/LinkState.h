//LINKSTATE FOR NODES AND THEIR NEIGHBORS

#ifndef LINKSTATE_H
#define LINKSTATE_H

typedef nx_struct LinkState{
	//Original Node
	nx_uint16_t node;
	//Packet of neightbors and cost
	nx_uint16_t neighbor;
	//Cost
	nx_uint16_t cost;
}LinkState;

typedef nx_struct RoutingTable{
        //Destination
        nx_uint16_t dest;
        //Nest Hop
        nx_uint16_t nextHop;
        //Cost of Total Hops
        nx_uint16_t cost;
}RoutingTable;

#endif
