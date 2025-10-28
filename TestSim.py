#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_LINKSTATE_DUMP = 2
    CMD_ROUTE_DUMP = 3
    CMD_TEST_CLIENT = 4
    CMD_TEST_SERVER = 5
    CMD_CLIENT_CLOSE = 11
    CMD_HELLO = 12
    CMD_MSG = 13
    CMD_WHISPER = 14
    CMD_LISTUR = 15

    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command";
    GENERAL_CHANNEL="general";

    # Project 1
    NEIGHBOR_CHANNEL="neighbor";
    FLOODING_CHANNEL="flooding";

    # Project 2
    ROUTING_CHANNEL="routing";

    # Project 3
    TRANSPORT_CHANNEL="transport";

    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap";

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo!'
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline());
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                print " ", s[0], " ", s[1], " ", s[2];
                self.r.add(int(s[0]), int(s[1]), float(s[2]))

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return;

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile;
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in range(1, self.numMote+1):
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in range(1, self.numMote+1):
            print "Creating noise model for ",i;
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return;
        self.t.getNode(nodeID).bootAtTime(1333*nodeID);

    def bootAll(self):
        i=0;
        for i in range(1, self.numMote+1):
            self.bootNode(i);

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff();

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn();

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount*1000)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest);
        self.msg.set_id(ID);
        self.msg.setString_payload(payloadStr)

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg));

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command");

    def linkstateDMP(self, destination):
	self.sendCMD(self.CMD_LINKSTATE_DUMP, destination, "linkstate command");

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command");

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);

    def cmdTestServer(self, address, port):
        print 'Listening for connections..', address, port;
        self.sendCMD(self.CMD_TEST_SERVER, address,"{0}".format(chr(port)));

    def cmdTestClient(self, address, destination, sPort, dPort, transfer):
        print 'Listening for connections...', address, destination, sPort, dPort, transfer;
        self.sendCMD(self.CMD_TEST_CLIENT, address, "{0}{1}{2}{3}".format(chr(destination),chr(sPort),chr(dPort),chr(transfer)));

    def cmdClientClose(self, address, destination, sPort, dPort):
        print 'Closing connections...', address, destination, sPort, dPort;
        self.sendCMD(self.CMD_CLIENT_CLOSE, address, "{0}{1}{2}".format(chr(destination),chr(sPort),chr(dPort)));

    def cmdHello(self, source, username, cPort):
        print 'Hello...', source, username, cPort;
        self.sendCMD(self.CMD_HELLO, source, "{0}{1}".format(username,chr(cPort)));

    def cmdMsg(self, source, msg):
        print 'Msg...', source, msg;
        self.sendCMD(self.CMD_MSG, source, "{0}".format(msg));

    def cmdWhisper(self, source, username, msg):
        print 'Whisper...', source, username, msg;
        self.sendCMD(self.CMD_WHISPER, source, "{0}{1}".format(username,msg));

    def cmdListur(self,source):
        print 'List Users...', source;
        self.sendCMD(self.CMD_LISTUR, source, "Listing Users");


def main():
    s = TestSim();
    s.runTime(10);
    s.loadTopo("long_line.topo");
    s.loadNoise("no_noise.txt");
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
#    s.addChannel(s.GENERAL_CHANNEL);
#    s.addChannel(s.NEIGHBOR_CHANNEL);
#    s.addChannel(s.ROUTING_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);

#    s.runTime(300);
    s.runTime(300);

# PRE-PROJECT 3 :
#    s.linkstateDMP(3);
#    s.routeDMP(3);
#    s.runTime(50);
#    s.ping(19, 1, "REEEE");
#    s.runTime(20);
#    s.ping(3, 2, "Hello, World");
#    s.runTime(20);
#    s.ping(1, 5, "Hello, World");
#    s.runTime(20);
#    s.ping(5, 1, "Hello, World 2");
#    s.runTime(20);
#    s.ping(3, 2, "Hello, World");
#    s.runTime(20);
#    s.ping(19, 1, "Hi!");
#    s.runTime(20);
#    s.routeDMP(19);
#    s.runTime(20);
#    s.routeDMP(13);
#    s.runTime(20);
#    s.routeDMP(1);
#    s.runTime(20);

# PROJECT 3 Tests :
#    s.cmdTestServer(3,10);
#    s.runTime(60);
#    s.cmdTestClient(9,3,25,10,32);
#    s.runTime(100);

#    s.cmdTestClient(3,5,5,11,32);
#    s.runTime(40);
#    s.cmdTestClient(4,3,80,15,32);
#    s.runTime(40);

#    Ignore this pls
#    s.cmdClientClose(9,3,25,10);
#    s.runTime(100);

# PROJECT 4 Tests :
    s.cmdTestServer(1,41);
    s.runTime(60);
    s.cmdHello(3,"acerpa,",35);			        #Must add comma after username; username can not have a comma in it pls
    s.runTime(80);
    s.cmdMsg(3,"HELLO WORLD");
    s.runTime(80);
    s.cmdWhisper(3,"acerpa,","HALO WURLD REEEE");	#Must add comma after username; username can not have a comma in it pls
    s.runTime(80);
    s.cmdListur(3);
    s.runTime(80);

if __name__ == '__main__':
    main()
