#ifndef TRANSPORT_HEADER_H
#define TRANSPORT_HEADER_H

#include "packet.h"
#include "socket.h"

// TCP Flags
enum {
    TCP_SYN = 0x01,      // Synchronization
    TCP_ACK = 0x02,      // Acknowledgment
    TCP_FIN = 0x04,      // Finish 
    TCP_DATA = 0x08,     // Data packet
};

#define TCP_HEADER_SIZE 6
#define TCP_MAX_PAYLOAD (PACKET_MAX_PAYLOAD_SIZE - TCP_HEADER_SIZE)

// TCP Header structure -  28-byte packet
// total packet: 8-byte + 20 bytes 
// TCP header uses 6 bytes
// Remaining: 14 bytes for payload 
typedef nx_struct tcp_header_t {
    nx_uint8_t srcPort;          
    nx_uint8_t destPort;         
    nx_uint8_t seq;              
    nx_uint8_t ack;              
    nx_uint8_t flags;            
    nx_uint8_t advertisedWindow; 
    nx_uint8_t payload[14];      
} tcp_header_t;

#endif
