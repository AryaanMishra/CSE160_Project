/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
	

}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

//    components FloodingC;
//    Node.FloodSender -> FloodingC.FloodSender;

    components new ListC (pack, 64) as ListC;
    Node.List -> ListC;

    components new ListC (int, 64) as List2C;
    Node.List2 -> List2C;

    components new TimerMilliC() as periodicTimer;
    Node.periodicTimer -> periodicTimer;

    components new TimerMilliC() as neighborFlood;
    Node.neighborFlood -> neighborFlood;

    components new TimerMilliC() as dijkstra;
    Node.dijkstra -> dijkstra;

    components new ListC (LinkState, 64) as nListC;
    Node.nList -> nListC;

    components new ListC (RoutingTable, 64) as dListC;
    Node.dList -> dListC;

    components new TimerMilliC() as serverTimer;
    Node.serverTimer -> serverTimer;

    components new TimerMilliC() as clientTimer;
    Node.clientTimer -> clientTimer;

    components TransportC;
    Node.Transport -> TransportC;

    components new ListC (socket_t, 64) as sockListC;
    Node.sockList -> sockListC; 

   components new HashmapC (char*, 64) as userMapC;
   Node.userMap -> userMapC;
}
