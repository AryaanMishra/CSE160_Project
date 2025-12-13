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

    components RandomC as Random;
    Node.Random -> Random;

    components new TimerMilliC() as steadyTimer;
    Node.steadyTimer -> steadyTimer;

    components new TimerMilliC() as test_server_connection_timer;
    Node.test_server_connection_timer -> test_server_connection_timer;

    components new TimerMilliC() as test_client_write_timer;
    Node.test_client_write_timer -> test_client_write_timer;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components new NeighborDiscoveryC(AM_PACK) as NeighborDiscovery;
    Node.Neighbor -> NeighborDiscovery;
    NeighborDiscovery.Sender -> SimpleSendC;

    components new FloodingC() as Flooding;
    Node.Flooding -> Flooding;
    Flooding.Sender -> SimpleSendC;

    components new ipC() as IP;
    Node.IP -> IP;

    components new TransportC() as Transport;
    Node.Transport -> Transport;
    Transport.IP -> IP;

    components new LinkStateC() as LinkState;
    Node.LinkState -> LinkState;
    LinkState.ND -> NeighborDiscovery;
    LinkState.Flood -> Flooding;
    NeighborDiscovery.LinkState -> LinkState;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    components new LinkLayerC();
    Node.LinkLayer -> LinkLayerC;
    LinkLayerC.ND -> NeighborDiscovery;
    LinkLayerC.Flood -> Flooding;
    LinkLayerC.IP -> IP;

    NeighborDiscovery.LinkLayer -> LinkLayerC;
    Flooding.LinkLayer -> LinkLayerC;
    Flooding.LinkState -> LinkState;
    Flooding.ND -> NeighborDiscovery;

    IP.LinkLayer -> LinkLayerC;
    IP.LinkState -> LinkState;
    IP.Sender -> SimpleSendC;
    IP.Transport -> Transport;

    components new AppC() as App;
    Node.App -> App;
    App.Transport -> Transport;
    
    Transport.App -> App;

    components new HashmapC(bool, 20) as currConnections;
    Node.currConnections -> currConnections;

}
