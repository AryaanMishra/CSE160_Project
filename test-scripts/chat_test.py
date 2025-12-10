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
    # TEST 1: Start the chat server on Node 1, Port 41
    # ============================================
    print("\n===== TEST 1: Starting Chat Server on Node 1, Port 41 =====")
    s.appServer(1, 41);
    s.runTime(200);

    # ============================================
    # TEST 2: Client 1 connects with hello command
    # ============================================
    print("\n===== TEST 2: Client 'alice' connecting from Node 2 =====")
    s.appClient(2, "hello alice 5\r\n");
    s.runTime(500);

    # ============================================
    # TEST 3: Client 2 connects with hello command
    # ============================================
    print("\n===== TEST 3: Client 'bob' connecting from Node 3 =====")
    s.appClient(3, "hello bob 6\r\n");
    s.runTime(500);

    # ============================================
    # TEST 4: Broadcast message from alice
    # ============================================
    print("\n===== TEST 4: alice sends broadcast message =====")
    s.appClient(2, "msg Hello everyone!\r\n");
    s.runTime(500);

    # ============================================
    # TEST 5: List users command
    # ============================================
    print("\n===== TEST 5: alice requests user list =====")
    s.appClient(2, "listusr\r\n");
    s.runTime(500);

    # ============================================
    # TEST 6: Whisper (private message)
    # ============================================
    print("\n===== TEST 6: alice whispers to bob =====")
    s.appClient(2, "whisper bob Hi!\r\n");
    s.runTime(500);

    # ============================================
    # TEST 7: Bob sends a broadcast message
    # ============================================
    print("\n===== TEST 7: bob sends broadcast message =====")
    s.appClient(3, "msg Hi from Bob!\r\n");
    s.runTime(500);

    print("\n===== ALL TESTS COMPLETE =====")
    print("Check the output above for:")
    print("  - Server listening on port 41")
    print("  - SYN/SYN-ACK/ACK handshakes for connections")
    print("  - User registration messages")
    print("  - Broadcast messages received by clients")
    print("  - Whisper messages (only recipient should see)")
    print("  - User list responses")


if __name__ == '__main__':
    main()
