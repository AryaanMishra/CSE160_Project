generic configuration ipC(){
    provides interface IP;
    uses interface LinkLayer;
    uses interface LinkState;
    uses interface SimpleSend as Sender;
    uses interface Transport;
}
implementation{
    components new ipP();
    IP = ipP.IP;

    ipP.LinkLayer = LinkLayer;
    ipP.LinkState = LinkState;
    ipP.Sender = Sender;
    ipP.Transport = Transport;
}