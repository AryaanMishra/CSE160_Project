// Configuration
#define AM_NEIGHBOR 62

Configuration NeighborDiscoveryC{
	provides interface NeighborDiscovery;
}

Implementation{
	components NeighborDiscoveryP;
	components new TimerMilliC() as beaconTimer;
	components new SimpleSendC(AM_NEIGHBOR);
	components new AMReceiverC(AM_NEIGHBOR);

	// External Wiring
	NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

	// internal Wiring
	NeighborDiscoveryP.SimpleSend -> SimpleSendC;
	NeighborDiscoveryP.Receve -> AMReceive;
	NeighborDiscoveryP.beaconTimer -> beaconTimer;
}

