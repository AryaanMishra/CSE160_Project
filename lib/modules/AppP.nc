#include "../../includes/socket.h"
#include "../../includes/app_structs.h"

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
            if(!(call read_write.isRunning())){
                call read_write.startPeriodic(30000);
            }
            call read_write.startPeriodic(30000);
            return SUCCESS;
        }
        else {
            return FAIL;
        }
    }

    command error_t App.connect_done(socket_t fd){
        if(!(call read_write.isRunning())){
            call read_write.startPeriodic(30000);
        }
        call read_write.startPeriodic(30000);
        return SUCCESS;
    }

    error_t hello_cmd(char* msg){
        socket_addr_t src_addr;
        socket_addr_t dest_addr;
        error_t bindResult;
        char extract[32] = {0};
        uint16_t len;
        size_t remaining_size;

        extract_word(msg, extract, 3); //extracts port

        src_addr.addr = TOS_NODE_ID;
        src_addr.port = (socket_port_t)atoi(extract);
        dbg(TRANSPORT_CHANNEL, "Extract: %u\n", src_addr.port);
        dest_addr.addr = 1;
        dest_addr.port = 41;
        
        global_fd = call Transport.socket();
        bindResult = call Transport.bind(global_fd, &src_addr);
        if(bindResult == SUCCESS){
            //create a structure to handle commands
            sockets[global_fd].isActive = TRUE;
            sockets[global_fd].written = 0;
            sockets[global_fd].curr = 0;               
            dbg(TRANSPORT_CHANNEL, "NODE %u SOCKET INITIALIZED, IS ACTIVE TRUE\n", TOS_NODE_ID);
        }

        call Transport.connect(global_fd, &dest_addr);
        dbg(TRANSPORT_CHANNEL, "NODE %u CONNECT CALLED\n", TOS_NODE_ID);

        memset(extract, 0, sizeof(extract));
        extract_word(msg, extract, 2);

        if(BUFF_SIZE - sockets[global_fd].curr < sizeof(extract) -1 ){
            return FAIL;
        }
        remaining_size = BUFF_SIZE - sockets[global_fd].curr;
        len = snprintf((char *)&sockets[global_fd].send_buff[sockets[global_fd].written], 
            remaining_size, "Hello %s", extract);
        dbg(TRANSPORT_CHANNEL, "len: %u\n", len);
        sockets[global_fd].curr += len + 1;

        return SUCCESS;    
    }

    error_t build_buff(char* msg, socket_t fd){
        size_t remaining_size = BUFF_SIZE - sockets[global_fd].written;
        uint8_t len;
        if(remaining_size < sizeof(msg)){
            return FAIL;
        }
        else{
            len = snprintf((char *)&sockets[fd].send_buff[sockets[global_fd].written], remaining_size, "%s", msg);
            dbg(TRANSPORT_CHANNEL, "len: %u\n", len);
            sockets[global_fd].curr += len + 1;
        }
        return SUCCESS;
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
        char extract [32];
        error_t status;

        memset(extract, 0, sizeof(extract));

        extract_word(msg, extract, 1); //command type

        if(strcmp(extract, "hello\0") == 0){ //hello command requires additional steps compared to other commands
            status = hello_cmd(msg);
        }
        else if(strcmp(extract, "msg") == 0){
            socket_t fd = call Transport.findFD(41, 1);
            status = build_buff(msg, fd);
        }
        return status;
    }

    event void read_write.fired(){
        uint8_t len;
        uint8_t i;
        //this will work for now, but is bad practice. Need to better handle buffer size
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].isActive){
                uint16_t send_size = sockets[i].curr - sockets[i].written;
                dbg(TRANSPORT_CHANNEL, "Send size: %u\n", send_size);
                if(send_size != 0){
                    len = call Transport.write(i, &sockets[i].send_buff[sockets[i].written], send_size);
                    sockets[i].written += len;
                }
            }
        }
    }
}