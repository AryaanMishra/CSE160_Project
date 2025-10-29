#ifndef FLOODHEADER_H
#define FLOODHEADER_H

enum{
    FLOOD_HEADER_LENGTH = 5
};

typedef nx_struct flood_header{
    nx_uint16_t flood_src;
    nx_uint16_t seq;
    nx_uint8_t TTL;
    nx_uint8_t payload[0];
} flood_header;

#endif