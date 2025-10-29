#ifndef NDHEADER_H
#define NDHEADER_H

enum{
    ND_HEADER_LENGTH = 2
};

typedef nx_struct nd_header{
    nx_uint8_t protocol;
    nx_uint8_t seq;
    nx_uint8_t payload[0];
} nd_header;

#endif