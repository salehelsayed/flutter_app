import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';

/// Test-Flight-Improv/190 (TC-190-05, Dart parity) — the libp2p advert-port
/// derivation is IP-agnostic, so the Android rollout's empty→real address
/// transition (0.0.0.0-mined FDC-11 fallback shape → real self-enumerated IP
/// shape once anet lands) derives the SAME advert ports. That parity is what
/// prevents an advert-port churn (updateLibp2pPorts dedupe / bonsoir
/// stop+start = iOS watchdog vector) as devices upgrade.
///
/// GREEN-on-HEAD sentinel: the regex `_libp2pListenPort` matches the port
/// regardless of the IP octet, so both shapes already agree today. Its RED
/// proof is the mutation — make `_libp2pListenPort` skip unspecified-IP addrs
/// and the mined-shape derivation nulls out, re-redding the parity asserts.
///
/// Kept in a standalone file (not appended to p2p_service_impl_test.dart) to
/// stay conflict-free while that file is dirty on the shared tree.
void main() {
  group('TC-190-05 advert-port parity across the empty→real address rollout', () {
    const minedShape = <String>[
      '/ip4/0.0.0.0/udp/4001/quic-v1',
      '/ip4/0.0.0.0/tcp/4002',
    ];
    const realShape = <String>[
      '/ip4/192.168.1.7/udp/4001/quic-v1',
      '/ip4/192.168.1.7/tcp/4002',
    ];

    test(
      'TC-190-05: 0.0.0.0-mined and real-addr listenAddresses shapes derive '
      'identical advert ports (no rollout advert churn)',
      () {
        // Both shapes derive the same concrete ports.
        expect(P2PServiceImpl.debugLibp2pListenPort(minedShape, quic: true), 4001);
        expect(P2PServiceImpl.debugLibp2pListenPort(minedShape, quic: false), 4002);
        expect(P2PServiceImpl.debugLibp2pListenPort(realShape, quic: true), 4001);
        expect(P2PServiceImpl.debugLibp2pListenPort(realShape, quic: false), 4002);

        // The rollout empty(0.0.0.0-mined)→real transition must not churn ports.
        expect(
          P2PServiceImpl.debugLibp2pListenPort(minedShape, quic: true),
          P2PServiceImpl.debugLibp2pListenPort(realShape, quic: true),
        );
        expect(
          P2PServiceImpl.debugLibp2pListenPort(minedShape, quic: false),
          P2PServiceImpl.debugLibp2pListenPort(realShape, quic: false),
        );
      },
    );
  });
}
