#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/tcp_payload.h"

generic module TransportP(){
    provides interface Transport;

    uses interface Random;
    uses interface Queue<new_conn_t> as connectionQueue;
    uses interface IP;
    uses interface Timer<TMilli> as timer_wait;
    uses interface Timer<TMilli> as retransmit_timer;
    uses interface Queue<packet_send_t> as resend_queue;
}
implementation{
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    tcp_payload_t p;
    uint8_t data[TCP_PAYLOAD_SIZE];

    void makePack(tcp_payload_t* package, uint8_t flags, uint8_t ack, uint8_t seq, uint8_t dest_port, uint8_t src_port, uint8_t window, uint8_t len, uint8_t* payload);
    void resend_helper(tcp_payload_t payload, uint16_t RTT, uint8_t fd);
    bool wrap_checker(uint8_t seq1, uint8_t seq2);

    void clear_socket(socket_t fd){
        sockets[fd].flag = 0;
        sockets[fd].state = CLOSED;
        sockets[fd].lastWritten = 0;
        sockets[fd].lastAck = 0;
        sockets[fd]. lastSent = 0;
        sockets[fd].lastRead = 0;
        sockets[fd].lastRcvd = 0;
        sockets[fd].nextExpected = 0;
        sockets[fd].RTT = 50000;
        sockets[fd].effectiveWindow = SOCKET_BUFFER_SIZE;
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
        uint8_t ISN;
        socket_t newFd = NULL_SOCKET;
        new_conn_t newConn;
        if(sockets[fd].state == LISTEN){
            if(!call connectionQueue.empty()){
                newConn = call connectionQueue.dequeue();
                if(newConn.payload.destPort == sockets[fd].src){
                    newFd = call Transport.findFD(newConn.payload.srcPort, newConn.src);
                    if(newFd != NULL_SOCKET){
                        return NULL_SOCKET;
                    }
                }
                if(newConn.payload.destPort == sockets[fd].src){
                    newFd = call Transport.socket();
                    if(newFd != NULL_SOCKET){
                        ISN = call Random.rand16()%256;
                        sockets[newFd] = sockets[fd];
                        sockets[newFd].dest.addr = newConn.src;
                        sockets[newFd].dest.port = newConn.payload.srcPort;
                        sockets[newFd].state = SYN_RCVD;
                        sockets[newFd].nextExpected = newConn.payload.seq + 1;
                        sockets[newFd].effectiveWindow = newConn.payload.window;

                        sockets[newFd].lastWritten = ISN+1;
                        sockets[newFd].lastAck = ISN+1;
                        sockets[newFd].lastSent = ISN+1;
                        makePack(&p, SYN_ACK, newConn.payload.seq+1, ISN, sockets[newFd].dest.port, sockets[newFd].src, sockets[newFd].effectiveWindow, 0, &data[0]);
                        dbg(TRANSPORT_CHANNEL, "Accepting client: Sending SYN+ACK, seq:%u ack: %u\n", ISN, newConn.payload.seq+1);
                        call IP.buildIP(sockets[newFd].dest.addr, PROTOCOL_TCP, &p);
                    }
                }
            }
        }
        return newFd;
    }

    uint8_t get_distance(uint8_t seqA, uint8_t seqB){
        return (uint8_t)(seqA - seqB);
    }

    void send_data(socket_t fd){
        uint8_t send_idx;
        uint8_t available_data;
        uint8_t window_remaining;
        uint8_t k;
        uint8_t bytes_to_send;
        uint8_t seq_to_send;
        uint8_t in_flight;
        send_idx = sockets[fd].lastSent;
        available_data = get_distance(sockets[fd].lastWritten, sockets[fd].lastSent);

        while(available_data > 0){

            in_flight = get_distance(sockets[fd].lastSent, sockets[fd].lastAck);

            if(in_flight >= sockets[fd].effectiveWindow){
                break; 
            }
            
            window_remaining = sockets[fd].effectiveWindow - in_flight;
            
            bytes_to_send = (available_data < TCP_PAYLOAD_SIZE) ? available_data : TCP_PAYLOAD_SIZE;
            bytes_to_send = (bytes_to_send < window_remaining) ? bytes_to_send : window_remaining;

            if(bytes_to_send == 0){
                break;
            }

            seq_to_send = send_idx;
            
            for(k = 0; k < bytes_to_send; k++){
                data[k] = sockets[fd].sendBuff[(send_idx + k) % SOCKET_BUFFER_SIZE];
            }

            dbg(TRANSPORT_CHANNEL, "SENDING PACKET seq: %u, len: %u, window: %u\n", seq_to_send, bytes_to_send, sockets[fd].effectiveWindow);
            
            makePack(&p, NONE, sockets[fd].nextExpected, seq_to_send, sockets[fd].dest.port, sockets[fd].src, SOCKET_BUFFER_SIZE - get_distance(sockets[fd].lastRcvd, sockets[fd].lastRead), bytes_to_send, &data[0]);

            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);
            
            resend_helper(p, sockets[fd].RTT, fd);
            
            sockets[fd].lastSent += bytes_to_send; 
            send_idx += bytes_to_send; 
            available_data -= bytes_to_send; 
        }
    }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen){
        uint8_t i = sockets[fd].lastWritten;
        uint16_t j = 0;
        uint16_t bytes_to_write;
        uint8_t occupied;

        if(sockets[fd].flag == 0 || sockets[fd].state != ESTABLISHED){
            return 0;
        }
        
        occupied = (uint8_t)(sockets[fd].lastWritten - sockets[fd].lastAck);
        dbg(TRANSPORT_CHANNEL, "Occupied: %u, last written: %u, last ack: %u\n", occupied, sockets[fd].lastWritten, sockets[fd].lastAck);
        if (occupied >= SOCKET_BUFFER_SIZE) {
            send_data(fd); 
            return 0; 
        }

        bytes_to_write = SOCKET_BUFFER_SIZE - occupied - 1;
        bytes_to_write = (bufflen < bytes_to_write) ? bufflen : bytes_to_write;

        while(j < bytes_to_write){
            sockets[fd].sendBuff[i % SOCKET_BUFFER_SIZE] = buff[j]; 
            i++; 
            j++;
            sockets[fd].lastWritten++;
        }
        send_data(fd);  
        return j; 
    }


    command error_t Transport.receive(tcp_payload_t* package, uint16_t src_addr){
        socket_t fd = call Transport.findFD(package->srcPort, src_addr);
        uint8_t new_seq;
        
        if(fd != NULL_SOCKET){
            
            if(package->flags == ACK){
                bool is_newer = wrap_checker(package->ack, sockets[fd].lastAck);
                bool in_range = wrap_checker(sockets[fd].lastWritten, package->ack);
                if(sockets[fd].state != CLOSED && in_range){
                    if(is_newer){
                        sockets[fd].lastAck = package->ack;
                        dbg(TRANSPORT_CHANNEL, "Received ACK, updating last ack: %u\n", sockets[fd].lastAck);
                    } 
                    else if(package->ack == sockets[fd].lastAck){
                        dbg(TRANSPORT_CHANNEL, "Received duplicate ack: %u\n", package->ack);
                    } 
                    else {
                        return FAIL;
                    }

                } else {
                    return FAIL;
                }

                if(call retransmit_timer.isRunning() && !call resend_queue.empty()){
                    uint32_t now = call retransmit_timer.getNow();
                    packet_send_t next = call resend_queue.head();
                    uint32_t time_until_timeout = next.timeout > now ? next.timeout - now : 1;
                    call retransmit_timer.startOneShot(time_until_timeout);
                }

                while(!call resend_queue.empty()){
                    packet_send_t sent = call resend_queue.head();
                    if(sent.fd == fd){
                        uint8_t next_seq = sent.payload.seq + sent.payload.payload_len;
                        if(sent.payload.flags & (SYN || FIN || SYN_ACK)){
                            next_seq++;
                        }
                        if(wrap_checker(sockets[fd].lastAck, next_seq)){
                            call resend_queue.dequeue();
                            dbg(TRANSPORT_CHANNEL, "NODE %u: ACK received removing package seq: %u\n", TOS_NODE_ID, sent.payload.seq);
                        } else {
                            break; 
                        }
                    } else {
                        break;
                    }
                }

                if(sockets[fd].state == SYN_RCVD){
                    dbg(TRANSPORT_CHANNEL, "NODE %u: ACK received, moving to ESTABLISHED\n", TOS_NODE_ID);
                    sockets[fd].state = ESTABLISHED;

                    return SUCCESS;        
                }
                else if(sockets[fd].state == FIN_WAIT){
                    if(sockets[fd].lastWritten == package->ack){
                        sockets[fd].state = FIN_WAIT2;
                        dbg(TRANSPORT_CHANNEL, "NODE: %u MOVING TO FIN_WAIT2\n", TOS_NODE_ID);
                        return SUCCESS;
                    }
                }
                else if(sockets[fd].state == LAST_ACK){
                    sockets[fd].state = CLOSED;
                    dbg(TRANSPORT_CHANNEL, "NODE: %u MOVING TO CLOSED\n", TOS_NODE_ID);
                    return SUCCESS;
                }
                else{
                    sockets[fd].effectiveWindow = package->window;
                    return SUCCESS;
                }
            }

            // HANDLE DATA
            else if(sockets[fd].state == ESTABLISHED && package->flags == NONE){
                uint8_t i;
                uint8_t advertised_window;
                
                if(package->seq != sockets[fd].nextExpected){
                    return FAIL;
                }

                for(i = 0; i < package->payload_len; i++){
                    advertised_window = SOCKET_BUFFER_SIZE - get_distance(sockets[fd].lastRcvd, sockets[fd].lastRead);
                    if(advertised_window != 0){
                        sockets[fd].rcvdBuff[sockets[fd].lastRcvd % SOCKET_BUFFER_SIZE] = package->payload[i];
                        sockets[fd].lastRcvd++;
                    }
                }
                advertised_window = SOCKET_BUFFER_SIZE - get_distance(sockets[fd].lastRcvd, sockets[fd].lastRead);
                sockets[fd].nextExpected = package->seq + i;
                dbg(TRANSPORT_CHANNEL, "Received data: seq: %u Next Expected: %u\n", package->seq, sockets[fd].nextExpected);
                
                makePack(&p, ACK, sockets[fd].nextExpected, 0, package->srcPort, sockets[fd].src, advertised_window, 0, &data[0]);
                call IP.buildIP(src_addr, PROTOCOL_TCP, &p);
                return SUCCESS;
            }

            else if(package->flags == SYN_ACK && sockets[fd].state == SYN_SENT){
                //SIGNAL THE ESTABLISHED EVENT
                dbg(TRANSPORT_CHANNEL, "NODE %u received SYN+ACK from NODE %u PORT %u, moving to ESTABLISHED\n", TOS_NODE_ID, src_addr, package->srcPort);
                sockets[fd].state = ESTABLISHED;
                sockets[fd].effectiveWindow = package->window;
                sockets[fd].lastWritten = package->ack;
                sockets[fd].lastSent = package->ack;
                sockets[fd].lastAck = package->ack;

                sockets[fd].lastRead = package->seq+1;
                sockets[fd].lastRcvd = package->seq+1;
                sockets[fd].nextExpected = package->seq+1;

                new_seq = package->seq + 1;
                dbg(TRANSPORT_CHANNEL, "RECEIVED SYN+ACK: seq: %u, ack: %u\n", package->seq, package->ack);
                dbg(TRANSPORT_CHANNEL, "SENDING ACK, Ack: %u\n", new_seq);

                makePack(&p, ACK, sockets[fd].nextExpected, 1, package->srcPort, sockets[fd].src, sockets[fd].effectiveWindow, 0, &data[0]);
                call IP.buildIP(src_addr, PROTOCOL_TCP, &p);
                return SUCCESS;
            }
            
            else if(package->flags == FIN){
                dbg(TRANSPORT_CHANNEL, "Next Expected: %u\n", sockets[fd].nextExpected);
                if(package->seq == sockets[fd].nextExpected) {
                    sockets[fd].nextExpected++; 

                    makePack(&p, ACK, sockets[fd].nextExpected, 0, package->srcPort, sockets[fd].src, sockets[fd].effectiveWindow, 0, &data[0]);
                    call IP.buildIP(src_addr, PROTOCOL_TCP, &p);

                    if(sockets[fd].state == ESTABLISHED){
                        sockets[fd].state = CLOSE_WAIT;
                        call Transport.close(fd); 
                        dbg(TRANSPORT_CHANNEL, "Recv FIN. ACKing %u. Moving to CLOSE_WAIT.\n", sockets[fd].nextExpected);
                        return SUCCESS;
                    }
                    else if(sockets[fd].state == FIN_WAIT2){
                        sockets[fd].state = TIME_WAIT;
                        dbg(TRANSPORT_CHANNEL, "Recv FIN. ACKing %u. Moving to TIME_WAIT.\n", sockets[fd].nextExpected);
                        call timer_wait.startOneShot(30000 + (call Random.rand16()%300));
                        return SUCCESS;
                    }
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
        dbg(TRANSPORT_CHANNEL, "next expected: %u\n", sockets[fd].nextExpected);
        return FAIL;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){
        uint8_t i = sockets[fd].lastRead;
        uint16_t j = 0;
        uint16_t bytes_to_read;
        uint8_t old_window;
        uint8_t new_data;
        uint8_t new_window;
        
        uint8_t available_data = get_distance(sockets[fd].lastRcvd, sockets[fd].lastRead);

        if(sockets[fd].flag == 0 || sockets[fd].state != ESTABLISHED){
            return 0;
        }

        bytes_to_read = (bufflen < available_data) ? bufflen : available_data;
        
        dbg(TRANSPORT_CHANNEL, "READ: Requested %u bytes, Available %u bytes, Reading %u bytes, window: %u\n", bufflen, available_data, bytes_to_read, sockets[fd].effectiveWindow);

        while(j < bytes_to_read){ 
            buff[j] = sockets[fd].rcvdBuff[i % SOCKET_BUFFER_SIZE]; 
            i++; 
            j++;
        }
        sockets[fd].lastRead = i;
        old_window = SOCKET_BUFFER_SIZE - available_data;
        new_data = get_distance(sockets[fd].lastRcvd, sockets[fd].lastRead);
        new_window = SOCKET_BUFFER_SIZE - new_data;

        // CHANGED
        if( (new_window > old_window) && ( (new_window >= (SOCKET_BUFFER_SIZE/2)) || (old_window == 0) ) ){
            dbg(TRANSPORT_CHANNEL, "Sending Window Update: New Window %u, last received: %u\n", new_window, sockets[fd].nextExpected-1);
            makePack(&p, ACK, sockets[fd].nextExpected, 0, sockets[fd].dest.port, sockets[fd].src, new_window, 0, &data[0]);
            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);
        }
        return j;
    }

    command error_t Transport.connect(socket_t fd, socket_addr_t * addr){
        uint8_t ISN = call Random.rand16() % 255;
        

        sockets[fd].lastSent = ISN+1;
        sockets[fd].lastAck = ISN; 
        sockets[fd].lastWritten = ISN+1;
        
        dbg(TRANSPORT_CHANNEL, "Client: ISN, SEQ of %u\n", ISN);
        makePack(&p, SYN, 0, ISN, addr->port, sockets[fd].src, sockets[fd].effectiveWindow, 0, &data[0]);
        dbg(TRANSPORT_CHANNEL, "Transport.connect: building SYN payload\n");
        sockets[fd].dest.addr = addr->addr;
        sockets[fd].dest.port = addr->port;
        call IP.buildIP(addr->addr, PROTOCOL_TCP, &p);
        sockets[fd].state = SYN_SENT;
        resend_helper(p, sockets[fd].RTT, fd);

        return SUCCESS;
    }

    command error_t Transport.close(socket_t fd){
        if(sockets[fd].state == ESTABLISHED){
            send_data(fd);
            sockets[fd].state = FIN_WAIT;
            //write remaining data in the current buffer
            dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO FIN_WAIT\n", TOS_NODE_ID, sockets[fd].src);
            
            makePack(&p, FIN, 0, sockets[fd].lastSent, sockets[fd].dest.port, sockets[fd].src, sockets[fd].effectiveWindow, 0, &data[0]);
            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);
            resend_helper(p, sockets[fd].RTT, fd);
            sockets[fd].lastSent++;
            sockets[fd].lastWritten++;
            return SUCCESS;
        }
        else if(sockets[fd].state == CLOSE_WAIT){
            sockets[fd].state = LAST_ACK;
            dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO LAST_ACK\n", TOS_NODE_ID, sockets[fd].src);

            makePack(&p, FIN, 0, sockets[fd].lastSent, sockets[fd].dest.port, sockets[fd].src, TOS_NODE_ID, 0, &data[0]);
            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);
            resend_helper(p, sockets[fd].RTT, fd);
            sockets[fd].lastSent++;
            sockets[fd].lastWritten++;
            
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

    void resend_helper(tcp_payload_t payload, uint16_t RTT, uint8_t fd){
        packet_send_t send;
        send.payload = payload;
        send.retransmitCount = 0;
        send.fd = fd;
        send.timestamp = call retransmit_timer.getNow();
        send.timeout = send.timestamp + (RTT * 2);  
        call resend_queue.enqueue(send);
        if(!call retransmit_timer.isRunning()){
            call retransmit_timer.startOneShot(RTT*2);
        } 
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

    bool wrap_checker(uint8_t seq1, uint8_t seq2){
        return seq1 == seq2|| (uint8_t)(seq1 - seq2) < 128;
    }

//don't retransmit acks, this will be handled when the sender resends data
    event void retransmit_timer.fired(){
        uint32_t now = call retransmit_timer.getNow();
        packet_send_t sent;
        
        if(call resend_queue.empty()){
            return;
        } 
        
        sent = call resend_queue.head();
        
        if(sockets[sent.fd].flag == 1 && sockets[sent.fd].state != CLOSED && now >= sent.timeout){
            
            sent = call resend_queue.dequeue(); 
            
            if(sent.payload.ack == 0){
            
                uint8_t next_seq = sent.payload.seq + sent.payload.payload_len;

                if(wrap_checker(sockets[sent.fd].lastAck, next_seq)){
                    dbg(TRANSPORT_CHANNEL, "DISCARDING ACKED PACKET on Timeout: Seq %u < Ack %u\n", sent.payload.seq, sockets[sent.fd].lastAck);
                }
                else if(sent.retransmitCount < 100){
                    call IP.buildIP(sockets[sent.fd].dest.addr, PROTOCOL_TCP, &sent.payload);
                    sent.retransmitCount++;
                    sent.timestamp = call retransmit_timer.getNow();
                    sent.timeout = sent.timestamp + (sockets[sent.fd].RTT * 2);
                    call resend_queue.enqueue(sent); 
                    dbg(TRANSPORT_CHANNEL, "RESENDING seq %u fd %u, count %u\n", sent.payload.seq, sent.fd, sent.retransmitCount);
                }
                else {
                    dbg(TRANSPORT_CHANNEL, "STOPPED RESENDING seq %u fd %u\n", sent.payload.seq, sent.fd);
                }
            } else {
                dbg(TRANSPORT_CHANNEL, "DISCARDING PURE ACK packet from resend queue.\n");
            }
        } 
        
        if(!call resend_queue.empty()){
            packet_send_t next = call resend_queue.head();
            uint32_t time_until_timeout = next.timeout > now ? next.timeout - now : 1; 
            call retransmit_timer.startOneShot(time_until_timeout);
        }
    }

    void makePack(tcp_payload_t* package, uint8_t flags, uint8_t ack, uint8_t seq, uint8_t dest_port, uint8_t src_port, uint8_t window, uint8_t len, uint8_t* payload){
        package->flags = flags;
        package->ack = ack;
        package->seq = seq;
        package->destPort = dest_port;
        package->srcPort = src_port;
        package->window = window;
        package->payload_len = len;
        memcpy(package->payload, payload, len);
    }
}
