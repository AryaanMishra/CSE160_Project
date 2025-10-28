// Module
#include ../../includes/channels.h

module FloodingP{
	provide interface SimpleSend as FloodSender;
	provide interface Receive as MainReceive;
	provide interface Receive as ReplyReceive;

	// Internal 
	uses interface SimpleSend as InternalSender;
	uses interface Receive as InternalReceiver;
}

implementation{
	int seq=0;
	command error_t FloodSender.send(pack msg, uint16_t dest){
		msg.src = TOS_NODE_ID;
		msg.protocol = 0;
		
		msg.seq = seq ++;
		dbg(FLOODING_CHANNEL, "Flooding Network: %s", msg.payload);
		call InternalSender.send(msg, AM_BROADCAST_ADDR);
	}

  	event message_t* InternalReceiver.receive(message_t* msg, void* payload, uint8_t len){
		dbg(FLOODING_CHANNEL,"Receive: %s", m	sg.payload);
		// Check to see if we have seen it before?
		// If we have return msg;
		// If TTL Expired return msg;
		// If none of the above
			//If it is the final destination (TOS_NODE_ID)
			  // RESPOND if it is not a ping reply
			  // msg.Protocol != PING_REPLY
			  // Roughly, return signal MainReceive.receive(msg, payload, len);
			// if not final destination
			  // decrement TTL

			// add to our history
			call FloodSender.send((pack *) payload, AM_BROADCAST_ADDR);
		// 
  		return msg;
 	}
}

