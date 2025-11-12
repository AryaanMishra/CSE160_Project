/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/protocol.h"
#include "includes/socket.h"
#include "includes/tcp_payload.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface NeighborDiscovery as Neighbor;

   uses interface Flooding;

   uses interface LinkLayer;

   uses interface LinkState;

   uses interface IP as IP;

   uses interface Transport as Transport;

   uses interface Timer<TMilli> as steadyTimer;

   uses interface Hashmap<bool> as currConnections;

   uses interface Timer<TMilli> as connectionTimer;
}

implementation{
   pack sendPackage;
   socket_t fd;

   // Prototype (used by other handlers in this module)
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
      call Neighbor.findNeighbors();
      call steadyTimer.startOneShot(100000);
      call Transport.initializeSockets();

   }

   event void steadyTimer.fired(){
      call Neighbor.setSteady();
   }



   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}



   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT: Node %d trying to ping %d\n", TOS_NODE_ID, destination);
      // Implement proper ping via IP layer
      // For now, just log the ping request
      dbg(GENERAL_CHANNEL, "Ping functionality not yet implemented\n");
      call IP.buildIP(destination, PROTOCOL_IP, (tcp_payload_t*)payload);
   }

   

   event void CommandHandler.printNeighbors(){
      call Neighbor.printNeighbors();
      
      // Also trigger LSA generation to test LinkState
      dbg(ROUTING_CHANNEL, "Triggering LSA generation for Node %d\n", TOS_NODE_ID);
      call LinkState.build_and_flood_LSA();
   }

   event void CommandHandler.printRouteTable(){
      call LinkState.printRoute();
   }

   event void CommandHandler.printLinkState(){
   }

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(socket_port_t port){
      socket_addr_t addr;
      dbg(TRANSPORT_CHANNEL, "NODE %u OPENING PORT: %u\n", TOS_NODE_ID, port);
      fd = call Transport.socket();
      addr.addr = TOS_NODE_ID;
      addr.port = port;
      call Transport.bind(fd, &addr);
      call Transport.listen(fd);
      call connectionTimer.startPeriodic(300000);
   }

   event void connectionTimer.fired(){
      socket_t newFd = call Transport.accept(fd);

      if(newFd != NULL_SOCKET){
         dbg(TRANSPORT_CHANNEL, "NODE %u ACCEPTED CONNECTION ON PORT: %u\n", TOS_NODE_ID, newFd);
         call currConnections.insert(newFd, TRUE);
      }

      //READ DATA HERE

      dbg(TRANSPORT_CHANNEL, "Socket %u did not accept new connections\n", fd);
   }

   event void CommandHandler.setTestClient(uint16_t dest, socket_port_t srcPort, socket_port_t destPort, uint8_t* transfer){
      socket_addr_t src_addr;
      socket_addr_t dest_addr;
      dbg(TRANSPORT_CHANNEL, "NODE %u PORT %u attempting to connect to NODE %u PORT %u\n", TOS_NODE_ID, srcPort, dest, destPort);

      src_addr.addr = TOS_NODE_ID;
      src_addr.port = srcPort;

      dest_addr.addr = dest;
      dest_addr.port = destPort;
      
      fd = call Transport.socket();
      call Transport.bind(fd, &src_addr);

      call Transport.connect(fd, &dest_addr);
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

}
