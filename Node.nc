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

   uses interface Timer<TMilli> as server_connection_timer;

   uses interface Timer<TMilli> as client_write_timer;

	uses interface Random;
}

implementation{
   pack sendPackage;
   socket_t fd;
   active_socket_t sockets[10];

   // Prototype (used by other handlers in this module)
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
      call Neighbor.findNeighbors();
      call steadyTimer.startOneShot(100000 + (call Random.rand16()%300));
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
      call server_connection_timer.startPeriodic(100000 + (call Random.rand16()%300));
   }
   
   event void server_connection_timer.fired(){
      socket_t newFd = call Transport.accept(fd);
      uint8_t i;
      uint8_t read_buff[SOCKET_BUFFER_SIZE];
      uint16_t bytes_read;
      uint16_t* p;

      if(newFd != NULL_SOCKET){
         dbg(TRANSPORT_CHANNEL, "NODE %u ACCEPTED CONNECTION ON PORT: %u\n", TOS_NODE_ID, newFd);
         call currConnections.insert(newFd, TRUE);
         sockets[newFd].has_odd = FALSE; 
         sockets[newFd].odd_byte = 0; 
      }

      for(i =0; i < MAX_NUM_OF_SOCKETS; i++){
         if(call currConnections.contains(i)){
               
               uint16_t start_index = 0;
               uint16_t total_data;
               uint16_t num_16;
               
               if(sockets[i].has_odd){
                  read_buff[0] = sockets[i].odd_byte;
                  start_index = 1;
               }
               
               bytes_read = call Transport.read(i, &read_buff[start_index], SOCKET_BUFFER_SIZE - start_index);
               
               total_data = bytes_read + start_index;

               if(total_data > 0){
                  uint8_t j;

                  p = (uint16_t*)read_buff;

                  if(total_data > 1 || (total_data == 1 && !sockets[i].has_odd)){
                     
                     
                     num_16 = total_data / 2;
                     
                     for(j = 0; j < num_16; j++){
                           dbg_clear(TRANSPORT_CHANNEL, "%u, ", p[j]);
                     }
                     
                     if((total_data % 2) != 0){
                           sockets[i].has_odd = TRUE;
                           sockets[i].odd_byte = read_buff[total_data - 1];
                           dbg_clear(TRANSPORT_CHANNEL, "ODD_BYTE STORED: %u(8)", sockets[i].odd_byte);
                     } else {
                           sockets[i].has_odd = FALSE;
                           sockets[i].odd_byte = 0;
                     }
                     
                     dbg_clear(TRANSPORT_CHANNEL, "\n");
                  }
               } 
         }
      }
   }

   void build_buff(socket_t d){
      uint8_t i;
      uint16_t val;
      for(i = 0; i < SOCKET_BUFFER_SIZE/2; i++){
         if(sockets[d].curr < sockets[d].transfer){
            val = ++sockets[fd].curr;
            sockets[d].buff[i*2] = (uint8_t)(val & 0x00FF);
            sockets[d].buff[i*2 + 1] = (uint8_t)((val >> 8) & 0x00FF);
         } else {
            break;
         }
      }
   }

   event void CommandHandler.setTestClient(uint16_t dest, socket_port_t srcPort, socket_port_t destPort, uint16_t transfer){
      socket_addr_t src_addr;
      socket_addr_t dest_addr;
      error_t bindResult;
      dbg(TRANSPORT_CHANNEL, "NODE %u PORT %u attempting to connect to NODE %u PORT %u\n", TOS_NODE_ID, srcPort, dest, destPort);
      dbg(TRANSPORT_CHANNEL, "SETTEST CLIENT CALLED ON NODE %u\n", TOS_NODE_ID);

      src_addr.addr = TOS_NODE_ID;
      src_addr.port = srcPort;

      dest_addr.addr = dest;
      dest_addr.port = destPort;
      
      fd = call Transport.socket();
      dbg(TRANSPORT_CHANNEL, "NODE %u SOCKET FD: %u\n", TOS_NODE_ID, fd);
      bindResult = call Transport.bind(fd, &src_addr);
      dbg(TRANSPORT_CHANNEL, "NODE %u BIND RESULT: %u\n", TOS_NODE_ID, bindResult);
      if(bindResult == SUCCESS){
         sockets[fd].isActive = TRUE;
         sockets[fd].transfer = transfer;
         sockets[fd].curr = 0;
         sockets[fd].written = 0;
         build_buff(fd);
         dbg(TRANSPORT_CHANNEL, "NODE %u SOCKET INITIALIZED, IS ACTIVE TRUE, Transfer %u\n", TOS_NODE_ID, sockets[fd].transfer);
      }

      call Transport.connect(fd, &dest_addr);
      dbg(TRANSPORT_CHANNEL, "NODE %u CONNECT CALLED\n", TOS_NODE_ID);

      if(!call client_write_timer.isRunning()){
         call client_write_timer.startPeriodic(30000 + (call Random.rand16()%300));
      }
   }

   task void client_write(){
      uint8_t i;
      bool writing = FALSE;
      uint16_t total_bytes;
      uint16_t bytes_remaining;
      uint8_t write_size_buffer;
      uint8_t len;
      
      for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){      
         if(sockets[i].isActive == TRUE){
               total_bytes = sockets[i].transfer * 2;
               if (sockets[i].written < total_bytes) {
                  writing = TRUE;
                  bytes_remaining = total_bytes - sockets[i].written;

                  if(sockets[i].written % SOCKET_BUFFER_SIZE == 0 && sockets[i].written != 0) {
                     build_buff(i);
                  }
                  
                  write_size_buffer = SOCKET_BUFFER_SIZE - (sockets[i].written % SOCKET_BUFFER_SIZE);

                  len = (uint8_t) (bytes_remaining < write_size_buffer ? bytes_remaining : write_size_buffer);
                  
                  if (len == 0){
                     return;
                  }

                  len = call Transport.write(i, &sockets[i].buff[sockets[i].written % SOCKET_BUFFER_SIZE], len);
                  // dbg(TRANSPORT_CHANNEL, "Wrote %u bytes\n", len);
                  
                  sockets[i].written += len; 
               }
         }
      }
      
      if(writing == FALSE){
         call client_write_timer.stop();
      }
   }

   event void client_write_timer.fired(){
      post client_write();
   }


   event void CommandHandler.clientClose(uint16_t dest, socket_port_t srcPort, socket_port_t destPort){
      error_t status;
      socket_t client_fd = call Transport.findFD(destPort, dest);
      if(client_fd != NULL_SOCKET){
         status = call Transport.close(client_fd);
         if(status == SUCCESS){
            dbg(TRANSPORT_CHANNEL, "CLIENT IS CLOSING\n");
         }
         else{
            dbg(TRANSPORT_CHANNEL, "CLIENT FAILED TO CLOSE\n");
         }
      }
      
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

}
