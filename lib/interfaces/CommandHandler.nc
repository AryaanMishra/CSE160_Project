interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(socket_port_t port);
   event void setTestClient(uint16_t dest, socket_port_t srcPort, socket_port_t destPort, uint8_t* transfer);
   event void clientClose(uint16_t dest, socket_port_t srcPort, socket_port_t destPort);
   event void setAppServer();
   event void setAppClient();
}
