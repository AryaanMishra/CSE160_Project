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
    uint8_t data[11];

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
        sockets[fd].RTT = 10000;
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
        uint8_t ISN;
        if(sockets[fd].state == LISTEN){
            if(!call connectionQueue.empty()){
                newConn = call connectionQueue.dequeue();
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
                        makePack(&p, SYN_ACK, newConn.payload.seq+1, ISN, sockets[newFd].dest.port, sockets[newFd].src, sockets[newFd].effectiveWindow, 0, &data[0]);
                        dbg(TRANSPORT_CHANNEL, "Accepting client: Sending SYN+ACK, seq:%u ack: %u\n", ISN, newConn.payload.seq+1);
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
        uint8_t j;
        uint8_t bytes_to_send;
        uint8_t send_idx = sockets[fd].lastSent;
        uint8_t window_end;

        if(sockets[fd].flag == 0 || sockets[fd].state != ESTABLISHED){
            // dbg(TRANSPORT_CHANNEL, "NODE %u write() FAILED: flag=%u state=%u\n", TOS_NODE_ID, sockets[fd].flag, sockets[fd].state);
            return 0;
        }

        dbg(TRANSPORT_CHANNEL, "NODE %u write() called: fd=%u bufflen=%u lastWritten=%u lastSent=%u lastAck=%u\n", TOS_NODE_ID, fd, bufflen, sockets[fd].lastWritten, sockets[fd].lastSent, sockets[fd].lastAck);

        // Window starts at lastAck, ends at lastAck + effectiveWindow
        window_end = (sockets[fd].lastAck + sockets[fd].effectiveWindow) % SOCKET_BUFFER_SIZE;

        // Buffer data up to the window end (sliding window)
        //INFINITE LOOP, CHECK WINDOW END;
        while(j < bufflen){
            next = i+1;
            if(next == SOCKET_BUFFER_SIZE){
                next = 0;
            }
            // Stop if we hit the window boundary
            if(next == window_end){
                break;
            }
            sockets[fd].sendBuff[i] = buff[j]; 
            i = next;
            j++;
        }
        sockets[fd].lastWritten = i;

        // Send all unsent packets within the window
        while(send_idx != sockets[fd].lastWritten){
            bytes_to_send = 0;
            while(send_idx != sockets[fd].lastWritten && bytes_to_send < 11){
                data[bytes_to_send] = sockets[fd].sendBuff[send_idx];
                send_idx++;
                if(send_idx == SOCKET_BUFFER_SIZE){
                    send_idx = 0;
                }
                bytes_to_send++;
            }
            dbg(TRANSPORT_CHANNEL, "SENDING PACKET seq: %u, BYTES TO SEND: %u\n", sockets[fd].lastSent, bytes_to_send);
            makePack(&p, NONE, 0, sockets[fd].lastSent, sockets[fd].dest.port, sockets[fd].src, sockets[fd].effectiveWindow, bytes_to_send, &data[0]);
            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);

            resend_helper(p, sockets[fd].RTT, fd);
            sockets[fd].lastSent = send_idx;
        }
        
        dbg(TRANSPORT_CHANNEL, "NODE %u write() returning %u bytes\n", TOS_NODE_ID, j);
        return j;
    }


//if ack==1 treat seq as ack number
    command error_t Transport.receive(tcp_payload_t* package, uint16_t src_addr){
        socket_t fd = call Transport.findFD(package->srcPort, src_addr);
        uint8_t new_seq;
        if(fd != NULL_SOCKET){
            if(package->flags == ACK){
                if(sockets[fd].state != CLOSED && wrap_checker(package->seq, sockets[fd].lastAck)){
                    sockets[fd].lastAck = package->seq;
                }

                while(!call resend_queue.empty()){
                    packet_send_t sent = call resend_queue.head();

                    if(sent.fd == fd){
                        if(wrap_checker(sockets[fd].lastAck, sent.payload.seq+1)){
                            call resend_queue.dequeue();
                            dbg(TRANSPORT_CHANNEL, "ACK recieved removing package\n");
                        } else {
                            break;
                        }
                    } else {
                        break;
                    }
                }

                if(sockets[fd].state == SYN_RCVD){
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

            else if(sockets[fd].state == ESTABLISHED){
                uint8_t i;
                // Copy payload data into receive buffer
                for(i = 0; i < package->payload_len; i++){
                    sockets[fd].rcvdBuff[sockets[fd].lastRcvd] = package->payload[i];
                    sockets[fd].lastRcvd++;
                    if(sockets[fd].lastRcvd == SOCKET_BUFFER_SIZE){
                        sockets[fd].lastRcvd = 0;  
                    }
                }

                sockets[fd].nextExpected = (package->seq + package->payload_len) % SOCKET_BUFFER_SIZE;
                
                // Send ACK back
                makePack(&p, ACK, sockets[fd].nextExpected, 0, package->srcPort, sockets[fd].src, sockets[fd].effectiveWindow, 0, &data[0]);
                call IP.buildIP(src_addr, PROTOCOL_TCP, &p);
                
                dbg(TRANSPORT_CHANNEL, "NODE %u received data, sending ACK\n", TOS_NODE_ID);
                return SUCCESS;
            }

            else if(package->flags == SYN_ACK && sockets[fd].state == SYN_SENT){
                //SIGNAL THE ESTABLISHED EVENT
                dbg(TRANSPORT_CHANNEL, "NODE %u received SYN+ACK from NODE %u PORT %u, moving to ESTABLISHED\n", TOS_NODE_ID, src_addr, package->srcPort);
                sockets[fd].state = ESTABLISHED;
                sockets[fd].effectiveWindow = package->window;
                sockets[fd].nextExpected = package->seq;
                sockets[fd].lastSent = package->ack;

                new_seq = package->seq + 1;
                dbg(TRANSPORT_CHANNEL, "RECEIVED SYN+ACK: seq: %u, ack: %u\n", package->seq, package->ack);

                makePack(&p, ACK, 1, new_seq, package->srcPort, sockets[fd].src, sockets[fd].effectiveWindow, 0, &data[0]);
                call IP.buildIP(src_addr, PROTOCOL_TCP, &p);
                return SUCCESS;
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

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen){
        uint8_t i = sockets[fd].lastRead;
        uint16_t j = 0;

        // Check if socket is valid and in a state where we can read
        if(sockets[fd].flag == 0 || sockets[fd].state != ESTABLISHED){
            return 0;
        }

        // Copy data from receive buffer to application buffer
        while(j < bufflen){
            // Stop if we've read all available data
            if(i == sockets[fd].lastRcvd){
                break;
            }

            // Copy one byte
            buff[j] = sockets[fd].rcvdBuff[i];
            
            // Move to next position in circular buffer
            i++;
            if(i == SOCKET_BUFFER_SIZE){
                i = 0;  // Wrap around
            }
            
            j++;
        }

        // Update the lastRead pointer to where we stopped
        sockets[fd].lastRead = i;

        return j;
    }

    command error_t Transport.connect(socket_t fd, socket_addr_t * addr){
        uint8_t ISN = call Random.rand16() % 255;
        

        sockets[fd].lastSent = ISN;
        sockets[fd].lastAck = ISN; 
        sockets[fd].lastWritten = ISN;
        
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
            sockets[fd].state = FIN_WAIT;
            //write remaining data in the current buffer
            dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO FIN_WAIT\n", TOS_NODE_ID, sockets[fd].src);
            
            if(sockets[fd].lastWritten == sockets[fd].lastSent){
                sockets[fd].state = FIN_WAIT2;
                dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO FIN_WAIT2\n", TOS_NODE_ID, sockets[fd].src);
            }
            makePack(&p, FIN, 0, 0, sockets[fd].dest.port, sockets[fd].src, sockets[fd].effectiveWindow, 0, &data[0]);
            call IP.buildIP(sockets[fd].dest.addr, PROTOCOL_TCP, &p);
            return SUCCESS;
        }
        else if(sockets[fd].state == CLOSE_WAIT){
            sockets[fd].state = LAST_ACK;
            dbg(TRANSPORT_CHANNEL, "NODE: %u PORT: %u MOVING TO LAST_ACK\n", TOS_NODE_ID, sockets[fd].src);

            makePack(&p, FIN, 0, 0, sockets[fd].dest.port, sockets[fd].src, TOS_NODE_ID, 0, &data[0]);
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

    command uint8_t Transport.findFD(uint8_t src_port, uint16_t src_addr){
        uint8_t i = 0;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
            if(sockets[i].dest.port == src_port && sockets[i].dest.addr == src_addr && sockets[i].flag == 1){
                return i;
            }
        }
        return NULL_SOCKET;
    }


    uint8_t findFD_by_port(uint8_t src_port, uint8_t dest_port){
        uint8_t i = 0;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){
             dbg(TRANSPORT_CHANNEL, "DEST PORT: %u, SRC PORT: %u, flag: %u\n", sockets[i].dest.port, sockets[i].src, sockets[i].flag);
            if(sockets[i].dest.port == dest_port && sockets[i].src == src_port && sockets[i].flag == 1){
                return i;
            }
        }
        return NULL_SOCKET;
    }

    bool wrap_checker(uint8_t seq1, uint8_t seq2){
        return (uint8_t)(seq1 - seq2) < 128;
    }
//don't retransmit acks, this will be handled when the sender resends data
    event void retransmit_timer.fired(){
        packet_send_t sent;
        uint32_t now = call retransmit_timer.getNow();
        if(call resend_queue.empty()){
                return;
        } 
        sent = call resend_queue.dequeue();
        if(sockets[sent.fd].flag == 1 && sockets[sent.fd].state != CLOSED){
            if (now >= sent.timeout){
                if(sent.payload.ack == 0){
                if(!wrap_checker(sockets[sent.fd].lastAck, sent.payload.seq + 1)){
                    dbg(TRANSPORT_CHANNEL, "DISCARDING ACKED PACKET\n");
                }
                else if(sent.retransmitCount < 10){
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
                }
            }else{
                call resend_queue.enqueue(sent);
            }
            
        } 
        if(!call resend_queue.empty()){
            packet_send_t next = call resend_queue.head();
            uint32_t time_until_timeout = next.timeout - now;
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