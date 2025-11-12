#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/tcp_payload.h"

generic module TransportP(){
    provides interface Transport;

    uses interface Random;
    uses interface Queue<tcp_payload_t> as connectionQueue;
    uses interface IP;
}
implementation{
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    tcp_payload_t p;

    void makePack(tcp_payload_t* payload, uint8_t flags, uint16_t seq, uint8_t dest_port, uint8_t src_port, uint16_t src_addr);
    uint8_t findFD(uint8_t src_port, uint16_t src_addr);

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
        socket_t fd = findFD(package->srcPort, package->src_addr);
        dbg(ROUTING_CHANNEL, "Recieved flag is %u found fd is %u\n?", package->flags, fd);
        if(fd != NULL_SOCKET){
            if(package->flags == SYN_ACK && sockets[fd].state == SYN_SENT){
                //SIGNAL THE ESTABLISHED EVENT
                dbg(TRANSPORT_CHANNEL, "NODE %u received SYN+ACK from NODE %u PORT %u, moving to ESTABLISHED\n", TOS_NODE_ID, package->src_addr, package->srcPort);
                sockets[fd].state == ESTABLISHED;
                makePack(&p, ACK, package->seq, package->srcPort, sockets[fd].src, TOS_NODE_ID);
                call IP.buildIP(package->src_addr, PROTOCOL_TCP, &p);
                return SUCCESS;
            }
            else if(package->flags == ACK && sockets[fd].state == SYN_RCVD){
                //SIGNAL ESTABLISHED EVENT
                dbg(TRANSPORT_CHANNEL, "NODE %u: ACK received from NODE %u PORT %u, moving to ESTABLISHED\n", TOS_NODE_ID, package->src_addr, package->srcPort);
                return SUCCESS;
            }
        }
        else if(package->flags == SYN){
            call connectionQueue.enqueue(*package);
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

    command error_t Transport.close(socket_t fd){}

    command error_t Transport.release(socket_t fd){}

    command error_t Transport.listen(socket_t fd){
        if(sockets[fd].state == CLOSED){
            sockets[fd].state = LISTEN;
            dbg(TRANSPORT_CHANNEL, "NODE %u, SOCKET %u PORT %u is now LISTENING\n", TOS_NODE_ID, fd, sockets[fd].src);
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

    uint8_t findFD(uint8_t src_port, uint16_t src_addr){
        uint8_t i = 0;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].dest.port == src_port && sockets[i].dest.addr == src_addr){
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