#ifndef IPHEADER_H
#define IPHEADER_H

enum{
    IP_HEADER_LENGTH = 5
};

typedef nx_struct ip_header{
    nx_uint16_t src;
    nx_uint16_t dest;
    nx_uint8_t TTL;
    nx_uint8_t payload[0];
} ip_header;

#endif