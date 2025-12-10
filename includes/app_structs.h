#ifndef APP_STRUCT_H
#define APP_STRUCT_H

#include "socket.h"

typedef struct active_t{
    //might want to increase the buff size later
    uint8_t send_buff[SOCKET_BUFFER_SIZE];
    uint8_t curr;
    uint8_t last_written;
    bool isActive;
} active_t;

#endif