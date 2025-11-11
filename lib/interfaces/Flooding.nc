interface Flooding{
    command void flood(lsa_pack* payload, uint8_t protocol);
    command message_t* floodReceive(message_t* msg, void* payload, uint8_t len, uint8_t protocol);
    
}