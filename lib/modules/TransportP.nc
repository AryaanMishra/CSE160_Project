#include "../../includes/transport_header.h"
#include "../../includes/socket.h"
#include "../../includes/protocol.h"
#include "../../includes/packet.h"

module TransportP {
    provides interface Transport;
    uses interface SimpleSend;
    uses interface Timer<TMilli> as RetransmitTimer[uint8_t num];
}

implementation {
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];
    uint16_t socketCounter = 0;

    // Helper function to get socket by fd
    socket_store_t* getSocket(socket_t fd) {
        if (fd >= MAX_NUM_OF_SOCKETS) return NULL;
        if (sockets[fd].state == CLOSED) return NULL;
        return &sockets[fd];
    }

    // Helper function to find socket by address
    socket_t findSocketByAddr(uint16_t destAddr, uint8_t destPort, uint8_t srcPort) {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state != CLOSED &&
                sockets[i].dest.addr == destAddr &&
                sockets[i].dest.port == destPort &&
                sockets[i].src == srcPort) {
                return i;
            }
        }
        return NULL_SOCKET;
    }

    // Send TCP packet
    void sendTCPPacket(socket_t fd, uint8_t flags, uint8_t *data, uint8_t dataLen) {
        socket_store_t *sock = getSocket(fd);
        default_pack tcpPack;
        tcp_header_t *tcpHeader;

        if (!sock) return;

        // Build IP-level pack
        tcpPack.dest = sock->dest.addr;
        tcpPack.src = TOS_NODE_ID;
        tcpPack.seq = socketCounter++;
        tcpPack.TTL = MAX_TTL;
        tcpPack.protocol = PROTOCOL_TCP;

        // Cast payload to TCP header
        tcpHeader = (tcp_header_t *)tcpPack.payload;

        // Fill TCP header
        tcpHeader->srcPort = sock->src;
        tcpHeader->destPort = sock->dest.port;
        tcpHeader->seq = sock->lastSent;
        tcpHeader->ack = sock->nextExpected;
        tcpHeader->flags = flags;
        tcpHeader->advertisedWindow = SOCKET_BUFFER_SIZE - sock->lastRcvd;

        // Copy data to payload if provided
        if (data && dataLen > 0) {
            uint8_t i;
            for (i = 0; i < dataLen && i < 14; i++) {
                tcpHeader->payload[i] = data[i];
            }
        }

        dbg("Project3TGen", "Sending packet: src=%d dest=%d flags=0x%02X\n", 
            TOS_NODE_ID, sock->dest.addr, flags);

        // Pack the default_pack into the generic pack structure for transmission
        {
            pack genericPack;
            memcpy(genericPack.payload, (uint8_t *)&tcpPack, sizeof(default_pack));
            call SimpleSend.send(genericPack, sock->dest.addr);
        }
    }

    command socket_t Transport.socket() {
        uint8_t i;
        for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if (sockets[i].state == CLOSED) {
                sockets[i].state = LISTEN;
                sockets[i].lastSent = 0;
                sockets[i].lastAck = 0;
                sockets[i].lastRcvd = 0;
                sockets[i].lastRead = 0;
                sockets[i].lastWritten = 0;
                sockets[i].nextExpected = 0;
                dbg("Project3TGen", "Socket allocated: fd=%d\n", i);
                return i;
            }
        }
        return NULL_SOCKET;
    }

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        socket_store_t *sock = getSocket(fd);
        if (!sock) return FAIL;
        
        sock->src = addr->port;
        dbg("Project3TGen", "Socket bound: fd=%d port=%d\n", fd, addr->port);
        return SUCCESS;
    }

    command error_t Transport.listen(socket_t fd) {
        socket_store_t *sock = getSocket(fd);
        if (!sock) return FAIL;
        
        sock->state = LISTEN;
        dbg("Project3TGen", "Socket listening: fd=%d\n", fd);
        return SUCCESS;
    }

    command error_t Transport.connect(socket_t fd, socket_addr_t *addr) {
        socket_store_t *sock = getSocket(fd);
        if (!sock) return FAIL;

        sock->dest.addr = addr->addr;
        sock->dest.port = addr->port;
        sock->state = SYN_SENT;

        sendTCPPacket(fd, TCP_SYN, NULL, 0);
        dbg("Project3TGen", "SYN sent to %d:%d\n", addr->addr, addr->port);

        call RetransmitTimer.startOneShot[fd](500);
        return SUCCESS;
    }

    command socket_t Transport.accept(socket_t fd) {
        return NULL_SOCKET;
    }

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t *sock = getSocket(fd);
        uint16_t toWrite;
        uint8_t i;

        if (!sock || sock->state != ESTABLISHED) return 0;

        if (sock->lastSent > sock->lastAck) {
            return 0;
        }

        toWrite = (bufflen > 14) ? 14 : bufflen;

        for (i = 0; i < toWrite; i++) {
            sock->sendBuff[sock->lastWritten + i] = buff[i];
        }
        sock->lastWritten += toWrite;

        sendTCPPacket(fd, TCP_DATA, buff, toWrite);
        sock->lastSent += toWrite;

        dbg("Project3TGen", "Wrote %d bytes on socket %d\n", toWrite, fd);

        call RetransmitTimer.startOneShot[fd](500);
        return toWrite;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        socket_store_t *sock = getSocket(fd);
        uint16_t bytesToRead;
        uint8_t i;

        if (!sock) return 0;

        bytesToRead = sock->lastRcvd - sock->lastRead;
        if (bytesToRead == 0) return 0;

        if (bytesToRead > bufflen) bytesToRead = bufflen;

        for (i = 0; i < bytesToRead; i++) {
            buff[i] = sock->rcvdBuff[sock->lastRead + i];
        }

        sock->lastRead += bytesToRead;

        dbg("Project3TGen", "Read %d bytes from socket %d\n", bytesToRead, fd);
        return bytesToRead;
    }

    command error_t Transport.receive(pack* package) {
        default_pack *defaultPkg = (default_pack *)package->payload;
        tcp_header_t *tcpHeader;
        uint16_t srcNode;
        uint8_t srcPort, destPort;
        uint8_t i;
        socket_t sockFd;
        socket_store_t *sock;

        if (defaultPkg->protocol != PROTOCOL_TCP) {
            return FAIL;
        }

        tcpHeader = (tcp_header_t *)defaultPkg->payload;
        srcNode = defaultPkg->src;
        srcPort = tcpHeader->srcPort;
        destPort = tcpHeader->destPort;

        dbg("Project3TGen", "Received TCP packet from %d:%d to port %d, flags=0x%02X\n",
            srcNode, srcPort, destPort, tcpHeader->flags);

        if (tcpHeader->flags & TCP_SYN) {
            sockFd = findSocketByAddr(srcNode, srcPort, destPort);
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                sock->state = SYN_RCVD;
                sock->nextExpected = tcpHeader->seq + 1;
                sendTCPPacket(sockFd, TCP_SYN | TCP_ACK, NULL, 0);
                dbg("Project3TGen", "SYN-ACK sent\n");
                return SUCCESS;
            }
        }

        if (tcpHeader->flags & TCP_ACK) {
            sockFd = findSocketByAddr(srcNode, srcPort, destPort);
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                if (sock->state == SYN_SENT) {
                    sock->state = ESTABLISHED;
                    sock->lastAck = tcpHeader->ack;
                    dbg("Project3TGen", "Connection ESTABLISHED\n");
                    return SUCCESS;
                }
                if (sock->state == SYN_RCVD) {
                    sock->state = ESTABLISHED;
                    sock->lastAck = tcpHeader->ack;
                    dbg("Project3TGen", "Connection ESTABLISHED (server side)\n");
                    return SUCCESS;
                }
            }
        }

        if (tcpHeader->flags & TCP_DATA) {
            sockFd = findSocketByAddr(srcNode, srcPort, destPort);
            if (sockFd != NULL_SOCKET) {
                sock = getSocket(sockFd);
                if (sock->state != ESTABLISHED) return FAIL;

                if (tcpHeader->seq == sock->nextExpected) {
                    for (i = 0; i < 14; i++) {
                        sock->rcvdBuff[sock->lastRcvd + i] = tcpHeader->payload[i];
                    }
                    sock->lastRcvd += 14;
                    sock->nextExpected += 14;

                    dbg("Project3TGen", "DATA received: %d bytes total\n", sock->lastRcvd);
                } else {
                    dbg("Project3TGen", "Out-of-order packet dropped\n");
                }

                sendTCPPacket(sockFd, TCP_ACK, NULL, 0);
                return SUCCESS;
            }
        }

        return FAIL;
    }

    command error_t Transport.close(socket_t fd) {
        socket_store_t *sock = getSocket(fd);
        if (!sock) return FAIL;
        
        sock->state = FIN_WAIT;
        sendTCPPacket(fd, TCP_FIN, NULL, 0);
        return SUCCESS;
    }

    command error_t Transport.release(socket_t fd) {
        socket_store_t *sock = getSocket(fd);
        if (!sock) return FAIL;
        
        sock->state = CLOSED;
        return SUCCESS;
    }

    event void RetransmitTimer.fired[uint8_t num]() {
        dbg("Project3TGen", "Retransmit timer fired\n");
    }
}
