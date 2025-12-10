#ifndef APP_STRUCT_H
#define APP_STRUCT_H

#include "socket.h"

enum{
    BUFF_SIZE = 1028
};

typedef struct active_t{
    //might want to increase the buff size later
    uint8_t send_buff[BUFF_SIZE];
    uint8_t curr;
    uint8_t written;
    bool isActive;
    char username[20]; // Add this line to store the user's name
} active_t;

#endif