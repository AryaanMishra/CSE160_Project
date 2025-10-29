interface Flooding{
    command void flood(lsa_pack* payload);
    command message_t* floodReceive(message_t* msg, void* payload, uint8_t len, uint8_t protocol);
    
    command void flood_LSA(lsa_pack* lsa_payload, uint16_t sequence_number);
}