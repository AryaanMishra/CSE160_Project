#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/tcp_payload.h"

generic module TransportP(){
    provides interface Transport;

    uses interface Random;
    uses interface Queue<new_conn_t> as connectionQueue;
    uses interface IP;
    uses interface Timer<TMilli> as timer_wait;
    uses interface Timer<TMilli> as send_timer;
}
implementation{
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    tcp_payload_t p;

    void makePack(tcp_payload_t* payload, uint8_t flags, uint8_t ack, uint16_t seq, uint8_t dest_port, uint8_t src_port, uint8_t window);

    void clear_socket(socket_t fd){
        sockets[fd].flag = 0;
        sockets[fd].state = CLOSED;
        sockets[fd].lastWritten = 0;
        sockets[fd].lastAck = 0;
        sockets[fd]. lastSent = 0;
        sockets[fd].lastRead = 0;
        sockets[fd].lastRcvd = 0;
        sockets[fd].nextExpected = 0;
        sockets[fd].RTT = 1000;
        sockets[fd].effectiveWindow = SOCKET_BUFFER_SIZE;
    }

    command socket_t Transport.socket(){
        uint8_t i;
        socket_t fd = NULL_SOCKET;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if (sockets[i].flag == 0){
                fd = i;
                clear_socket(fd);
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
        new_conn_t newConn;
        socket_t newFd = NULL_SOCKET;
        if(sockets[fd].state == LISTEN){
            if(!call connectionQueue.empty()){
                newConn = call connectionQueue.dequeue();
                if(newConn.payload.destPort == sockets[fd].src){
                    newFd = call Transport.socket();
                    if(newFd != NULL_SOCKET){
                        sockets[newFd] = sockets[fd];
                        sockets[newFd].dest.addr = newConn.src;
                        sockets[newFd].dest.port = newConn.payload.srcPort;
                        sockets[newFd].state = SYN_RCVD;
                        makePack(&p, SYN, 1, 0, sockets[newFd].dest.port, sockets[newFd].src, sockets[newFd].effectiveWindow);
                        call IP.buildIP(sockets[newFd].dest.addr, PROTOCOL_TCP, &p);
                    }
                }
            }
        }
        return newFd;
    }


    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){
        uint8_t i = sockets[fd].lastWritten;
        uint8_t next;
        uint8_t j = 0;

        if(sockets[fd].flag == 0 || sockets[fd].state != ESTABLISHED){
            dbg(TRANSPORT_CHANNEL, "UNABLE TO WRITE\n");
            return 0;
        }

        while(j < bufflen){
            next = i+1;
            if(next == SOCKET_BUFFER_SIZE){
                next = 0;
            }
            if(next == sockets[fd].lastAck){
                sockets[fd].sendBuff[i] = buff[j]; 
                dbg(TRANSPORT_CHANNEL, "NODE %u Port %u wrote %u at pos %u\n", TOS_NODE_ID, sockets[fd].src, sockets[fd].sendBuff[i], i);
                j++;
                break;
            }
            sockets[fd].sendBuff[i] = buff[j]; 
            dbg(TRANSPORT_CHANNEL, "NODE %u Port %u wrote %u at pos %u\n", TOS_NODE_ID, sockets[fd].src, sockets[fd].sendBuff[i], i);
            i = next;
            j++;
        }
        sockets[fd].lastWritten = i;
        return j;
    }


    command error_t Transport.receive(tcp_payload_t* package, uint16_t src_addr){
        socket_t fd = call Transport.findFD(package->srcPort, src_addr);
        if(fd != NULL_SOCKET){
            if(package->ack == 1){
                if(package->flags == SYN && sockets[fd].state == SYN_SENT){
                    //SIGNAL THE ESTABLISHED EVENT
                    dbg(TRANSPORT_CHANNEL, "NODE %u received SYN+ACK from NODE %u PORT %u, moving to ESTABLISHED\n", TOS_NODE_ID, src_addr, package->srcPort);
                    sockets[fd].state = ESTABLISHED;
                    sockets[fd].effectiveWindow = package->window;
                    makePack(&p, NONE, 1, package->seq, package->srcPort, sockets[fd].src, sockets[fd].effectiveWindow);
                    call IP.buildIP(src_addr, PROTOCOL_TCP, &p);
                    call send_timer.startPeriodic(3000 + (call Random.rand16()%500));
                    return SUCCESS;
                }
                else if(sockets[fd].state == SYN_RCVD){
                    //SIGNAL ESTABLISHED EVENT
                    dbg(TRANSPORT_CHANNEL, "NODE %u: ACK received from NODE %u PORT %u, moving to ESTABLISHED\n", TOS_NODE_ID, src_addr, package->srcPort);
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
                    call timer_wait.startOneShot(300000 + (call Random.rand16()%300));
                    return SUCCESS;
                }
            }
        }
        else if(package->flags == SYN){
            new_conn_t conn;
            conn.payload = *package;
            conn.src = src_addr;

            call connectionQueue.enqueue(conn);
            dbg(TRANSPORT_CHANNEL, "NODE %u received SYN from NODE %u PORT %u\n", TOS_NODE_ID, src_addr, package->srcPort);
            return SUCCESS;
        }
        return FAIL;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){}

    command error_t Transport.connect(socket_t fd, socket_addr_t * addr){
        makePack(&p, SYN, 0, 0, addr->port, sockets[fd].src, sockets[fd].effectiveWindow);
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
            makePack(&p, FIN, 0, 0, sockets[fd].dest.port, sockets[fd].src, sockets[fd].effectiveWindow);
            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);
            return SUCCESS;
        }
        else if(sockets[fd].state == CLOSE_WAIT){
            sockets[fd].state = LAST_ACK;
            dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO LAST_ACK\n", TOS_NODE_ID, sockets[fd].src);

            makePack(&p, FIN, 0, 0, sockets[fd].dest.port, sockets[fd].src, TOS_NODE_ID);
            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);

            if(sockets[fd].lastRcvd == sockets[fd].nextExpected){
                sockets[fd].state = CLOSED;
                dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO CLOSED\n", TOS_NODE_ID, sockets[fd].src);
                clear_socket(fd);
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

    event void send_timer.fired(){
    }

    event void timer_wait.fired(){
        uint8_t i;
        for(i = 0; i< MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].state == TIME_WAIT){
                sockets[i].state = CLOSED;
                dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO CLOSED\n", TOS_NODE_ID, sockets[i].src);
                clear_socket(i);
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


    void makePack(tcp_payload_t* payload, uint8_t flags, uint8_t ack, uint16_t seq, uint8_t dest_port, uint8_t src_port, uint8_t window){
        payload->flags = flags;
        payload->ack = ack;
        payload->seq = seq;
        payload->destPort = dest_port;
        payload->srcPort = src_port;
        payload->window = window;
    }

}