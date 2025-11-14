configuration TransportC {
    provides interface Transport;
}
implementation {
    components TransportP;
    components new SimpleSendC(AM_PACK) as SimpleSend;
    components new TimerMilliC() as RetransmitTimer0;
    components new TimerMilliC() as RetransmitTimer1;
    
    Transport = TransportP.Transport;
    
    TransportP.SimpleSend -> SimpleSend;
    TransportP.RetransmitTimer0 -> RetransmitTimer0;
    TransportP.RetransmitTimer1 -> RetransmitTimer1;
}
