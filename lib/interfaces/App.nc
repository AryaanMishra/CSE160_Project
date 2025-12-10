interface App{
    command void initialize_server(socket_t port);
    command error_t handle_command(char* msg);

    command error_t accept_done();

    command error_t connect_done(socket_t fd);
}