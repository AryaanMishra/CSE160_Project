/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include <string.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/LinkState.h"
#include "includes/TCP.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;

   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface Transport;

   uses interface List<pack> as List;

   uses interface List<int> as List2;

   uses interface Timer<TMilli> as periodicTimer;

   uses interface Timer<TMilli> as neighborFlood;

   uses interface Timer<TMilli> as dijkstra;

   uses interface List<LinkState> as nList;

   uses interface List<RoutingTable> as dList;

   uses interface Timer<TMilli> as serverTimer;

   uses interface Timer<TMilli> as clientTimer;

   uses interface List<socket_t> as sockList;

   uses interface Hashmap<char*> as userMap;
}

implementation{
   pack sendPackage;

   uint16_t seqNum = 0;

   //Socket function
   socket_t *fd;
   int transferB = 0;
//   char* username;
//   char* bMsg;
//   char *wMsg;
//   char *wUser;
   char username[SOCKET_BUFFER_SIZE];
   char bMsg[SOCKET_BUFFER_SIZE];
   char wMsg[SOCKET_BUFFER_SIZE];
   char wUser[SOCKET_BUFFER_SIZE];
   int hell = 0;
   int broad = 0;
   int mess = 0;
   int lis = 0;
   int size = 0;

   //Initializes neighbor flood fcn
   void lsFlood();

   //Initializes dijkstra Algorithm
   void dijkstraAlg();

   //Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   //Initializes the link state struct
   LinkState linkStateC;

   //Initializes the routing table
   RoutingTable rTableC;


   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
      call periodicTimer.startPeriodic(100000);			//Neighbor Discovery Timer
      call neighborFlood.startPeriodic(200000);			//Neighbor Flood Timer
      call dijkstra.startPeriodic(500000);			//Dijkstra's Algorithm Timer
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      } else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}



   event void periodicTimer.fired(){
      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 32, 0, seqNum, "Neighbor Ping", PACKET_MAX_PAYLOAD_SIZE);      
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
      seqNum++;
   }

   event void neighborFlood.fired() {
   //For Flooding neighbors
      lsFlood();
   }

   event void dijkstra.fired() {
   //Runs Shortest Distance Algorithm
      dijkstraAlg();
   }

   event void serverTimer.fired() {
   //Server Fire
      int x, newFd, r = 1, i;
      int oFd;
      char readBuff[SOCKET_BUFFER_SIZE];
      char writeBuff[SOCKET_BUFFER_SIZE];
      char* usern;

      dbg(TRANSPORT_CHANNEL, "Server Timer Fired\n");

      newFd = call Transport.accept(fd);
      if (newFd != NULL){
	 dbg(TRANSPORT_CHANNEL, "Adding newFd : %d\n", newFd);
         call sockList.pushback(newFd);
      }
      if(call Transport.estCheck(fd) == SUCCESS) {
      //Creates an empty array for buffer
         for (x = 0; x < SOCKET_BUFFER_SIZE; x++)
            readBuff[x] = 0;

         dbg(TRANSPORT_CHANNEL, "%d\n", call sockList.size());
         for (x = 0; x < call sockList.size(); x++) {
            oFd = call sockList.get(x);

            dbg(TRANSPORT_CHANNEL, "reading %d\n", oFd);
  	    r = call Transport.read(oFd, readBuff, SOCKET_BUFFER_SIZE);
//            dbg(TRANSPORT_CHANNEL, "%d added and rb = %d\n", oFd, readBuff[0]);
//            dbg(TRANSPORT_CHANNEL, "Size Read %d ---------\n", strlen(readBuff));

	    if (readBuff[0] == 104) {
	       dbg(TRANSPORT_CHANNEL, "Reading Hello\n");
	       for (x = 0; x < strlen(readBuff); x++) {
		  username[x] = (char) readBuff[x + 1];
 	       }
               dbg(TRANSPORT_CHANNEL, "Username: %s\n", username);
               dbg(TRANSPORT_CHANNEL, "Fd: %d\n",oFd);
	       call userMap.insert(oFd, username);
               size += strlen(readBuff);
            }
	    else if (readBuff[0] == 98) {
               dbg(TRANSPORT_CHANNEL, "Reading Broadcast\n");
               for (i = 0; i < call sockList.size(); i++) {
                  oFd = call sockList.get(i);
                  if (call Transport.estCheck(oFd) == SUCCESS) {
		     call Transport.write(oFd, readBuff, sizeof(readBuff));
	             call Transport.bufCheck(oFd);
                  }
               }
               size += strlen(readBuff);
	    }
            else if (readBuff[0] == 108) {			//Need to fix
               dbg(TRANSPORT_CHANNEL, "Reading Whisper\n");
               for (i = 0; i < call sockList.size(); i++) {
                  oFd = call sockList.get(i);
                  if (call Transport.estCheck(oFd) == SUCCESS) {
		     call Transport.write(oFd, readBuff, sizeof(readBuff));
                     call Transport.bufCheck(oFd);
		  }
               }
               size += strlen(readBuff);
	    }
            else if (readBuff[0] == 109) {
               dbg(TRANSPORT_CHANNEL, "Reading List\n");
               for (i = 0; i < call sockList.size(); i++) {
                  oFd = call sockList.get(i);
                  if (call Transport.estCheck(oFd) == SUCCESS) {
		     usern = call userMap.get(oFd);
                     writeBuff[i] = usern;
                  }
	       }   
	       call Transport.write(fd, writeBuff, sizeof(writeBuff));
               call Transport.bufCheck(fd);
               size += strlen(readBuff);
	    }
            else if (r != 0) {
               for (r = 0; r < SOCKET_BUFFER_SIZE; r++) {
  	          if (r == SOCKET_BUFFER_SIZE - 1 && readBuff[r] != 0)		//At end with value
                     dbg(TRANSPORT_CHANNEL, "%d\n", readBuff[r]);
     	          else if (readBuff[r] != 0)				//Not at end but have value
   	             dbg(TRANSPORT_CHANNEL, "%d, \n", readBuff[r]);
	          else if (r == (SOCKET_BUFFER_SIZE - 1))			//No value and at end
                     dbg(TRANSPORT_CHANNEL, "\n");
	       }
            }
         }
      }
   }

   event void clientTimer.fired() {
   //Client Fire
      int i = 0, x = 0;
      int temp = 0;
      int writeBuff[transferB];
      char readBuff[SOCKET_BUFFER_SIZE];
      char* charac;

      //New FCN to test buffer and send data accordingly
      dbg(TRANSPORT_CHANNEL, "Client Timer Fired\n");


      if (transferB != NULL) {
         if (call Transport.estCheck(fd) == SUCCESS) {
            for (i = 0; i < transferB; i++)
               writeBuff[i] = i + 1;

            x = call Transport.write(fd, writeBuff, transferB);

            call Transport.bufCheck(fd);
         }
         if ((transferB - x) == 0) {
            call Transport.close(fd);
	    call clientTimer.stop();
         }
         else
	    transferB -= x; 
      }
      else {
         if (hell == 1) {
	    temp = strlen(username);
	    charac = "h";

	    call Transport.write(fd, charac, 1);
            x = call Transport.write(fd, username, strlen(username));
	    call Transport.bufCheck(fd);

	    if ((temp - x) == 0)
	       hell = 0;
	 }
	 else if (broad == 1) {
            temp = strlen(bMsg);
            charac = "b";

            call Transport.write(fd, charac, 1);
            x = call Transport.write(fd, bMsg, strlen(bMsg));
            call Transport.bufCheck(fd);

	    //write bMsg to buffer
	    //Send msg
            if ((temp - x) == 0)
               broad = 0;	 
	 }
	 else if (mess == 1){
            temp = strlen(wMsg) + strlen(wUser);
            charac = "m";

            call Transport.write(fd, charac, 1);    
            x = call Transport.write(fd, wMsg, strlen(wMsg));
//            x = call Transport.write(fd, wUser, strlen(wUser));
            call Transport.bufCheck(fd);

            if ((temp - x) == 0)
               mess = 0;
	 }
	 else if (lis == 1) {
            charac = "l";

            call Transport.write(fd, charac, 1);
            call Transport.bufCheck(fd);

            //send pckt indicating list
            lis = 0;
	 }
	 else
	    dbg(TRANSPORT_CHANNEL, "Broke\n"); 		//Not actually broke

         for (x = 0; x < SOCKET_BUFFER_SIZE; x++)
            readBuff[x] = 0;

	 call Transport.read(fd, readBuff, SOCKET_BUFFER_SIZE);
	 if (readBuff[0] == 109) {
	    for (x = 1; x < sizeof(readBuff); x++)
 	       wMsg[x - 1] = (char) readBuff[x];
            dbg(TRANSPORT_CHANNEL, "Whisper Message: %s\n", wMsg);
         }
         else if (readBuff[0] == 108) {
            for (x = 1; x < sizeof(readBuff); x++)
               wUser[x - 1] = (char) readBuff[x];
            dbg(TRANSPORT_CHANNEL, "List of Users: %s\n", wUser);
         }
         else if (readBuff[0] == 98) {
            for (x = 1; x < sizeof(readBuff); x++)
               bMsg[x - 1] = (char) readBuff[x];
            dbg(TRANSPORT_CHANNEL, "Broadcast Message: %s\n", bMsg);
         }
      }
   }

   bool routeCheck(RoutingTable *rTableC) {
      int x;
      int size = call dList.size();
      RoutingTable routeC;
      if (call dList.isEmpty())
         return TRUE;

      for (x = 0; x < size; x++) {
         routeC = call dList.get(x);
         if (routeC.dest == rTableC->dest && routeC.nextHop == rTableC->nextHop && routeC.cost == rTableC->cost)
            return FALSE;
      }

      return TRUE;
   }

   int minmax(int d) {
      int x;
      int m;
      LinkState lsTest;
      if (d == 1) {
         m = 0;
         for (x = 0; x < call nList.size(); x++) {
            lsTest = call nList.get(x);
            if (m < lsTest.node)
               m = lsTest.node;
         }
      }
      else if (d == 0) {
         m = 999;
         for (x = 0; x < call nList.size(); x++) {
            lsTest = call nList.get(x);
            if (m > lsTest.node)
               m = lsTest.node;
         }
      }
      return m;
   }

   int nextHop(int destination) {
      int x;
      int nn = 999;
      RoutingTable routeC;
      for (x = 0; x < call dList.size(); x++) {
         routeC = call dList.get(x);
         if (routeC.dest == destination){
            nn = routeC.nextHop;
            break;
         }
      }
//      dbg(TRANSPORT_CHANNEL, "NH: %d\n", nn);
      return nn;
   }

   bool neighCheck(LinkState *linkStateC) {
      int x;
      int size = call nList.size();
      LinkState lsTest;
      if (call nList.isEmpty())
         return TRUE;

      for (x = 0; x < size; x++) {
         lsTest = call nList.get(x);
         if (lsTest.node == linkStateC->node && lsTest.neighbor == linkStateC->neighbor && lsTest.cost == linkStateC->cost)
            return FALSE;
      }

      return TRUE;
   }

   bool packCheck(pack *Package) {
      int x;
      int size = call List.size();
      pack listPack;
      if (call List.isEmpty())
         return TRUE;

      for (x = 0; x < size; x++) {
         listPack = call List.get(x);
         if (listPack.src == Package->src && listPack.dest == Package->dest && listPack.seq == Package->seq)
            return FALSE;
      }

      return TRUE;
   }

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
//      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;

         if (myMsg->dest == AM_BROADCAST_ADDR) {
            if (myMsg->protocol == 0) {
               myMsg->TTL--;
               makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 32, 1, seqNum, "Ping Reply", PACKET_MAX_PAYLOAD_SIZE);        //Ping Reply
               call Sender.send(sendPackage, myMsg->src);
               seqNum++;
            }
            else if (myMsg->protocol == 1) {
               int size = call List2.size();
               int x = 0;
               int ans = 0;

               for (x = 0; x < size; x++) {
                  if (myMsg->src == call List2.get(x)) {
                     ans = 1;
                  }
               }

               if (ans == 0) {
                  call List2.pushfront(myMsg->src);
               }               
            }

            else if (myMsg->protocol == 2) {                                         //LinkState Flood

//               dbg(GENERAL_CHANNEL, "The neighbor of %d is %d found at node %d\n", myMsg->src, myMsg->payload[0], TOS_NODE_ID);
               linkStateC.node = myMsg->src;
               linkStateC.neighbor = myMsg->payload[0];
//               dbg(GENERAL_CHANNEL, "Payload %d\n", myMsg->payload[0]);
               linkStateC.cost = 1;

               if (neighCheck(&linkStateC))
                  call nList.pushback(linkStateC);
               else
                  return msg;

               myMsg->TTL -=1;
//               dbg(GENERAL_CHANNEL, "New TTL is %d\n", myMsg->TTL);
               call Sender.send(*myMsg, AM_BROADCAST_ADDR);                     //Floods to neighbors
//               dbg(GENERAL_CHANNEL, "Flood Packet Sent from %d\n",TOS_NODE_ID);
            }

         return msg;
         }

         else if (myMsg->TTL == 0){						//TTL is at end
            dbg(GENERAL_CHANNEL, "TTL is 0\n");
            return msg;
         }

         else if (myMsg->protocol == 3) {
            if (myMsg->dest == TOS_NODE_ID){                            //Checks if myMsg is at the destination
               dbg(ROUTING_CHANNEL, "At End\n\n");
               dbg(ROUTING_CHANNEL, "Package Payload: %s\n\n", myMsg->payload);
            }
            else if (nextHop(myMsg->dest) == 999) {
               call Sender.send(sendPackage, AM_BROADCAST_ADDR);
               dbg(ROUTING_CHANNEL, "No next hop FLOODING");
            }
            else {
               dbg(ROUTING_CHANNEL, "Not there yet at %d next hop is %d\n", TOS_NODE_ID, nextHop(myMsg->dest));
               myMsg->TTL -= 1;
//               dbg(ROUTING_CHANNEL, "New TTL is %d\n", myMsg->TTL);
               call Sender.send(*myMsg, nextHop(myMsg->dest));             //Floods to neighbors
//               dbg(ROUTING_CHANNEL, "Packet Sent\n");
               return msg;
            }
         }

	 else if (myMsg->protocol == 4) {
            dbg(TRANSPORT_CHANNEL, "Packet Received\n");

	    //Stops our intial flood
	    if (TOS_NODE_ID == myMsg->src)
	       return msg;	

	    if (myMsg->dest == TOS_NODE_ID)
	       call Transport.receive(payload);
	    else if ((nextHop(myMsg->dest)) == 999) {
	       myMsg->TTL -= 1;
               call Sender.send(*myMsg, AM_BROADCAST_ADDR);
               dbg(TRANSPORT_CHANNEL, "No next hop FLOODING\n");
            }
            else {
               myMsg->TTL -= 1;
               call Sender.send(*myMsg, (nextHop(myMsg->dest)));
//	       call Sender.send(*myMsg, AM_BROADCAST_ADDR);
               dbg(TRANSPORT_CHANNEL, "Going from %d to %d\n", TOS_NODE_ID, myMsg->dest);
            }
	    return msg;
         }
         else if (packCheck(myMsg)) {						//Checks if package is saved already
            dbg (GENERAL_CHANNEL, "Is Empty\n");
            call List.pushfront(*myMsg);					//Adds new package to list

            if (myMsg->dest == TOS_NODE_ID){				//Checks if myMsg is at the destination
               dbg(GENERAL_CHANNEL, "At End\n\n");
               dbg(GENERAL_CHANNEL, "Package Payload: %s\n\n", myMsg->payload);

               if(myMsg->protocol == 0) {
                  makePack(&sendPackage, TOS_NODE_ID, myMsg->src, 32, 1, seqNum, "Ping Reply", PACKET_MAX_PAYLOAD_SIZE);	//Ping Reply
                  call Sender.send(sendPackage, AM_BROADCAST_ADDR);
                  seqNum++;
               }
               
               return msg;
            }
            else {
               //dbg(GENERAL_CHANNEL, "Not at End\n");
               myMsg->TTL -= 1;							//Counts down TTL
               dbg(GENERAL_CHANNEL, "New TTL is %d\n", myMsg->TTL);
               call Sender.send(*myMsg, AM_BROADCAST_ADDR);		//Floods to neighbors
               dbg(GENERAL_CHANNEL, "Packet Sent\n");
	       return msg;
            }
         }
         else {
            dbg(GENERAL_CHANNEL, "Packet already been here\n");
            return msg;
         }
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;

   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 32, 3, seqNum, payload, PACKET_MAX_PAYLOAD_SIZE);	//32 is TTL
      dbg(GENERAL_CHANNEL, "Sequence Number is %d\n", seqNum);
      seqNum++;
      if (nextHop(destination) == 999) {
         call Sender.send(sendPackage, AM_BROADCAST_ADDR);
         dbg(ROUTING_CHANNEL, "No next hop FLOODING");
      }
      else {
         call Sender.send(sendPackage, nextHop(destination));
         dbg(ROUTING_CHANNEL, "Going from %d to %d\n", TOS_NODE_ID, destination);
      }
   }

   void lsFlood() {
   //For Flooding Neighbors
      int x = call List2.size();
      int NieAr[1];
      int i;

      for (i = 0; i < x; i++) {
         NieAr[0] = call List2.get(i);
//         dbg(GENERAL_CHANNEL, "%d's neighbor is %d\n",TOS_NODE_ID, NieAr[0]);
         makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 32, 2, seqNum, NieAr, PACKET_MAX_PAYLOAD_SIZE);        //payload is neighbor (one at a time) and protocal is 2
//         dbg(GENERAL_CHANNEL, "Sequence Number is %d\n", seqNum);
         seqNum++;
         call Sender.send(sendPackage, AM_BROADCAST_ADDR);
      }
   }

   void dijkstraAlg() {
      int i, nh, greater, less;
      int ph = 999;
      int x = 0;
      LinkState lsTest;
      int max = minmax(1);
      int min = minmax(0);

      while (x < call nList.size()) {
         lsTest = call nList.get(x);
         if (lsTest.node == TOS_NODE_ID){
            x++;
            continue;
         }

         greater = 0;
         less = 0;
         if (max == TOS_NODE_ID) 
            less = call List2.get(call List2.size()-1);
         else if (min == TOS_NODE_ID) 
            greater = call List2.get(call List2.size()-1);
         else {
            for (i = 0; i < call List2.size()-1; i++){
               if (call List2.get(i) > call List2.get(i+1)){
                  greater = call List2.get(i);
                  less = call List2.get(i+1);
               }
               else {
                  greater = call List2.get(i+1);
                  less = call List2.get(i);
               }
            }    
         }

         if (TOS_NODE_ID < lsTest.node){
            ph = (lsTest.node - TOS_NODE_ID);
            nh = greater;
         }
         else {
            ph = (TOS_NODE_ID - lsTest.node);
            nh = less;         
         }

         rTableC.dest = lsTest.node;
         rTableC.nextHop = nh;
         rTableC.cost = ph;

         if(routeCheck(&rTableC)) 
            call dList.pushback(rTableC);
         x++;
      }
   }

   event void CommandHandler.printNeighbors(){				//Prints the neighbors of a specific node
      int x;
      int size = call List2.size();
      for (x = 0; x < size; x++) {
         int node;
         node = call List2.get(x);
         dbg(NEIGHBOR_CHANNEL, "The neighbors of %d is %d\n", TOS_NODE_ID, node);
      } 
      dbg(NEIGHBOR_CHANNEL, "End of neighbor dump %d\n\n",TOS_NODE_ID);
   }

   event void CommandHandler.printRouteTable(){
      int x;
      int size = call dList.size();
      RoutingTable routeC;
      for (x = 0; x < size; x++) {
         routeC = call dList.get(x);
         dbg(ROUTING_CHANNEL, "Destination : %d / Next Hop : %d / Cost : %d\n",routeC.dest, routeC.nextHop, routeC.cost);
      }
      dbg(ROUTING_CHANNEL, "End of Routing dump %d\n\n",TOS_NODE_ID);
   }

   event void CommandHandler.printLinkState(){
      int x;
      int size = call nList.size();
      LinkState lsTest;
      for (x = 0; x < size; x++) {         
         lsTest = call nList.get(x);
         dbg(GENERAL_CHANNEL, "The neighbor of %d is %d and has a cost of %d\n", lsTest.node, lsTest.neighbor, lsTest.cost);
      }
      dbg(GENERAL_CHANNEL, "End of LinkState dump %d\n\n",TOS_NODE_ID); 
   }

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(uint8_t sPort){
      socket_addr_t sAddr;

      dbg(TRANSPORT_CHANNEL, "Test Server Starting\n");

      sAddr.port = sPort;
      sAddr.addr = TOS_NODE_ID;

      fd = call Transport.socket();
      call Transport.bind(fd, &sAddr);
      call Transport.listen(fd);

      dbg(TRANSPORT_CHANNEL, "Starting Server Timer\n");
      call serverTimer.startPeriodic(100000);                 //Server Connection
   }

   event void CommandHandler.setTestClient(int destination, int srcPort, int destPort, int trans){
      socket_addr_t src;
      socket_addr_t dest;

      dbg(TRANSPORT_CHANNEL, "Test Client Starting\n");

      src.port = srcPort;
      src.addr = TOS_NODE_ID;
      dest.port = destPort;
      dest.addr = destination;

      fd = call Transport.socket();
      call Transport.bind(fd, &src);

      call Transport.connect(fd, &dest);
      //Connects
      call clientTimer.startPeriodic(200000);		//Client Connection
      transferB = trans;				//Global Var storing transfer amount
   }

   event void CommandHandler.setClientClose(int destination, int srcPort, int destPort){ 	//Ignore this
      socket_addr_t src;
      socket_addr_t dest;

      dbg(TRANSPORT_CHANNEL, "Client Closing Starting\n");

      src.port = srcPort;
      src.addr = TOS_NODE_ID;
      dest.port = destPort;
      dest.addr = destination;

      fd = call Transport.find(&src, &dest);
      if (fd != 231){
	 call clientTimer.stop();
         call serverTimer.stop();
         call Transport.close(fd);
      }
      else
	 dbg(TRANSPORT_CHANNEL, "ERROR IN FIND\n");
   }

   event void CommandHandler.hello(char *user, int cPort){
      socket_addr_t src;
      socket_addr_t dest;
      int x, i, temp = 0, port = 0, rPort = 0;
      char* token;
      char* search = ",";
      dbg(TRANSPORT_CHANNEL, "Hello Initiated\n");      

      token = strtok(user, search);
      strcpy(username, token);
      token = strtok(NULL, search);

      for (x = 0; x < strlen(token); x++) {
         port += *(token + x);
         temp = ((strlen(token) - x));
         for(i = 0; i < temp; i++) {
            if (i == 0)
               rPort += port;
            else
               rPort += (port * (10 * i)); 
         }
      }

      src.port = rPort;
      src.addr = TOS_NODE_ID;
      dest.port = 41;           //Req'd Port/Addr
      dest.addr = 1;

      fd = call Transport.socket();
      call Transport.bind(fd, &src);

      transferB = NULL;
      hell = 1;

      dbg(TRANSPORT_CHANNEL, "Username: %s Port: %d\n", username, x);
      call Transport.connect(fd, &dest);
      //Connects
      call clientTimer.startPeriodic(200000);           //Client Connection
   }

   event void CommandHandler.msg(char *msg){
   //Broadcasts a Message
      if(call Transport.estCheck(fd) == SUCCESS) {
         strcpy(bMsg, msg);
         broad = 1;
      }
      else 
	 dbg(TRANSPORT_CHANNEL, "Not Connected can't broadcast\n");
   }

   event void CommandHandler.whisper(char *user, char *msg){
   //Whispers specific user a message
   int x = 0, y = 0, ch = 0;
      if(call Transport.estCheck(fd) == SUCCESS) {

	 //Python combines the 2 strings into 1; This fixes that problem 
	 for(x = 0; x < (strlen(user)); x++) {
	    dbg(TRANSPORT_CHANNEL, "%c\n", *(user + x));
	    if(*(user + x) == NULL)
	       break;
	    else if(*(user + x) == ',') {
//	       dbg(TRANSPORT_CHANNEL, "dash\n");
	       ch = 1;
	       continue;
	    }
	    else if(ch == 0) {
//	       dbg(TRANSPORT_CHANNEL, "here\n");
 	       wUser[x] = *(user + x);
	    }
	    else{
//	       dbg(TRANSPORT_CHANNEL, "there\n");
	       wMsg[y] = *(user + x);
               y++;
	    }
         }

         dbg(TRANSPORT_CHANNEL, "Username: %s\n", wUser);
         dbg(TRANSPORT_CHANNEL, "Message: %s\n", wMsg);
         mess = 1;
      }
      else  
         dbg(TRANSPORT_CHANNEL, "Not Connected can't whisper\n");
   }

   event void CommandHandler.listur(){
   //Asks server for list of connected users
      if(call Transport.estCheck(fd) == SUCCESS)
         lis = 1;
      else
         dbg(TRANSPORT_CHANNEL, "Not Connected can't recieve user list\n");
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
