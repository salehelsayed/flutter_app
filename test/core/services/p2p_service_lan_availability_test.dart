import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../local_discovery/fake_local_p2p_service.dart';

class _FakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = {};

  void whenCommand(
    String cmd,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[cmd] = handler;
  }

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

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
    final payload = request['payload'] as Map<String, dynamic>?;
    final handler = _handlers[cmd];
    if (handler != null) {
      return await handler(payload);
    }
    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $cmd',
    });
  }
}

_FakeBridge _bridge() {
  final bridge = _FakeBridge();
  bridge.whenCommand(
    'node:start',
    (_) => jsonEncode({
      'ok': true,
      'peerId': 'self-peer',
      'isStarted': true,
      'listenAddresses': [],
      'circuitAddresses': [],
      'connections': [],
    }),
  );
  bridge.whenCommand(
    'node:stop',
    (_) => jsonEncode({'ok': true, 'isStarted': false}),
  );
  bridge.whenCommand('inbox:store', (_) => jsonEncode({'ok': false}));
  bridge.whenCommand(
    'inbox:retrieve_pending',
    (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
  );
  bridge.whenCommand('inbox:ack', (_) => jsonEncode({'ok': true, 'acked': 0}));
  return bridge;
}

P2PServiceImpl _service({
  required TransportMetrics metrics,
  required FakeLocalP2PService localP2P,
}) {
  return P2PServiceImpl(
    bridge: _bridge(),
    localP2PService: localP2P,
    inboxStagingRepository: InMemoryInboxStagingRepository(),
    transportMetrics: metrics,
  );
}

void expectLan(
  TransportMetrics metrics, {
  required bool active,
  required int peers,
}) {
  expect(metrics.lanAvailability.discoveryActive, active);
  expect(metrics.lanAvailability.discoveredPeerCount, peers);
}

void main() {
  test(
    'records active zero-peer LAN snapshot after local discovery starts',
    () async {
      final metrics = TransportMetrics();
      final localP2P = FakeLocalP2PService();
      final service = _service(metrics: metrics, localP2P: localP2P);
      addTearDown(service.dispose);

      expectLan(metrics, active: false, peers: 0);

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.warmBackground();

      expect(localP2P.started, isTrue);
      expectLan(metrics, active: true, peers: 0);
    },
  );

  test('updates active LAN peer count without leaking peer details', () async {
    final metrics = TransportMetrics();
    final localP2P = FakeLocalP2PService();
    final service = _service(metrics: metrics, localP2P: localP2P);
    addTearDown(service.dispose);

    localP2P.addLocalPeer(
      'pre-start-peer-id',
      host: '192.168.1.44',
      port: 4444,
    );
    await Future<void>.delayed(Duration.zero);
    expectLan(metrics, active: false, peers: 0);

    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
    await service.warmBackground();
    expectLan(metrics, active: true, peers: 1);

    localP2P.addLocalPeer('second-peer-id', host: '10.0.0.22', port: 5555);
    await Future<void>.delayed(Duration.zero);
    expectLan(metrics, active: true, peers: 2);

    final report = metrics.baselineReport();
    expect(report, contains('LAN: discovery active, 2 peers'));
    expect(report, isNot(contains('pre-start-peer-id')));
    expect(report, isNot(contains('second-peer-id')));
    expect(report, isNot(contains('192.168.1.44')));
    expect(report, isNot(contains('10.0.0.22')));
    expect(report, isNot(contains('4444')));
    expect(report, isNot(contains('5555')));
  });

  test('records inactive zero after local discovery stops', () async {
    final metrics = TransportMetrics();
    final localP2P = FakeLocalP2PService();
    final service = _service(metrics: metrics, localP2P: localP2P);
    addTearDown(service.dispose);

    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
    await service.warmBackground();
    localP2P.addLocalPeer('peer-a');
    await Future<void>.delayed(Duration.zero);
    expectLan(metrics, active: true, peers: 1);

    await service.stopNode();

    expect(localP2P.started, isFalse);
    expectLan(metrics, active: false, peers: 0);
  });

  group('P4 suspected-permission-denied heuristic', () {
    test(
      'flips suspectedPermissionDenied true after 12s with zero peers',
      () {
        fakeAsync((async) {
          final metrics = TransportMetrics();
          final localP2P = FakeLocalP2PService();
          final service = _service(metrics: metrics, localP2P: localP2P);
          addTearDown(service.dispose);

          service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
          async.flushMicrotasks();

          // Discovery active, zero peers — heuristic not yet armed past timeout.
          expectLan(metrics, active: true, peers: 0);
          expect(metrics.lanAvailability.suspectedPermissionDenied, isFalse);

          // Just before the 12s threshold: still not flagged.
          async.elapse(const Duration(seconds: 11));
          expect(metrics.lanAvailability.suspectedPermissionDenied, isFalse);

          // Crossing the threshold with zero peers → suspected.
          async.elapse(const Duration(seconds: 2));
          expect(metrics.lanAvailability.suspectedPermissionDenied, isTrue);
          // Distinct from discoveryActive, which only means start() returned.
          expect(metrics.lanAvailability.discoveryActive, isTrue);
          expect(metrics.lanAvailability.discoveredPeerCount, 0);

          service.dispose();
        });
      },
    );

    test('does not flag when a peer appears before the 12s timeout', () {
      fakeAsync((async) {
        final metrics = TransportMetrics();
        final localP2P = FakeLocalP2PService();
        final service = _service(metrics: metrics, localP2P: localP2P);
        addTearDown(service.dispose);

        service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        async.flushMicrotasks();
        expectLan(metrics, active: true, peers: 0);

        // A peer appears at 5s — clears the armed timer.
        async.elapse(const Duration(seconds: 5));
        localP2P.addLocalPeer('peer-x');
        async.flushMicrotasks();
        expect(metrics.lanAvailability.discoveredPeerCount, 1);
        expect(metrics.lanAvailability.suspectedPermissionDenied, isFalse);

        // Well past the original 12s window: still not suspected.
        async.elapse(const Duration(seconds: 20));
        expect(metrics.lanAvailability.suspectedPermissionDenied, isFalse);

        service.dispose();
      });
    });

    test('peer seen then left does not leave a stale suspected flag', () {
      fakeAsync((async) {
        final metrics = TransportMetrics();
        final localP2P = FakeLocalP2PService();
        final service = _service(metrics: metrics, localP2P: localP2P);
        addTearDown(service.dispose);

        service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        async.flushMicrotasks();

        // Peer appears (cancels timer), then leaves before 12s elapse.
        localP2P.addLocalPeer('peer-y');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        localP2P.removeLocalPeer('peer-y');
        async.flushMicrotasks();
        expect(metrics.lanAvailability.discoveredPeerCount, 0);

        // The peer-seen already cancelled the timer; no re-arm on leave, so the
        // flag must NOT become true (a peer WAS seen → permission not denied).
        async.elapse(const Duration(seconds: 30));
        expect(metrics.lanAvailability.suspectedPermissionDenied, isFalse);

        service.dispose();
      });
    });

    test('stopping discovery clears any suspected flag and cancels timer', () {
      fakeAsync((async) {
        final metrics = TransportMetrics();
        final localP2P = FakeLocalP2PService();
        final service = _service(metrics: metrics, localP2P: localP2P);
        addTearDown(service.dispose);

        service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        async.flushMicrotasks();

        // Let the heuristic flip true with zero peers.
        async.elapse(const Duration(seconds: 13));
        expect(metrics.lanAvailability.suspectedPermissionDenied, isTrue);

        // Stopping discovery resets the snapshot to inactive/0/false.
        service.stopNode();
        async.flushMicrotasks();
        expectLan(metrics, active: false, peers: 0);
        expect(metrics.lanAvailability.suspectedPermissionDenied, isFalse);

        // No re-arm: advancing time must not resurrect the flag.
        async.elapse(const Duration(seconds: 30));
        expect(metrics.lanAvailability.suspectedPermissionDenied, isFalse);

        service.dispose();
      });
    });
  });
}
