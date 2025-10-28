interface Flooding{
    command void flood();
    command message_t* floodReceive(message_t* msg, void* payload, uint8_t len);
}