#include "../../includes/socket.h"

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
        sockets[newFd].isActive = TRUE;
        dbg(TRANSPORT_CHANNEL, "Accepting Things");
        if(!(call read_write.isRunning())){
            call read_write.startPeriodic(30000);
        }
        return FAIL;
    }

    command error_t App.connect_done(socket_t fd){
        return FAIL;
    }

    command void App.initialize_server(socket_port_t port){
        socket_addr_t addr;
        dbg(TRANSPORT_CHANNEL, "NODE %u OPENING PORT: %u\n", TOS_NODE_ID, port);
        global_fd = call Transport.socket();
        addr.addr = TOS_NODE_ID;
        addr.port = port;
        call Transport.bind(global_fd, &addr);
        call Transport.listen(global_fd);
    }

    command error_t App.handle_command(char* msg){
        char extract [3][32] = {{0}};
        socket_addr_t src_addr;
        socket_addr_t dest_addr;
        error_t bindResult;

        extract_word(&msg[0], extract[0], 1); //command type
        dbg(TRANSPORT_CHANNEL, "Extract: %s\n", extract[0]);

        if(strcmp(extract[0], "hello") == 0){
            extract_word(&msg[0], extract[2], 3); //extracts port
            dbg(TRANSPORT_CHANNEL, "Extract: %s\n", extract[2]);

            src_addr.addr = TOS_NODE_ID;
            src_addr.port = *(socket_port_t *)extract[2];

            dest_addr.addr = 1;
            dest_addr.port = 41;
            
            global_fd = call Transport.socket();
            bindResult = call Transport.bind(global_fd, &src_addr);
            if(bindResult == SUCCESS){
                //create a structure to handle commands
                sockets[global_fd].isActive = TRUE;
                dbg(TRANSPORT_CHANNEL, "NODE %u SOCKET INITIALIZED, IS ACTIVE TRUE\n", TOS_NODE_ID);
            }

            call Transport.connect(global_fd, &dest_addr);
            dbg(TRANSPORT_CHANNEL, "NODE %u CONNECT CALLED\n", TOS_NODE_ID);     
        }
        return FAIL;
    }

    event void read_write.fired(){
        
    }
}