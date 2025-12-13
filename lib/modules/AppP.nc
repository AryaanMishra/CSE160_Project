#include "../../includes/socket.h"
#include "../../includes/app_structs.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

generic module AppP(){
    provides interface App;

    uses interface Timer<TMilli> as read_write;
    uses interface Transport;
}
implementation{
    socket_t global_fd;
    active_t sockets[MAX_NUM_OF_SOCKETS];

    void extract_word(const char *src, char *dest, uint8_t n){
        uint8_t count = 0;
        const char *p = src;
        const char *delimiters = " \r\n";

        while (*p && strchr(delimiters, *p))
            p++;

        while (*p) {
            const char *word_start = p;
            
            while (*p && !strchr(delimiters, *p)){
                p++;
            }

            count++;

            if (count == n) {
                size_t len = p - word_start;
                
                memcpy(dest, word_start, len);
                dest[len] = '\0';
                return;
            }
            
            while (*p && strchr(delimiters, *p))
                p++;
        }
    }

    command error_t App.accept_done(){
        socket_t newFd = call Transport.accept(global_fd);
        if(newFd != NULL_SOCKET){
            sockets[newFd].isActive = TRUE;
            sockets[newFd].written = 0;
            sockets[newFd].curr = 0;
            sockets[newFd].recv_len = 0;
            memset(sockets[newFd].recv_buff, 0, BUFF_SIZE);
            dbg(GENERAL_CHANNEL, "Accepting Connection, Socket %d Active\n", newFd);
            if(!(call read_write.isRunning())){
                call read_write.startPeriodic(500); // Faster period for better responsiveness
            }
        }
        else {
            return FAIL;
        }
        return SUCCESS;
    }

    command error_t App.connect_done(socket_t fd){
        dbg(GENERAL_CHANNEL, "Connect Done called for socket %d\n", fd);
        sockets[fd].recv_len = 0;
        memset(sockets[fd].recv_buff, 0, BUFF_SIZE);
        if(!(call read_write.isRunning())){
            call read_write.startPeriodic(500);
        }
        return SUCCESS;
    }

    error_t hello_cmd(char* msg){
        socket_addr_t src_addr;
        socket_addr_t dest_addr;
        error_t bindResult;
        char extract[32] = {0};
        uint8_t len;
        size_t remaining_size;

        extract_word(msg, extract, 3); //extracts port
        
        src_addr.port = atoi(extract); 
        src_addr.addr = TOS_NODE_ID;

        dest_addr.addr = 1;
        dest_addr.port = 41;
        
        global_fd = call Transport.socket();
        bindResult = call Transport.bind(global_fd, &src_addr);
        if(bindResult == SUCCESS){
            sockets[global_fd].isActive = TRUE;
            sockets[global_fd].written = 0;
            sockets[global_fd].curr = 0;               
            dbg(GENERAL_CHANNEL, "NODE %u SOCKET INITIALIZED, IS ACTIVE TRUE\n", TOS_NODE_ID);
        }

        call Transport.connect(global_fd, &dest_addr);
        dbg(GENERAL_CHANNEL, "NODE %u CONNECT CALLED\n", TOS_NODE_ID);

        memset(extract, 0, sizeof(extract));
        extract_word(msg, extract, 2); // extracts username

        remaining_size = BUFF_SIZE - sockets[global_fd].curr;
        if(remaining_size < sizeof(extract) + 10){
            return FAIL;
        }
        
        len = snprintf((char*)&sockets[global_fd].send_buff[sockets[global_fd].curr], 
            remaining_size, "hello %s\r\n", extract);

        sockets[global_fd].curr += len; 

        return SUCCESS;    
    }

    error_t msg_cmd(char* msg){
        char extract[BUFF_SIZE] = {0};
        uint8_t len;
        size_t remaining_size;
        
        // Format: msg [message]
        //  extract everything after "msg "
        char cmd[10];
        sscanf(msg, "%s %[^\r\n]", cmd, extract);

        remaining_size = BUFF_SIZE - sockets[global_fd].curr;
        
        // Protocol: msg [message]\r\n
        len = snprintf((char*)&sockets[global_fd].send_buff[sockets[global_fd].curr], 
            remaining_size, "msg %s\r\n", extract);

        sockets[global_fd].curr += len;
        return SUCCESS;
    }

    error_t whisper_cmd(char* msg){
        char user[20];
        char content[BUFF_SIZE];
        uint8_t len;
        size_t remaining_size;

        // Format: whisper [username] [message]
        char cmd[10];
        sscanf(msg, "%s %s %[^\r\n]", cmd, user, content);

        remaining_size = BUFF_SIZE - sockets[global_fd].curr;
        
        len = snprintf((char*)&sockets[global_fd].send_buff[sockets[global_fd].curr], 
            remaining_size, "whisper %s %s\r\n", user, content);

        sockets[global_fd].curr += len;
        return SUCCESS;
    }

    error_t listusr_cmd(){
        uint8_t len;
        size_t remaining_size = BUFF_SIZE - sockets[global_fd].curr;
        
        len = snprintf((char*)&sockets[global_fd].send_buff[sockets[global_fd].curr], 
            remaining_size, "listusr\r\n");

        sockets[global_fd].curr += len;
        return SUCCESS;
    }

    command void App.initialize_server(socket_port_t port){
        socket_addr_t addr;
        dbg(GENERAL_CHANNEL, "NODE %u OPENING PORT: %u\n", TOS_NODE_ID, port);
        global_fd = call Transport.socket();
        addr.addr = TOS_NODE_ID;
        addr.port = port;
        call Transport.bind(global_fd, &addr);
        call Transport.listen(global_fd);
        
        sockets[global_fd].isActive = TRUE; 
        call read_write.startPeriodic(500);
    }

    command error_t App.handle_command(char* msg){
        char extract [32] = {0};
        
        extract_word(msg, extract, 1); //command type
        dbg(GENERAL_CHANNEL, "App Handle Command: %s\n", extract);

        if(strcmp(extract, "hello") == 0){
            return hello_cmd(msg);
        } else if (strcmp(extract, "msg") == 0){
            return msg_cmd(msg);
        } else if (strcmp(extract, "whisper") == 0){
            return whisper_cmd(msg);
        } else if (strcmp(extract, "listusr") == 0){
            return listusr_cmd();
        }
        return FAIL;
    }

    void broadcast(socket_t source_fd, char* message) {
        int i;
        uint16_t len = strlen(message);
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].isActive && i != source_fd && i != global_fd) {
                uint16_t remaining = BUFF_SIZE - sockets[i].curr;
                if (remaining > len) {
                    memcpy(&sockets[i].send_buff[sockets[i].curr], message, len);
                    sockets[i].curr += len;
                }
            }
        }
    }

    void server_parse_input(socket_t fd, char* input) {
        char cmd[10];
        char rest[BUFF_SIZE];
        char output[BUFF_SIZE];
        char* ptr;
        
        memset(cmd, 0, 10);
        memset(rest, 0, BUFF_SIZE);
        memset(output, 0, BUFF_SIZE);
        
        // Strip \r\n from input
        ptr = input;
        while (*ptr) {
            if (*ptr == '\r' || *ptr == '\n') {
                *ptr = '\0';
                break;
            }
            ptr++;
        }
        
        sscanf(input, "%s %[^\t\n]", cmd, rest); 

        dbg(GENERAL_CHANNEL, "Server received from %d: %s\n", fd, input);

        if (strcmp(cmd, "Hello") == 0 || strcmp(cmd, "hello") == 0) {
            strcpy(sockets[fd].username, rest);
            dbg(GENERAL_CHANNEL, "User registered: %s on socket %d\n", sockets[fd].username, fd);
        } 
        else if (strcmp(cmd, "msg") == 0) {
            sprintf(output, "%s: %s\r\n", sockets[fd].username, rest);
            broadcast(fd, output);
        }
        else if (strcmp(cmd, "listusr") == 0) {
            int i;
            strcpy(output, "listUsrRply ");
            for(i=0; i<MAX_NUM_OF_SOCKETS; i++){
                if(sockets[i].isActive && strlen(sockets[i].username) > 0){
                    strcat(output, sockets[i].username);
                    strcat(output, ", ");
                }
            }
            strcat(output, "\r\n");
            
            if (BUFF_SIZE - sockets[fd].curr > strlen(output)) {
                strcpy((char*)&sockets[fd].send_buff[sockets[fd].curr], output);
                sockets[fd].curr += strlen(output);
            }
        }
        else if (strcmp(cmd, "whisper") == 0) {
            char targetUser[20];
            char msgContent[BUFF_SIZE];
            int i;
            bool found = FALSE;

            sscanf(rest, "%s %[^\t\n]", targetUser, msgContent);

            for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
                if(sockets[i].isActive && strcmp(sockets[i].username, targetUser) == 0){
                    sprintf(output, "%s whispers: %s\r\n", sockets[fd].username, msgContent);
                    
                    if (BUFF_SIZE - sockets[i].curr > strlen(output)) {
                        memcpy(&sockets[i].send_buff[sockets[i].curr], output, strlen(output));
                        sockets[i].curr += strlen(output);
                    }
                    found = TRUE;
                    break;
                }
            }
            if(!found){
                dbg(GENERAL_CHANNEL, "Whisper failed: User %s not found.\n", targetUser);
            }
        }
    }

    // Check if buffer contains a complete message (ends with \r\n or \n)
    char* find_message_end(char* buf, uint16_t len) {
        uint16_t j;
        for (j = 0; j < len; j++) {
            if (buf[j] == '\n') {
                return &buf[j];
            }
        }
        return NULL;
    }

    event void read_write.fired(){
        int i;
        uint8_t read_buff[BUFF_SIZE];
        uint16_t bytes_read, bytes_written;
        char* msg_end;
        char complete_msg[BUFF_SIZE];
        uint16_t msg_len;

        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].isActive) {
                
                // READ - accumulate data in recv_buff
                bytes_read = call Transport.read(i, read_buff, BUFF_SIZE - sockets[i].recv_len - 1);
                if (bytes_read > 0) {
                    // Append to receive buffer
                    memcpy(&sockets[i].recv_buff[sockets[i].recv_len], read_buff, bytes_read);
                    sockets[i].recv_len += bytes_read;
                    sockets[i].recv_buff[sockets[i].recv_len] = '\0';
                    
                    // Process all complete messages in buffer
                    while ((msg_end = find_message_end((char*)sockets[i].recv_buff, sockets[i].recv_len)) != NULL) {
                        msg_len = (msg_end - (char*)sockets[i].recv_buff) + 1;
                        
                        // Copy complete message
                        memcpy(complete_msg, sockets[i].recv_buff, msg_len);
                        complete_msg[msg_len] = '\0';
                        
                        // Remove processed message from buffer
                        memmove(sockets[i].recv_buff, &sockets[i].recv_buff[msg_len], sockets[i].recv_len - msg_len + 1);
                        sockets[i].recv_len -= msg_len;
                        
                        // Process the complete message
                        if (TOS_NODE_ID == 1) {
                            server_parse_input(i, complete_msg);
                        } else {
                            // Strip \r\n for display
                            char* ptr = complete_msg;
                            while (*ptr) {
                                if (*ptr == '\r' || *ptr == '\n') { *ptr = '\0'; break; }
                                ptr++;
                            }
                            dbg(GENERAL_CHANNEL, "Client Received: %s\n", complete_msg);
                        }
                    }
                }

                // WRITE
                if (sockets[i].written < sockets[i].curr) {
                    uint16_t to_write = sockets[i].curr - sockets[i].written;
                    bytes_written = call Transport.write(i, &sockets[i].send_buff[sockets[i].written], to_write);
                    
                    if (bytes_written > 0) {
                        sockets[i].written += bytes_written;
                    }

                    if (sockets[i].written == sockets[i].curr) {
                        sockets[i].written = 0;
                        sockets[i].curr = 0;
                    }
                }
            }
        }
    }
}
