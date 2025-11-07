#ifndef LLHEADER_H
#define LLHEADER_H

enum{
    LL_HEADER_LENGTH = 5
};

typedef nx_struct ll_header{
    nx_uint16_t src;
    nx_uint16_t dest;
    nx_uint8_t protocol;
    nx_uint8_t payload[0];
} ll_header;

#endif