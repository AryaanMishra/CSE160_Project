generic configuration ipC(){
    provides interface ipC;

}
implementation{
    components new ipP();
    ip = ipP.ip;
    

}