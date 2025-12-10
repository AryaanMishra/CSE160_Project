#include "../../includes/app_structs.h"

generic configuration AppC(){
    provides interface App;

    uses interface Transport;
}
implementation{
    components new AppP();
    App = AppP.App;

    components new TimerMilliC() as read_write;
    AppP.read_write -> read_write;

    AppP.Transport = Transport;
}