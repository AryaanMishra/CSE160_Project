//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H


# include "protocol.h"
#include "channels.h"
#include "flood_header.h"
#include "ll_header.h"
#include "nd_header.h"

enum{
	PACKET_HEADER_LENGTH = 8,
	PACKET_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH,
	LSA_ENTRY_SIZE = 4,
	LSA_ENTRY_COUNT = PACKET_MAX_PAYLOAD_SIZE / LSA_ENTRY_SIZE,
	MAX_TTL = 15
};

typedef nx_struct node_cost{
	nx_uint16_t node;
	nx_uint16_t cost;
} node_cost;

typedef nx_struct lsa_pack{
	nx_uint8_t num_entries;
	node_cost entries[LSA_ENTRY_COUNT];
} lsa_pack;

typedef nx_struct default_pack{
	nx_uint16_t dest;
	nx_uint16_t src;
	nx_uint16_t seq;		//Sequence Number
	nx_uint8_t TTL;		//Time to Live
	nx_uint8_t protocol;
	nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
}default_pack;

typedef nx_struct pack{
	nx_uint8_t payload[28];
}pack;

/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(default_pack *input){
	dbg(GENERAL_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol:%hhu  Payload: %s\n",
	input->src, input->dest, input->seq, input->TTL, input->protocol, input->payload);
}

enum{
	AM_PACK=6
};

#endif
