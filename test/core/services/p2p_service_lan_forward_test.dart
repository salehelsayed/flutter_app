import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../local_discovery/fake_local_p2p_service.dart';

/// 179 — CV-34 Pixel→iPhone 1:1 LAN-media forward-chain self-heal + observability.
///
/// The discoverer (Pixel) drops a resolved-but-empty-`libp2pAddresses` peer at the
/// FIRST guard in `_forwardLanPeersToLibp2pDial` SILENTLY, never re-reads its
/// (possibly healed) TXT, and a later heal cannot re-forward because the per-peer
/// dedup set is never cleared. These tests lock the keystone diagnostic + the
/// discoverer self-heal, plus a characterization lock for the advert port derivation.
const _quicAddr = '/ip4/192.168.0.211/udp/4001/quic-v1';

class _FakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)> _handlers =
      {};
  final List<String> commandsSent = [];
  bool _initialized = false;

  void whenCommand(
    String cmd,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[cmd] = handler;
  }

  @override
  bool get isInitialized => _initialized;
  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    commandsSent.add(cmd);
    final handler = _handlers[cmd];
    if (handler != null) {
      return await handler(request['payload'] as Map<String, dynamic>?);
    }
    return jsonEncode({'ok': false, 'errorCode': 'UNHANDLED'});
  }
}

void main() {
  late _FakeBridge bridge;
  late FakeLocalP2PService localP2P;
  late P2PServiceImpl service;
  late List<Map<String, dynamic>> events;

  setUp(() {
    bridge = _FakeBridge();
    bridge.whenCommand('lan:peer_found', (_) => jsonEncode({'ok': true}));
    localP2P = FakeLocalP2PService()..sendWillSucceed = true;
    service = P2PServiceImpl(
      bridge: bridge,
      localP2PService: localP2P,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);
  });

  tearDown(() {
    debugSetFlowEventSink(null);
    service.dispose();
  });

  Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 30));

  int lanPeerFoundCount() =>
      bridge.commandsSent.where((c) => c == 'lan:peer_found').length;
  Iterable<Map<String, dynamic>> skippedEvents() =>
      events.where((e) => e['event'] == 'LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR');

  // --- TC-179-01: observability keystone -----------------------------------
  test(
    'TC-179-01: an empty-address resolved peer emits '
    'LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR and is NOT forwarded',
    () async {
      localP2P.addLocalPeer(
        'iphone',
        host: '192.168.0.211',
        libp2pAddresses: const [],
      );
      await flush();

      // Discriminator: the skip is observable AND no forward crossed the bridge.
      expect(skippedEvents(), hasLength(1));
      expect(skippedEvents().single['details']['peerId'], 'iphone');
      expect(bridge.commandsSent, isNot(contains('lan:peer_found')));
    },
  );

  // --- TC-179-02: dedup cleared on peer-lost -> re-forward on reappear -------
  test(
    'TC-179-02: a forwarded peer that drops from the snapshot is re-forwarded '
    'when it reappears with addresses',
    () async {
      localP2P.addLocalPeer('iphone', libp2pAddresses: const [_quicAddr]);
      await flush();
      expect(lanPeerFoundCount(), 1);

      localP2P.removeLocalPeer('iphone');
      await flush();

      localP2P.addLocalPeer('iphone', libp2pAddresses: const [_quicAddr]);
      await flush();

      expect(
        lanPeerFoundCount(),
        2,
        reason: 'lost clears the dedup set so the healed reappearance forwards',
      );
    },
  );

  // --- TC-179-03a: bounded re-resolve of an empty-address peer --------------
  test(
    'TC-179-03a: an empty-address peer triggers EXACTLY ONE bounded re-resolve '
    '(no advertise side-effect)',
    () async {
      localP2P.addLocalPeer('iphone', libp2pAddresses: const []);
      await flush();
      localP2P.addLocalPeer('iphone', libp2pAddresses: const []); // still empty
      await flush();

      expect(
        localP2P.discoverLocalPeerCallCount,
        1,
        reason: 'bounded to once per empty episode — no re-resolve storm',
      );
      expect(skippedEvents(), hasLength(1));
      expect(
        localP2P.updateLibp2pPortsCallCount,
        0,
        reason: 're-resolve is browse/resolve-only — never advertises',
      );
    },
  );

  // --- TC-179-03b: the re-resolve heal forwards -----------------------------
  test(
    'TC-179-03b: when the re-resolve heals the empty peer, it forwards',
    () async {
      localP2P.resolvesTo = LocalPeer(
        peerId: 'iphone',
        host: '192.168.0.211',
        port: 9999,
        discoveredAt: DateTime.now().toUtc(),
        libp2pAddresses: const [_quicAddr],
      );
      localP2P.addLocalPeer('iphone', libp2pAddresses: const []);
      await flush();

      expect(localP2P.discoverLocalPeerCallCount, 1);
      expect(
        lanPeerFoundCount(),
        1,
        reason: 'the healed re-resolve re-emits a peer with addresses → forward',
      );
    },
  );

  // --- TC-179-05: advert port-derivation characterization lock (A′) ----------
  // DUAL-OUTCOME: GREEN on HEAD ⇒ A′ is refuted at host level (derivation is
  // correct) and this is a regression lock; RED ⇒ a real derivation fix is owed.
  test(
    'TC-179-05: listenAddresses with LAN quic-v1 + tcp derive non-null ports '
    '(no :4221 both-null early-return)',
    () {
      const addrs = <String>[
        '/ip4/192.168.0.211/udp/4001/quic-v1',
        '/ip4/192.168.0.211/tcp/4002',
        '/ip4/127.0.0.1/tcp/8080/ws', // WS lane must be skipped
      ];
      expect(P2PServiceImpl.debugLibp2pListenPort(addrs, quic: true), 4001);
      expect(P2PServiceImpl.debugLibp2pListenPort(addrs, quic: false), 4002);
    },
  );
}
