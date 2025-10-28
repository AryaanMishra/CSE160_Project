interface LinkLayer{
    command nx_uint8_t* buildLLHeader(nx_uint8_t protocol, uint8_t* buffer, nx_uint16_t dest);
}