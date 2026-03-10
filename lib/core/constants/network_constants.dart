/// Network constants for P2P communication
///
/// These constants define the infrastructure endpoints for
/// the decentralized identity system.

/// Rendezvous point multiaddress for P2P connections.
///
/// This address is included in QR payloads so that scanning devices
/// know where to connect to reach this user on the P2P network.
///
/// Format: /dns/{domain}/tcp/{port}/wss/p2p/{peerId}
/// Uses /dns/ (not /dns4/) to resolve both A and AAAA records for dual-stack.
const String RENDEZVOUS_ADDRESS =
    '/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';
