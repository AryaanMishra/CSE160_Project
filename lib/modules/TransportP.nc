#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/tcp_payload.h"

generic module TransportP(){
    provides interface Transport;

    uses interface Queue<tcp_payload_t> as connectionQueue;
}
implementation{
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    tcp_payload_t payload;

    command socket_t Transport.socket(){
        uint8_t i;
        socket_t fd = NULL_SOCKET;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if (sockets[i].flag == 0){
                fd = i;
                return fd;
            }
        }
        return fd;
    } 

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr){
        sockets[fd].src = addr->port;
        sockets[fd].state = CLOSED;
        return SUCCESS;
    }

    command socket_t Transport.accept(socket_t fd){
        tcp_payload_t newConn;
        socket_t newFd = NULL_SOCKET;
        if(sockets[fd].state == LISTEN){
            if(!call connectionQueue.empty()){
                newConn = call connectionQueue.dequeue();
                if(newConn.destPort == sockets[fd].src){
                    newFd = call Transport.socket();
                    if(newFd != NULL_SOCKET){
                        sockets[newFd] = sockets[fd];
                        sockets[newFd].dest.addr = newConn.src_addr;
                        sockets[newFd].dest.port = newConn.srcPort;
                        sockets[newFd].state = SYN_RCVD;
                    }
                }
            }
        }
        return newFd;
    }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){}

    command error_t Transport.receive(pack* package){}

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){}

    command error_t Transport.connect(socket_t fd, socket_addr_t * addr){}

    command error_t Transport.close(socket_t fd){}

    command error_t Transport.release(socket_t fd){}

    command error_t Transport.listen(socket_t fd){
        if(sockets[fd].state == CLOSED){
            sockets[fd].state = LISTEN;
            return SUCCESS;
        }
        return FAIL;
    }

    command void Transport.initializeSockets(){
        uint8_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            sockets[i].flag = 0;
        }
    }

}