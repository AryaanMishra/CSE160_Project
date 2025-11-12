#ifndef TCP_PAYLOAD_H
#define TCP_PAYLOAD_H


enum{
    HANDSHAKE_PAYLOAD_SIZE = 18,
    ACK = 0,
    SYN = 1,
    SYN_ACK = 2,
    FIN = 3,
};

typedef struct tcp_payload_t{
    nx_uint8_t flags;
    uint16_t seq;
    nx_socket_port_t destPort;
    nx_socket_port_t srcPort;
    uint16_t src_addr;
    uint8_t payload[12];
} tcp_payload_t;

#endif