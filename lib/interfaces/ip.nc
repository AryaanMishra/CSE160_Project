interface IP{
    command void buildIP(uint16_t dest, uint8_t protocol);
    command message_t* ipRecieve(message_t* msg, void* payload, uint8_t len, uint8_t protocol);
}