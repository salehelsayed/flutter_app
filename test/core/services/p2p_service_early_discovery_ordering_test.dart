import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../local_discovery/fake_local_p2p_service.dart';
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

/// FDC-07 TC-07-02 — cold-start mDNS discovery is hoisted to start EARLY, ahead
/// of the warmBackground inbox-drain body, exactly once, behind the account-move
/// network gate.
///
/// Non-vacuity note: the fake LocalP2PService.start() records synchronously the
/// instant it is *called*, so a naive "discovery before the drain command"
/// assertion can pass vacuously on HEAD (the drain command is issued only after
/// awaits, while the in-Future.wait discovery start records synchronously). The
/// robust discriminator is therefore discovery-start vs the
/// P2P_SERVICE_WARM_BACKGROUND_BEGIN flow event: on HEAD discovery starts INSIDE
/// warmBackground (after BEGIN); after the hoist it starts BEFORE warmBackground
/// even begins.
void main() {
  late _RecordingBridge bridge;
  late InMemoryInboxStagingRepository inboxStagingRepository;

  setUp(() {
    bridge = _RecordingBridge();
    inboxStagingRepository = InMemoryInboxStagingRepository();
  });

  tearDown(() {
    debugSetFlowEventSink(null);
  });

  void stubStartedNode() {
    bridge.whenCommand(
      'node:start',
      (_) => jsonEncode({
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': <String>[],
        'circuitAddresses': <String>[],
        'connections': <dynamic>[],
      }),
    );
  }

  Future<void> settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'startNode starts local discovery before the inbox-drain warm body, exactly once',
    () async {
      final order = <String>[];
      final localP2P = _RecordingLocalP2PService(order);
      stubStartedNode();
      bridge.whenCommand('inbox:retrieve_pending', (_) {
        order.add('drain');
        return jsonEncode({'ok': true, 'messages': <dynamic>[], 'hasMore': false});
      });
      debugSetFlowEventSink((payload) {
        final event = payload['event'];
        if (event == 'P2P_SERVICE_WARM_BACKGROUND_BEGIN') order.add('warm_begin');
      });

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxStagingRepository,
        localP2PService: localP2P,
      );
      addTearDown(service.dispose);

      await service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await settle();
      debugSetFlowEventSink(null);

      // Discovery actually happened — and exactly once (idempotency entry guard:
      // the startNode early seam + the warmBackground idempotent trigger must
      // resolve to a single localP2P.start()).
      expect(localP2P.started, isTrue);
      expect(
        localP2P.startCount,
        1,
        reason: 'discovery must start exactly once (no double-start)',
      );

      // The robust, non-vacuous ordering check: discovery starts BEFORE the warm
      // body begins. On HEAD discovery is seeded inside warmBackground's futures
      // (after WARM_BACKGROUND_BEGIN) so this is RED there.
      expect(order.contains('discovery'), isTrue);
      expect(order.contains('warm_begin'), isTrue);
      expect(
        order.indexOf('discovery'),
        lessThan(order.indexOf('warm_begin')),
        reason:
            'mDNS discovery must start before the warmBackground inbox-drain body '
            '(order=$order)',
      );
    },
  );

  test(
    'early local discovery seam re-asserts the account-move network gate',
    () async {
      final order = <String>[];
      final localP2P = _RecordingLocalP2PService(order);
      stubStartedNode();

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxStagingRepository,
        localP2PService: localP2P,
        // Allow node start/core but DENY lan discovery specifically.
        accountMigrationNetworkGate: ({peerId, required operation}) async =>
            operation != 'p2p_lan_discovery',
      );
      addTearDown(service.dispose);

      // Core-only start (no warm body) then trigger the early seam directly.
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.startEarlyLocalDiscovery();

      expect(
        localP2P.started,
        isFalse,
        reason: 'gate-denied p2p_lan_discovery must not start mDNS',
      );
      expect(localP2P.startCount, 0);
    },
  );
}

/// Records the call order of localP2P.start() into a shared list.
class _RecordingLocalP2PService extends FakeLocalP2PService {
  _RecordingLocalP2PService(this.order);
  final List<String> order;
  int startCount = 0;

  @override
  Future<void> start(String peerId, {int? quicPort, int? tcpPort}) async {
    startCount++;
    order.add('discovery');
    await super.start(peerId, quicPort: quicPort, tcpPort: tcpPort);
  }
}

/// Minimal command-recording fake bridge (self-contained; mirrors the private
/// fake used elsewhere in this directory).
class _RecordingBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)> _handlers =
      {};
  final List<String> calledCommands = [];
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
    final payload = request['payload'] as Map<String, dynamic>?;
    calledCommands.add(cmd);
    final handler = _handlers[cmd];
    if (handler != null) return await handler(payload);
    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $cmd',
    });
  }
}
