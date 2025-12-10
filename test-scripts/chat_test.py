from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(1);

    # Load the the layout of the network.
    s.loadTopo("long_line.topo");  # Use a simple topology for testing

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt");

    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels for debugging
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);

    # Let the network stabilize (neighbor discovery, routing)
    print("\n===== NETWORK BOOT & STABILIZATION =====")
    s.runTime(500);

    # ============================================
    # Start the chat server on Node 1, Port 41
    # ============================================
    print("\n===== Starting Chat Server on Node 1, Port 41 =====")
    s.appServer(1, 41);
    s.runTime(200);

    # ============================================
    # Client connects with hello command
    # ============================================
    print("\n===== Client 'alice' connecting from Node 2 =====")
    s.appClient(2, "hello alice 5\r\n");
    s.runTime(500);

    # ============================================
    # Client connects with hello command
    # ============================================
    print("\n===== Client 'bob' connecting from Node 3 =====")
    s.appClient(3, "hello bob 6\r\n");
    s.runTime(500);

    # ============================================
    # Client connects with hello command
    # ============================================
    print("\n=====: Client 'jim' connecting from Node 4 =====")
    s.appClient(4, "hello jim 6\r\n");
    s.runTime(500);

    # ============================================
    # Broadcast message from alice
    # ============================================
    print("\n===== alice sends broadcast message =====")
    s.appClient(2, "msg Hello everyone!\r\n");
    s.runTime(500);

    # ============================================
    # List users command
    # ============================================
    print("\n===== alice requests user list =====")
    s.appClient(2, "listusr\r\n");
    s.runTime(500);

    # ============================================
    # Whisper 
    # ============================================
    print("\n===== alice whispers to bob =====")
    s.appClient(2, "whisper bob Hi!\r\n");
    s.runTime(500);

    # ============================================
    # Bob sends a broadcast message
    # ============================================
    print("\n===== bob sends broadcast message =====")
    s.appClient(3, "msg Hi from Bob!\r\n");
    s.runTime(500);


if __name__ == '__main__':
    main()
