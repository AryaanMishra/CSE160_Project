#ifndef APP_STRUCT_H
#define APP_STRUCT_H

#include "socket.h"

enum{
    BUFF_SIZE = 1028
};

typedef struct active_t{
    uint8_t send_buff[BUFF_SIZE];
    uint8_t recv_buff[BUFF_SIZE];  // Buffer for incoming data
    uint16_t curr;
    uint16_t written;
    uint16_t recv_len;  // Current length of received data
    bool isActive;
    char username[20];
} active_t;

#endif