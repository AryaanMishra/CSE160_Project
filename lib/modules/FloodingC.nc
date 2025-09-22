generic configuration FloodingC(){
    provides interface Flooding;
}

implementation{
    components new FloodingP();
    Flooding = FloodingP.Flooding;
}