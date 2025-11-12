#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/tcp_payload.h"

generic module TransportP(){
    provides interface Transport;

    uses interface Random;
    uses interface Queue<tcp_payload_t> as connectionQueue;
    uses interface IP;
    uses interface Timer<TMilli> as timer_wait;
}
implementation{
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    tcp_payload_t p;

    void makePack(tcp_payload_t* payload, uint8_t flags, uint16_t seq, uint8_t dest_port, uint8_t src_port, uint16_t src_addr);

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
        sockets[fd].flag = 1; // mark socket as in-use
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
                        makePack(&p, SYN_ACK, 0, sockets[newFd].dest.port, sockets[newFd].src, TOS_NODE_ID);
                        call IP.buildIP(sockets[newFd].dest.addr, PROTOCOL_TCP, &p);
                    }
                }
            }
        }
        return newFd;
    }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){}

    command error_t Transport.receive(tcp_payload_t* package){
        socket_t fd = call Transport.findFD(package->srcPort, package->src_addr);
        if(fd != NULL_SOCKET){
            if(package->flags == SYN_ACK && sockets[fd].state == SYN_SENT){
                //SIGNAL THE ESTABLISHED EVENT
                dbg(TRANSPORT_CHANNEL, "NODE %u received SYN+ACK from NODE %u PORT %u, moving to ESTABLISHED\n", TOS_NODE_ID, package->src_addr, package->srcPort);
                sockets[fd].state = ESTABLISHED;
                makePack(&p, ACK, package->seq, package->srcPort, sockets[fd].src, TOS_NODE_ID);
                call IP.buildIP(package->src_addr, PROTOCOL_TCP, &p);
                return SUCCESS;
            }
            else if(package->flags == ACK){
                //SIGNAL ESTABLISHED EVENT
                if(sockets[fd].state == SYN_RCVD){
                    dbg(TRANSPORT_CHANNEL, "NODE %u: ACK received from NODE %u PORT %u, moving to ESTABLISHED\n", TOS_NODE_ID, package->src_addr, package->srcPort);
                    sockets[fd].state = ESTABLISHED;
                    return SUCCESS;
                }
                else if(sockets[fd].state == FIN_WAIT){
                    if(sockets[fd].lastWritten == sockets[fd].lastSent){
                            sockets[fd].state = FIN_WAIT2;
                            dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO FIN_WAIT2\n", TOS_NODE_ID, sockets[fd].src);
                            return SUCCESS;
                        }
                }
            }
            else if(package->flags == FIN){
                if(sockets[fd].state == ESTABLISHED){
                    sockets[fd].state = CLOSE_WAIT;
                    dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO CLOSE_WAIT\n", TOS_NODE_ID, sockets[fd].src);
                    return SUCCESS;
                }
                else if(sockets[fd].state == FIN_WAIT2){
                    sockets[fd].state = TIME_WAIT;
                    dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO TIME_WAIT\n", TOS_NODE_ID, sockets[fd].src);
                    call timer_wait.startOneShot(30000 + (call Random.rand16()%300));
                    return SUCCESS;
                }
            }
        }
        else if(package->flags == SYN){
            call connectionQueue.enqueue(*package);
            dbg(TRANSPORT_CHANNEL, "NODE %u received SYN from NODE %u PORT %u\n", TOS_NODE_ID, package->src_addr, package->srcPort);
            return SUCCESS;
        }
        return FAIL;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){}

    command error_t Transport.connect(socket_t fd, socket_addr_t * addr){
        makePack(&p, SYN, 0, addr->port, sockets[fd].src, TOS_NODE_ID);
        dbg(TRANSPORT_CHANNEL, "Transport.connect: building SYN payload\n");
        sockets[fd].dest.addr = addr->addr;
        sockets[fd].dest.port = addr->port;
        call IP.buildIP(addr->addr, PROTOCOL_TCP, &p);
        sockets[fd].state = SYN_SENT;
        return SUCCESS;
    }

    command error_t Transport.close(socket_t fd){
        if(sockets[fd].state == ESTABLISHED){
            sockets[fd].state = FIN_WAIT;
            //write remaining data in the current buffer
            dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO FIN_WAIT\n", TOS_NODE_ID, sockets[fd].src);
            
            if(sockets[fd].lastWritten == sockets[fd].lastSent){
                sockets[fd].state = FIN_WAIT2;
                dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO FIN_WAIT2\n", TOS_NODE_ID, sockets[fd].src);
            }
            makePack(&p, FIN, 0, sockets[fd].dest.port, sockets[fd].src, TOS_NODE_ID);
            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);
            return SUCCESS;
        }
        else if(sockets[fd].state == CLOSE_WAIT){
            sockets[fd].state = LAST_ACK;
            dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO LAST_ACK\n", TOS_NODE_ID, sockets[fd].src);

            makePack(&p, FIN, 0, sockets[fd].dest.port, sockets[fd].src, TOS_NODE_ID);
            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);

            if(sockets[fd].lastRcvd == sockets[fd].nextExpected){
                sockets[fd].state = CLOSED;
                dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO CLOSED\n", TOS_NODE_ID, sockets[fd].src);
                sockets[fd].state = 0;
            }
            
            return SUCCESS; 
        }
        return FAIL;
    }

    command error_t Transport.release(socket_t fd){}

    command error_t Transport.listen(socket_t fd){
        if(sockets[fd].state == CLOSED){
            sockets[fd].state = LISTEN;
            dbg(TRANSPORT_CHANNEL, "NODE %u, SOCKET %u PORT %u is now LISTENING\n", TOS_NODE_ID, fd, sockets[fd].src);
            return SUCCESS;
        }
        return FAIL;
    }

    event void timer_wait.fired(){
        uint8_t i;
        for(i = 0; i< MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].state == TIME_WAIT){
                sockets[i].state = CLOSED;
                sockets[i].flag = 0;
                dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO CLOSED\n", TOS_NODE_ID, sockets[i].src);
            }
        }
    }

    command void Transport.initializeSockets(){
        uint8_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            sockets[i].flag = 0;
        }
    }

    command uint8_t Transport.findFD(uint8_t src_port, uint16_t src_addr){
        uint8_t i = 0;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].dest.port == src_port && sockets[i].dest.addr == src_addr && sockets[i].flag == 1){
                return i;
            }
        }
        return NULL_SOCKET;
    }

    void makePack(tcp_payload_t* payload, uint8_t flags, uint16_t seq, uint8_t dest_port, uint8_t src_port, uint16_t src_addr){
        payload->flags = flags;
        payload->seq = seq;
        payload->destPort = dest_port;
        payload->srcPort = src_port;
        payload->src_addr = src_addr;
    }

}