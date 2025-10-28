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

    Node -> MainC.Boot;


    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components new NeighborDiscoveryC(AM_PACK) as NeighborDiscovery;
    Node.Neighbor -> NeighborDiscovery;

    components new FloodingC() as Flooding;
    Node.Flooding -> Flooding;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components new LinkLayerC();
    Node.LinkLayer -> LinkLayerC;
    LinkLayerC.ND -> NeighborDiscovery;
    LinkLayerC.Flood -> Flooding;

    NeighborDiscovery.LinkLayer -> LinkLayerC;
    Flooding.LinkLayer -> LinkLayerC;

}
