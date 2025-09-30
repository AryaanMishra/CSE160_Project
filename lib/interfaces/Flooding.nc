interface Flooding{
    command void flood(pack msg, uint16_t dest);
    command void printCache();
    // Originate a flooded packet (e.g., a ping). Payload is a pointer to application data.
    command void test();
}