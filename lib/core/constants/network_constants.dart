/// Network constants for P2P communication
///
/// These constants define the infrastructure endpoints for
/// the decentralized identity system.

/// Rendezvous point multiaddress for P2P connections.
///
/// This address is included in QR payloads so that scanning devices
/// know where to connect to reach this user on the P2P network.
///
/// Format: /dns4/{domain}/tcp/{port}/wss/p2p/{peerId}
const String RENDEZVOUS_ADDRESS =
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
