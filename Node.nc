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

   uses interface Timer<TMilli> as steadyTimer;


}

implementation{
   pack sendPackage;

   // Prototype (used by other handlers in this module)
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
      call Neighbor.findNeighbors();
      call steadyTimer.startOneShot(30000);

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
      call IP.buildIP(destination);
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

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

}
