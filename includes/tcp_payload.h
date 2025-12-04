#ifndef TCP_PAYLOAD_H
#define TCP_PAYLOAD_H

#include "ip_header.h"
#include "ll_header.h"
enum{
    TCP_HEADER_LEN = 7,
    TCP_PAYLOAD_SIZE = 28 - IP_HEADER_LENGTH - LL_HEADER_LENGTH - TCP_HEADER_LEN,
    SYN = 0,
    FIN = 1,
    ACK = 2,
    SYN_ACK = 3,
    NONE = 4
};


typedef struct tcp_payload_t{
    nx_uint8_t flags;
    uint8_t ack;
    uint8_t seq;
    nx_socket_port_t destPort;
    nx_socket_port_t srcPort;
    uint8_t window;
    uint8_t payload_len;
    uint8_t payload[TCP_PAYLOAD_SIZE];
} tcp_payload_t;

typedef struct new_conn_t{
    tcp_payload_t payload;
    uint16_t src;
} new_conn_t;

typedef struct packet_send_t{
    tcp_payload_t payload;
    uint8_t retransmitCount;
    uint8_t fd;
    uint32_t timestamp;  // When this packet was sent
    uint32_t timeout;    // When it should timeout
}packet_send_t;

#endif