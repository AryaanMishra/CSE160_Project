#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/transport_header.h"
#include "../../includes/channels.h"

module TransportP {
    provides interface Transport;
    uses interface SimpleSend;
    uses interface Timer<TMilli> as RetransmitTimer0;
    uses interface Timer<TMilli> as RetransmitTimer1;
}
implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    
    // Track which socket owns which timer
    socket_t timerOwner0 = NULL_SOCKET;
    socket_t timerOwner1 = NULL_SOCKET;
        
    bool isValidSocket(socket_t fd) {
        return (fd < MAX_NUM_OF_SOCKETS && 
                sockets[fd].state != CLOSED);
    }
    
    // Get socket by file descriptor
    socket_store_t* getSocket(socket_t fd) {
        if (isValidSocket(fd)) {
            return &sockets[fd];
        }
        return NULL;
    }
    
    //  free socket slot for allocation
    socket_t allocateSocket() {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == CLOSED) {
                sockets[i].state = CLOSED;
                sockets[i].flag = 0;
                sockets[i].src = 0;
                sockets[i].dest.addr = 0;
                sockets[i].dest.port = 0;
                
                // Clear buffers, apparently necessary
                memset(sockets[i].sendBuff, 0, SOCKET_BUFFER_SIZE);
                memset(sockets[i].rcvdBuff, 0, SOCKET_BUFFER_SIZE);
                
                sockets[i].lastWritten = 0;
                sockets[i].lastAck = 0;
                sockets[i].lastSent = 0;
                sockets[i].lastRead = 0;
                sockets[i].lastRcvd = 0;
                sockets[i].nextExpected = 0;
                
                sockets[i].effectiveWindow = SOCKET_BUFFER_SIZE;
                sockets[i].RTT = 0;
                
                return i;
            }
        }
        return NULL_SOCKET;
    }
    
    //   (for receive)
    socket_t findSocketByAddr(uint16_t src, uint8_t srcPort, uint8_t destPort) {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == ESTABLISHED &&
                sockets[i].dest.addr == src &&
                sockets[i].src == destPort &&
                sockets[i].dest.port == srcPort) {
                return i;
            }
        }
        return NULL_SOCKET;
    }

    // (stop-and-wait)
    bool canSend(socket_t fd) {
        socket_store_t *sock = getSocket(fd);
        if (!sock) return false;
        
        // can send if all previous data was ACKed
        return (sock->lastSent == sock->lastAck);
    }
    
    void sendTCPPacket(socket_t fd, uint8_t flags, 
                       uint8_t *data, uint8_t dataLen) {
        socket_store_t *sock;
        pack tcpPack;
        tcp_header_t *tcpHeader;
        uint8_t i;
        
        sock = getSocket(fd);
        if (!sock) return;
        
        tcpPack.dest = sock->dest.addr;
        tcpPack.src = TOS_NODE_ID;
        tcpPack.seq = (sock->lastSent)++;  
        tcpPack.TTL = MAX_TTL;
        tcpPack.protocol = PROTOCOL_TCP;
        
        tcpHeader = (tcp_header_t *)tcpPack.payload;
        
        tcpHeader->srcPort = sock->src;
        tcpHeader->destPort = sock->dest.port;
        tcpHeader->seq = sock->lastSent;  
        tcpHeader->ack = sock->nextExpected;  
        tcpHeader->flags = flags;
        tcpHeader->advertisedWindow = SOCKET_BUFFER_SIZE - 
                                      (sock->lastRcvd - sock->lastRead);
        
        // Copy data payload
        if (dataLen > 0 && data != NULL) {
            for (i = 0; i < dataLen && i < TCP_MAX_PAYLOAD; i++) {
                tcpHeader->payload[i] = data[i];
            }
        }
        
        call SimpleSend.send(tcpPack, sock->dest.addr);
        
        dbg("Project3TGen", "Sent TCP packet: src=%d dest=%d flags=0x%02x "
            "seq=%d ack=%d len=%d\n", sock->src, sock->dest.port, flags,
            tcpHeader->seq, tcpHeader->ack, dataLen);
    }
    
    // Transport Commands
    
    // Command: Get a socket
    command socket_t Socket() {
        socket_t fd = allocateSocket();
        if (fd != NULL_SOCKET) {
            sockets[fd].state = CLOSED;
            dbg("Project3TGen", "Socket allocated: FD=%d\n", fd);
        }
        return fd;
    }
    
    //  Bind socket to local address
    command error_t Bind(socket_t fd, socket_addr_t *addr) {
        socket_store_t *sock = getSocket(fd);
        
        if (!sock) return FAIL;
        if (sock->state != CLOSED) return FAIL;
        
        sock->src = addr->port;
        sock->dest.addr = TOS_NODE_ID;  // Local node
        
        dbg("Project3TGen", "Socket %d bound to port %d\n", fd, addr->port);
        return SUCCESS;
    }

    //  Listen for incoming connections
    command error_t Listen(socket_t fd) {
        socket_store_t *sock = getSocket(fd);
        
        if (!sock) return FAIL;
        if (sock->state != CLOSED) return FAIL;
        
        sock->state = LISTEN;
        dbg("Project3TGen", "Socket %d listening on port %d\n", 
            fd, sock->src);
        return SUCCESS;
    }

    //  Accept incoming connection
    command socket_t Accept(socket_t fd) {
        socket_store_t *serverSock = getSocket(fd);
        socket_t newFd;
        
        if (!serverSock || serverSock->state != LISTEN) {
            return NULL_SOCKET;
        }
        
        //  return if connection ready
        if (serverSock->flag & 0x01) {  // Pending connection flag
            newFd = allocateSocket();
            if (newFd == NULL_SOCKET) return NULL_SOCKET;
            
            sockets[newFd].src = serverSock->src;
            sockets[newFd].dest = serverSock->dest;
            sockets[newFd].state = ESTABLISHED;
            // Clear pending flag
            serverSock->flag &= ~0x01;  
            
            dbg("Project3TGen", "Connection accepted: newFD=%d from node %d\n",
                newFd, sockets[newFd].dest.addr);
            
            return newFd;
        }
        
        return NULL_SOCKET;
    }

    // Connect to remote server
    command error_t Connect(socket_t fd, socket_addr_t *addr) {
        socket_store_t *sock = getSocket(fd);
        
        if (!sock || sock->state != CLOSED) return FAIL;
        
        sock->state = SYN_SENT;
        sock->dest = *addr;
        sock->lastSent = 0;
        sock->lastAck = 0;
        sock->nextExpected = 0;
        
        // Send SYN packet
        sendTCPPacket(fd, TCP_SYN, NULL, 0);
        
        dbg("Project3TGen", "Syn Packet Sent from Node %d to Node %d Port %d\n", 
            TOS_NODE_ID, addr->addr, addr->port);
        
        if (timerOwner0 == NULL_SOCKET) {
            timerOwner0 = fd;
            call RetransmitTimer0.startOneShot(1000);
        }
        
        return SUCCESS;
    }
    
    // Write data to socket & RETURN: Number of bytes written (may be 0 if can't send yet)
    command uint16_t Write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t *sock = getSocket(fd);
        uint16_t toWrite = 0;
        uint16_t i;
        
        if (!sock || sock->state != ESTABLISHED) {
            dbg("Project3TGen", "Write failed: socket not established\n");
            return 0;
        }
        
        // Stop-and-wait: Can only send if we've received ACK for all data
        if (sock->lastSent > sock->lastAck) {
            dbg("Project3TGen", "Write blocked: waiting for ACK "
                "(lastSent=%d, lastAck=%d)\n", sock->lastSent, sock->lastAck);
            return 0;
        }
        
        // How much can we send?
        toWrite = (bufflen > TCP_MAX_PAYLOAD) ? TCP_MAX_PAYLOAD : bufflen;
        
        // Check advertised window from receiver
        if ((sock->lastSent - sock->lastAck) + toWrite > sock->effectiveWindow) {
            toWrite = sock->effectiveWindow - (sock->lastSent - sock->lastAck);
            if (toWrite <= 0) return 0;
        }
        
        // Copy to send buffer
        for (i = 0; i < toWrite; i++) {
            sock->sendBuff[sock->lastWritten + i] = buff[i];
        }
        sock->lastWritten += toWrite;
        
        // Send packet with this data
        sendTCPPacket(fd, TCP_DATA, buff, toWrite);
        sock->lastSent += toWrite;
        
        // Start retransmit timer
        if (timerOwner0 == NULL_SOCKET) {
            timerOwner0 = fd;
            call RetransmitTimer0.startOneShot(500);
        }
        
        dbg("Project3TGen", "Write: sent %d bytes (total written: %d)\n", 
            toWrite, sock->lastWritten);
        
        return toWrite;
    }
    
    // Read data from socket & RETURN: Number of bytes read
    command uint16_t Read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t *sock = getSocket(fd);
        uint16_t bytesToRead = 0;
        uint16_t i;
        
        if (!sock) {
            return 0;
        }
        
        // How much data is available to read?
        bytesToRead = sock->lastRcvd - sock->lastRead;
        
        // Don't read more than requested or available
        if (bytesToRead > bufflen) {
            bytesToRead = bufflen;
        }
        
        // Copy data to output buffer
        for (i = 0; i < bytesToRead; i++) {
            buff[i] = sock->rcvdBuff[sock->lastRead + i];
        }
        
        sock->lastRead += bytesToRead;
        
        if (bytesToRead > 0) {
            dbg("Project3TGen", "Read: got %d bytes from socket %d\n", 
                bytesToRead, fd);
        }
        
        return bytesToRead;
    }
    
    // Close socket 
    command error_t Close(socket_t fd) {
        socket_store_t *sock = getSocket(fd);
        
        if (!sock || sock->state == CLOSED) {
            return FAIL;
        }
        
        // Send FIN packet
        sendTCPPacket(fd, TCP_FIN, NULL, 0);
        
        // For simplified version, immediately close
        sock->state = CLOSED;
        
        dbg("Project3TGen", "Connection closed: FD=%d\n", fd);
        return SUCCESS;
    }
    
    //  Hard close socket
    command error_t Release(socket_t fd) {
        socket_store_t *sock = getSocket(fd);
        
        if (!sock) return FAIL;
        
        sock->state = CLOSED;
        
        // Stop any pending timers
        if (timerOwner0 == fd) {
            call RetransmitTimer0.stop();
            timerOwner0 = NULL_SOCKET;
        }
        if (timerOwner1 == fd) {
            call RetransmitTimer1.stop();
            timerOwner1 = NULL_SOCKET;
        }
        
        dbg("Project3TGen", "Socket %d released\n", fd);
        return SUCCESS;
    }
    
    // Receive and process TCP packet
    command error_t Receive(pack* package) {
        tcp_header_t *tcpHeader;
        socket_store_t *sock;
        socket_t fd;
        uint16_t srcNode;
        uint8_t srcPort, destPort;
        uint8_t i;
        
        if (package->protocol != PROTOCOL_TCP) {
            return FAIL;
        }
        
        tcpHeader = (tcp_header_t *)package->payload;
        srcNode = package->src;
        srcPort = tcpHeader->srcPort;
        destPort = tcpHeader->destPort;
        
        dbg("Project3TGen", "Received TCP packet: from node %d:%d to port %d "
            "flags=0x%02x seq=%d ack=%d\n", srcNode, srcPort, destPort,
            tcpHeader->flags, tcpHeader->seq, tcpHeader->ack);
        
        //  Handle SYN 
        if (tcpHeader->flags & TCP_SYN) {
            uint8_t j;
            for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
                if (sockets[j].state == LISTEN && 
                    sockets[j].src == destPort) {
                    
                    // Mark connection pending
                    sockets[j].flag |= 0x01;
                    sockets[j].dest.addr = srcNode;
                    sockets[j].dest.port = srcPort;
                    sockets[j].nextExpected = tcpHeader->seq + 1;
                    
                    // Send SYN-ACK
                    sendTCPPacket(j, TCP_SYN | TCP_ACK, NULL, 0);
                    
                    dbg("Project3TGen", "Syn Packet Arrived from Node %d for Port %d\n", 
                        srcNode, destPort);
                    dbg("Project3TGen", "Syn Ack Packet Sent to Node %d for Port %d\n", 
                        srcNode, destPort);
                    
                    return SUCCESS;
                }
            }
        }
        
        //  Handle SYN-ACK 
        if ((tcpHeader->flags & TCP_SYN) && (tcpHeader->flags & TCP_ACK)) {
            uint8_t j;
            for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
                if (sockets[j].state == SYN_SENT &&
                    sockets[j].dest.addr == srcNode &&
                    sockets[j].dest.port == srcPort) {
                    
                    sockets[j].state = ESTABLISHED;
                    sockets[j].nextExpected = tcpHeader->seq + 1;
                    sockets[j].lastAck = tcpHeader->ack;
                    
                    // Send ACK
                    sendTCPPacket(j, TCP_ACK, NULL, 0);
                    
                    dbg("Project3TGen", "Connection established with Node %d\n", 
                        srcNode);
                    
                    return SUCCESS;
                }
            }
        }
        
        //  Handle ACK 
        if (tcpHeader->flags & TCP_ACK) {
            uint8_t j;
            for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
                if (sockets[j].state == ESTABLISHED &&
                    sockets[j].dest.addr == srcNode &&
                    sockets[j].src == destPort &&
                    sockets[j].dest.port == srcPort) {
                    
                    if (tcpHeader->ack > sockets[j].lastAck) {
                        sockets[j].lastAck = tcpHeader->ack;
                        
                        // Stop retransmit timer 
                        if (timerOwner0 == j) {
                            call RetransmitTimer0.stop();
                            timerOwner0 = NULL_SOCKET;
                        }
                        
                        dbg("Project3TGen", "Received ACK for bytes up to %d\n", 
                            tcpHeader->ack);
                    }
                    
                    return SUCCESS;
                }
            }
        }
        
        //  Handle DATA 
        if (tcpHeader->flags & TCP_DATA) {
            uint8_t j;
            for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
                if (sockets[j].state == ESTABLISHED &&
                    sockets[j].dest.addr == srcNode &&
                    sockets[j].src == destPort &&
                    sockets[j].dest.port == srcPort) {
                    
                    // Check expected sequence
                    if (tcpHeader->seq == sockets[j].nextExpected) {
                        // Buffer
                        uint8_t dataLen = TCP_MAX_PAYLOAD;
                        
                        // Copy  receive buffer
                        for (i = 0; i < dataLen; i++) {
                            sockets[j].rcvdBuff[sockets[j].lastRcvd + i] =
                                tcpHeader->payload[i];
                        }
                        
                        sockets[j].lastRcvd += dataLen;
                        sockets[j].nextExpected += dataLen;
                        
                        dbg("Project3TGen", "Received DATA: %d bytes, "
                            "total buffered: %d bytes\n", dataLen, sockets[j].lastRcvd);
                    } else {
                        dbg("Project3TGen", "Dropped out-of-order packet: "
                            "expected seq %d, got %d\n", sockets[j].nextExpected,
                            tcpHeader->seq);
                    }
                    
                    // send ACK
                    sendTCPPacket(j, TCP_ACK, NULL, 0);
                    
                    return SUCCESS;
                }
            }
        }
        
        //  Handle FIN 
        if (tcpHeader->flags & TCP_FIN) {
            uint8_t j;
            for (j = 0; j < MAX_NUM_OF_SOCKETS; j++) {
                if (sockets[j].state == ESTABLISHED &&
                    sockets[j].dest.addr == srcNode &&
                    sockets[j].src == destPort &&
                    sockets[j].dest.port == srcPort) {
                    
                    // Send FIN-ACK
                    sendTCPPacket(j, TCP_FIN | TCP_ACK, NULL, 0);
                    
                    // Close connection
                    sockets[j].state = CLOSED;
                    
                    dbg("Project3TGen", "Connection closed by remote: Node %d\n", 
                        srcNode);
                    
                    return SUCCESS;
                }
            }
        }
        
        return FAIL;
    }
    
    //Timer event for retransmission
    event void RetransmitTimer0.fired() {
        socket_store_t *sock;
        
        if (timerOwner0 == NULL_SOCKET) return;
        
        sock = getSocket(timerOwner0);
        if (!sock) return;
        
        // Resend last data if not all acknowledged
        if (sock->state == ESTABLISHED && sock->lastSent > sock->lastAck) {
            uint8_t toResend = sock->lastSent - sock->lastAck;
            if (toResend > TCP_MAX_PAYLOAD) toResend = TCP_MAX_PAYLOAD;
            
            sendTCPPacket(timerOwner0, TCP_DATA,
                         &sock->sendBuff[sock->lastAck], toResend);
            
            // Restart timer
            call RetransmitTimer0.startOneShot(500);
            
            dbg("Project3TGen", "Retransmitting %d bytes\n", toResend);
        } else {
            timerOwner0 = NULL_SOCKET;
        }
    }
    
    event void RetransmitTimer1.fired() {
        if (timerOwner1 == NULL_SOCKET) return;
        
        socket_store_t *sock = getSocket(timerOwner1);
        if (!sock) return;
        
        if (sock->state == ESTABLISHED && sock->lastSent > sock->lastAck) {
            uint8_t toResend = sock->lastSent - sock->lastAck;
            if (toResend > TCP_MAX_PAYLOAD) toResend = TCP_MAX_PAYLOAD;
            
            sendTCPPacket(timerOwner1, TCP_DATA,
                         &sock->sendBuff[sock->lastAck], toResend);
            
            call RetransmitTimer1.startOneShot(500);
            dbg("Project3TGen", "Retransmitting %d bytes\n", toResend);
        } else {
            timerOwner1 = NULL_SOCKET;
        }
    }
}
