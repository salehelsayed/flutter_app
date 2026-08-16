import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/push/domain/push_token_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_chat_disposition.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../local_discovery/fake_local_p2p_service.dart';
import '../../shared/fakes/in_memory_contact_repository.dart';
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../../shared/fakes/in_memory_message_repository.dart';

/// Captures [FLOW] log lines emitted during [action] and returns parsed events.
Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

/// A fake bridge that records commands and returns configurable responses.
class _FakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = {};
  final List<String> calledCommands = [];
  final Map<String, List<Map<String, dynamic>?>> payloadsByCommand = {};
  bool _initialized = false;
  bool automaticallyProveAckCustody = true;

  void whenCommand(
    String cmd,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[cmd] = handler;
  }

  List<Map<String, dynamic>?> payloadsFor(String cmd) =>
      List.unmodifiable(payloadsByCommand[cmd] ?? const []);

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
    payloadsByCommand.putIfAbsent(cmd, () => []).add(payload);

    final handler = _handlers[cmd];
    if (handler != null) {
      final response = await handler(payload);
      if (automaticallyProveAckCustody &&
          (cmd == 'inbox:retrieve_pending' || cmd == 'inbox:ack') &&
          payload?['custodyContract'] == ackOrExpiryInboxCustodyContract) {
        final decoded = jsonDecode(response);
        if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
          decoded.putIfAbsent(
            'custodyContract',
            () => ackOrExpiryInboxCustodyContract,
          );
          return jsonEncode(decoded);
        }
      }
      return response;
    }

    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $cmd',
    });
  }
}

Map<String, dynamic> _pendingInboxRow({
  required String entryId,
  required String from,
  required String message,
  Object? timestamp = '2026-04-01T00:00:00.000Z',
}) {
  return {
    'id': entryId,
    'from': from,
    'message': message,
    'timestamp': timestamp,
  };
}

String _chatEnvelope({
  required String id,
  required String text,
  required String senderPeerId,
  String senderUsername = 'Alice',
  String timestamp = '2026-04-01T00:00:00.000Z',
}) {
  return jsonEncode({
    'type': 'chat_message',
    'version': '1',
    'payload': {
      'id': id,
      'text': text,
      'senderPeerId': senderPeerId,
      'senderUsername': senderUsername,
      'timestamp': timestamp,
    },
  });
}

/// F7: a v1 message_reaction envelope (the wire shape that the relay-inbox
/// retrieve path surfaces).
String _reactionEnvelope({
  String messageId = 'm1',
  String emoji = '👍',
  String action = 'add',
  String senderPeerId = 'remote-peer',
  String timestamp = '2026-04-01T00:00:00.000Z',
}) {
  return jsonEncode({
    'type': 'message_reaction',
    'version': '1',
    'payload': {
      'messageId': messageId,
      'emoji': emoji,
      'action': action,
      'senderPeerId': senderPeerId,
      'timestamp': timestamp,
    },
  });
}

LocalChatMessage _lanChatMessage({
  required String id,
  String from = 'remote-peer',
  String to = 'self-peer',
  String text = 'hello lan',
}) {
  return LocalChatMessage(
    from: from,
    to: to,
    content: _chatEnvelope(id: id, text: text, senderPeerId: from),
    timestamp: DateTime.utc(2026, 4),
    isIncoming: true,
  );
}

Future<void> _waitForCondition(
  bool Function() condition, {
  required String reason,
}) async {
  for (var i = 0; i < 50; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(reason);
}

class _GateableInboxStagingRepository extends InMemoryInboxStagingRepository {
  Completer<void>? stageGate;

  @override
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries) async {
    final ids = await super.stageEntries(entries);
    final gate = stageGate;
    if (gate != null) {
      await gate.future;
    }
    return ids;
  }
}

class _RecordingInboxStagingRepository extends InMemoryInboxStagingRepository {
  _RecordingInboxStagingRepository(this.order);

  final List<String> order;
  int stageCallCount = 0;

  @override
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries) async {
    stageCallCount++;
    order.add('stage');
    return super.stageEntries(entries);
  }
}

class _ThrowingInboxStagingRepository extends InMemoryInboxStagingRepository {
  @override
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries) async {
    throw FileSystemException('simulated staging failure');
  }
}

/// F7: records every deleteEntry call so a test can assert the staged row is
/// NOT deleted until the replay actually commits.
class _DeleteSpyInboxStagingRepository extends InMemoryInboxStagingRepository {
  final List<String> deletedEntryIds = [];

  @override
  Future<void> deleteEntry(String entryId) async {
    deletedEntryIds.add(entryId);
    await super.deleteEntry(entryId);
  }
}

void main() {
  late _FakeBridge bridge;
  late P2PServiceImpl service;
  late InMemoryInboxStagingRepository inboxStagingRepository;

  setUp(() {
    bridge = _FakeBridge();
    bridge.whenCommand(
      'inbox:ack',
      (_) => jsonEncode({'ok': true, 'acked': 1}),
    );
    inboxStagingRepository = InMemoryInboxStagingRepository();
    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: inboxStagingRepository,
    );
  });

  tearDown(() {
    service.dispose();
  });

  Future<void> startNodeForDirectReadyProducer({
    String relayState = 'online',
    List<String> circuitAddresses = const [],
    bool proveReadiness = true,
  }) async {
    bridge.whenCommand(
      'node:start',
      (_) => jsonEncode({
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': <String>[],
        'circuitAddresses': circuitAddresses,
        'connections': <dynamic>[],
        'relayState': relayState,
        'healthyRelayCount': relayState == 'online' ? 1 : 0,
      }),
    );
    bridge.whenCommand(
      'inbox:retrieve',
      (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
    );

    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

    if (!proveReadiness) return;
    service.recordSuccessfulSendProof(
      source: 'test_send',
      trigger: 'test_action',
      sendPath: 'direct',
    );
    await service.retrieveInbox();
    expect(service.currentState.usabilityReady, isTrue);
  }

  void connectPeerForDirectReadyProducer({
    required String peerId,
    required List<String> multiaddrs,
    bool isRelay = false,
  }) {
    bridge.onPeerConnected?.call(
      p2p.ConnectionState(
        peerId: peerId,
        multiaddrs: multiaddrs,
        direction: 'outbound',
        status: 'connected',
        isRelay: isRelay,
      ),
    );
  }

  void disconnectPeerForDirectReadyProducer(String peerId) {
    bridge.onPeerDisconnected?.call(
      p2p.ConnectionState(
        peerId: peerId,
        multiaddrs: const [],
        direction: 'outbound',
        status: 'disconnected',
      ),
    );
  }

  test('ack-or-expiry capability rejects generic OK', () async {
    bridge.whenCommand(
      'inbox:store',
      (_) => jsonEncode({'ok': true, 'storeStatus': 'stored'}),
    );

    final genericOk = await service.storeInAckCustodyInboxDetailed(
      'remote-peer',
      'strict-envelope',
      custodyKind: AckCustodyKind.directTextV108,
    );

    expect(genericOk.status, InboxStoreStatus.failed);
    expect(genericOk.errorCode, 'CUSTODY_PROOF_MISSING_OR_INVALID');
    expect(genericOk.ackOrExpiryAccepted, isFalse);
    expect(
      bridge.payloadsFor('inbox:store').single,
      containsPair('custodyContract', ackOrExpiryInboxCustodyContract),
    );
    expect(
      bridge.payloadsFor('inbox:store').single,
      containsPair('custodyKind', 'direct_text_v108'),
    );
  });

  test(
    'TC-349-04 direct mutation custody kind reaches existing strict bridge command',
    () async {
      bridge.whenCommand(
        'inbox:store',
        (_) => jsonEncode({
          'ok': true,
          'storeStatus': 'stored',
          'custodyContract': ackOrExpiryInboxCustodyContract,
        }),
      );

      final outcome = await service.storeInAckCustodyInboxDetailed(
        'remote-peer',
        'strict-mutation-envelope',
        custodyKind: AckCustodyKind.directMutationV109,
      );

      expect(outcome.ackOrExpiryAccepted, isTrue);
      expect(
        bridge.payloadsFor('inbox:store').single,
        containsPair('custodyKind', 'direct_mutation_v109'),
      );
    },
  );

  test(
    'TC-347-05 media expiry-bounded capability requires exact relay expiry proof',
    () async {
      const ceiling = 2000000123456;
      for (final returnedExpiry in <int?>[null, ceiling + 1, ceiling]) {
        bridge.whenCommand(
          'inbox:store',
          (_) => jsonEncode({
            'ok': true,
            'storeStatus': 'stored',
            'custodyContract': ackOrExpiryInboxCustodyContract,
            'expiresAtMs': ?returnedExpiry,
          }),
        );

        final outcome = await service.storeInMediaExpiryBoundedInboxDetailed(
          'remote-peer',
          'strict-media-envelope',
          custodyExpiresAtOrBeforeMs: ceiling,
        );
        expect(
          outcome.ackOrExpiryAccepted,
          returnedExpiry == ceiling,
          reason: 'returned expiry $returnedExpiry',
        );
        if (returnedExpiry != ceiling) {
          expect(outcome.errorCode, 'CUSTODY_EXPIRY_PROOF_MISSING_OR_INVALID');
        }
      }

      final payload = bridge.payloadsFor('inbox:store').last!;
      expect(payload['custodyContract'], ackOrExpiryInboxCustodyContract);
      expect(payload['custodyKind'], 'direct_text_v108');
      expect(payload['custodyExpiresAtOrBeforeMs'], ceiling);
    },
  );

  test(
    'ack-or-expiry retrieve and ACK reject missing or mutated proof',
    () async {
      for (final phase in <String>['retrieve', 'ack']) {
        for (final proof in <String?>[null, 'ack_or_expiry_v2']) {
          final localBridge = _FakeBridge()
            ..automaticallyProveAckCustody = false;
          final repo = InMemoryInboxStagingRepository();
          var replayCount = 0;
          final retrieveProof = phase == 'ack'
              ? ackOrExpiryInboxCustodyContract
              : proof;
          final ackProof = phase == 'retrieve'
              ? ackOrExpiryInboxCustodyContract
              : proof;
          localBridge.whenCommand(
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
          localBridge.whenCommand(
            'inbox:retrieve_pending',
            (_) => jsonEncode({
              'ok': true,
              'custodyContract': ?retrieveProof,
              'messages': <Map<String, dynamic>>[
                _pendingInboxRow(
                  entryId: 'proof-$phase-${proof ?? 'missing'}',
                  from: 'remote-peer',
                  message: _chatEnvelope(
                    id: 'message-$phase-${proof ?? 'missing'}',
                    text: 'proof validation',
                    senderPeerId: 'remote-peer',
                  ),
                ),
              ],
              'hasMore': false,
            }),
          );
          localBridge.whenCommand(
            'inbox:ack',
            (_) => jsonEncode({
              'ok': true,
              'acked': 1,
              'custodyContract': ?ackProof,
            }),
          );
          final localService = P2PServiceImpl(
            bridge: localBridge,
            inboxStagingRepository: repo,
            replayRecoveredInboxChatMessage:
                (_, {String? stagedEntryId}) async {
                  replayCount++;
                  return (
                    disposition: RecoveredInboxChatDisposition.committed,
                    reasonCode: 'stored',
                    reasonDetail: null,
                  );
                },
          );
          addTearDown(localService.dispose);

          await localService.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
          final outcome = await localService.drainOfflineInboxFully();

          expect(outcome.isSuccessful, isFalse, reason: '$phase / $proof');
          expect(
            outcome.failureReason,
            contains('custody_proof_missing_or_invalid'),
            reason: '$phase / $proof',
          );
          expect(
            replayCount,
            phase == 'retrieve' ? 0 : 1,
            reason: '$phase / $proof',
          );
          expect(
            localBridge.payloadsFor('inbox:ack').length,
            phase == 'retrieve' ? 0 : 1,
            reason: '$phase / $proof',
          );
        }
      }
    },
  );

  // ───────────────────────── FDC-04: warmPeer ─────────────────────────
  group('FDC-04 warmPeer', () {
    // (Re)create `service` as a STARTED P2PServiceImpl backed by a fake LAN
    // stack + optional injected network-change signal / active-peer source.
    Future<FakeLocalP2PService> startWarmService({
      Stream<void>? networkChangeSignal,
      String? Function()? activePeerId,
    }) async {
      service.dispose();
      final localP2P = FakeLocalP2PService();
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxStagingRepository,
        localP2PService: localP2P,
        networkChangeSignal: networkChangeSignal,
        activePeerId: activePeerId,
      );
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
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      bridge.calledCommands.clear();
      bridge.payloadsByCommand.clear();
      return localP2P;
    }

    int dials() => bridge.calledCommands.where((c) => c == 'peer:dial').length;
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 25));

    // TC-04-01: AWAIT the LAN seed first, THEN re-read isLocalPeer to gate the
    // speculative dial (DESIGN-1). (a) non-LAN peer → dial fires; (b) the seed
    // makes the peer LAN-visible → dial SKIPPED.
    test('TC-04-01: awaits LAN seed first, then gates the dial', () async {
      // (a) peer stays non-LAN → dial fires after the awaited seed.
      final localA = await startWarmService();
      final eventsA = await _captureFlowEvents(() async {
        await service.warmPeer('peer-remote');
        await _waitForCondition(
          () => bridge.calledCommands.contains('peer:dial'),
          reason: 'expected a speculative dial for a non-LAN peer',
        );
      });
      expect(localA.discoverLocalPeerCallCount, 1);
      expect(dials(), 1);
      expect(
        eventsA.map((e) => e['event']),
        containsAllInOrder([
          'P2P_SERVICE_WARM_PEER_BEGIN',
          'P2P_SERVICE_WARM_PEER_LAN_SEED',
          'P2P_SERVICE_WARM_PEER_DIAL',
        ]),
      );

      // (b) the bounded seed flips the peer LAN-visible → dial SKIPPED. Models
      // the cold-LAN-map warm-open: isLocalPeer is false at warm-start and only
      // true AFTER the awaited seed.
      final localB = await startWarmService();
      localB.resolvesTo = LocalPeer(
        peerId: 'peer-lan',
        host: '192.168.1.50',
        port: 9999,
        discoveredAt: DateTime.now().toUtc(),
      );
      final eventsB = await _captureFlowEvents(() async {
        await service.warmPeer('peer-lan');
        await settle();
      });
      // 179: the warm seed (1) discovers peer-lan with EMPTY libp2pAddresses, so
      // the forward chain fires ONE additional bounded re-resolve (the CV-34
      // self-heal). warmPeer's own single seed + dial-skip behaviour is unchanged.
      expect(localB.discoverLocalPeerCallCount, 2);
      expect(dials(), 0);
      expect(
        eventsB.any(
          (e) =>
              e['event'] == 'P2P_SERVICE_WARM_PEER_DIAL_SKIPPED' &&
              (e['details'] as Map?)?['reason'] == 'is_local',
        ),
        isTrue,
      );
    });

    // TC-04-02: skip the dial when isLocalPeer is already true (LAN-only).
    test('TC-04-02: skips the dial when the peer is already LAN-visible', () async {
      final local = await startWarmService();
      local.addLocalPeer('peer-lan');
      final events = await _captureFlowEvents(() async {
        await service.warmPeer('peer-lan');
        await settle();
      });
      // 179: peer-lan is added with EMPTY libp2pAddresses, so the forward chain
      // fires one bounded re-resolve (CV-34 self-heal) BEFORE warmPeer's own
      // seed → 2 total. The warm seed still runs and the dial is still skipped.
      expect(local.discoverLocalPeerCallCount, 2);
      expect(dials(), 0);
      expect(
        events.any((e) => e['event'] == 'P2P_SERVICE_WARM_PEER_DIAL_SKIPPED'),
        isTrue,
      );
    });

    // TC-04-03: debounce — SEQUENTIAL (post-dial cooldown) and CONCURRENT
    // (same-tick in-flight sentinel) repeats both collapse to ONE dial.
    test(
      'TC-04-03: debounce collapses sequential AND concurrent repeats',
      () async {
        // (a) sequential: dial fails, second call within cooldown is debounced.
        await withClock(Clock.fixed(DateTime.utc(2026, 6, 27, 12)), () async {
          await startWarmService(); // no peer:dial handler → dial fails
          await service.warmPeer('peer-a');
          await _waitForCondition(() => dials() == 1, reason: 'first dial');
          await settle(); // outcome handler sets the cooldown
          final events = await _captureFlowEvents(() async {
            await service.warmPeer(
              'peer-a',
            ); // within the (fixed-clock) cooldown
            await settle();
          });
          expect(dials(), 1); // still one
          expect(
            events.any((e) => e['event'] == 'P2P_SERVICE_WARM_PEER_DEBOUNCED'),
            isTrue,
          );
        });

        // (b) concurrent burst: the dial hangs; two same-tick warms → ONE dial.
        await withClock(Clock.fixed(DateTime.utc(2026, 6, 27, 13)), () async {
          await startWarmService();
          final hang = Completer<String>();
          bridge.whenCommand('peer:dial', (_) => hang.future);
          // SAME synchronous tick — models conv-open + notif-tap + resume.
          unawaited(service.warmPeer('peer-b'));
          unawaited(service.warmPeer('peer-b'));
          await _waitForCondition(() => dials() >= 1, reason: 'first dial');
          await settle();
          expect(dials(), 1); // the in-flight sentinel collapsed the burst
          hang.complete(jsonEncode({'ok': false}));
          await settle();
        });
      },
    );

    // TC-04-04: per-peer cooldown ESCALATES on repeated failing dials
    // (floor 5s → 2x → …), layered over libp2p's Go-owned swarm backoff.
    test(
      'TC-04-04: per-peer cooldown escalates on repeated failures',
      () async {
        var now = DateTime.utc(2026, 6, 27, 14);
        await withClock(Clock(() => now), () async {
          await startWarmService(); // dial keeps failing
          await service.warmPeer('peer-c');
          await _waitForCondition(() => dials() == 1, reason: '1st dial');
          await settle(); // cooldown = now + 5s (floor)

          now = now.add(const Duration(seconds: 6)); // past the 5s floor
          await service.warmPeer('peer-c');
          await _waitForCondition(() => dials() == 2, reason: '2nd dial');
          await settle(); // cooldown = now + 10s (2x escalation)

          now = now.add(const Duration(seconds: 6)); // < the escalated 10s
          final events = await _captureFlowEvents(() async {
            await service.warmPeer('peer-c');
            await settle();
          });
          expect(
            dials(),
            2,
          ); // still debounced → escalation grew past the floor
          expect(
            events.any((e) => e['event'] == 'P2P_SERVICE_WARM_PEER_DEBOUNCED'),
            isTrue,
          );
        });
      },
    );

    // TC-04-05: PS-3 — no-op when the node is not started (no dial, no seed).
    test('TC-04-05: no-op when the node is not started (PS-3)', () async {
      service.dispose();
      final localP2P = FakeLocalP2PService();
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxStagingRepository,
        localP2PService: localP2P,
      ); // NOT started
      bridge.calledCommands.clear();
      final events = await _captureFlowEvents(() async {
        await service.warmPeer('peer-x');
        await settle();
      });
      expect(localP2P.discoverLocalPeerCallCount, 0);
      expect(bridge.calledCommands.contains('peer:dial'), isFalse);
      expect(
        events.any(
          (e) =>
              e['event'] == 'P2P_SERVICE_WARM_PEER_SKIPPED' &&
              (e['details'] as Map?)?['reason'] == 'not_started',
        ),
        isTrue,
      );
    });

    // TC-04-06: PS-1 — warmPeer never sends a message or deposits to the inbox.
    test('TC-04-06: never sends a message or inboxes (PS-1)', () async {
      final local = await startWarmService();
      await service.warmPeer('peer-remote'); // non-local → fires a dial only
      await _waitForCondition(() => dials() == 1, reason: 'speculative dial');
      await settle();
      expect(local.sentMessages, isEmpty);
      // The ONLY bridge command warmPeer may issue is the speculative dial.
      expect(bridge.calledCommands.where((c) => c != 'peer:dial'), isEmpty);
    });

    // TC-04-07: network-change re-warms ONLY the active peer, resets its
    // cooldown (preserving escalation), and drops its learned `local`.
    test(
      'TC-04-07: network-change re-warms active-only + resets + drops local',
      () async {
        var now = DateTime.utc(2026, 6, 27, 15);
        await withClock(Clock(() => now), () async {
          final signal = StreamController<void>();
          final local = await startWarmService(
            networkChangeSignal: signal.stream,
            activePeerId: () => 'peer-A',
          );
          // Warm A while NON-local → dial fails → A gets a live cooldown.
          await service.warmPeer('peer-A');
          await _waitForCondition(() => dials() == 1, reason: 'A dial');
          await settle();
          // Warm B too (also in _warmAttempts), but A stays the active peer.
          await service.warmPeer('peer-B');
          await _waitForCondition(() => dials() == 2, reason: 'B dial');
          await settle();
          // A becomes LAN-visible + learns 'local' (so the entry survives reads).
          local.addLocalPeer('peer-A');
          service.recordSuccessfulTransport('peer-A', 'local');
          expect(service.lastKnownGoodTransport('peer-A'), 'local');
          final seedBefore = local.discoverLocalPeerCallCount;

          now = now.add(
            const Duration(seconds: 1),
          ); // well within A's 5s cooldown
          final events = await _captureFlowEvents(() async {
            signal.add(null);
            await _waitForCondition(
              () => local.discoverLocalPeerCallCount > seedBefore,
              reason: 'A re-warmed despite the live cooldown (reset worked)',
            );
            await settle();
          });
          // A re-warmed (seed fired again) despite the just-reset cooldown.
          expect(local.discoverLocalPeerCallCount, greaterThan(seedBefore));
          // The learned 'local' was dropped by the network change.
          expect(service.lastKnownGoodTransport('peer-A'), isNull);
          // B (warmed but no longer active) was NOT re-warmed → no new dial.
          // (A's re-warm skips the dial because A is now LAN-visible.)
          expect(dials(), 2);
          expect(
            events.any(
              (e) =>
                  e['event'] == 'P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM',
            ),
            isTrue,
          );
          await signal.close();
        });
      },
    );

    test(
      'TC-371-09 group top route never warms direct transport on network change',
      () async {
        final signal = StreamController<void>();
        final compatibilityTracker = ActiveConversationTracker()
          ..setActive('group:group-a');
        expect(compatibilityTracker.activePeerId, 'group:group-a');
        final local = await startWarmService(
          networkChangeSignal: signal.stream,
          activePeerId: () => compatibilityTracker.activePeerId,
        );

        signal.add(null);
        await settle();

        expect(local.discoverLocalPeerCallCount, 0);
        expect(dials(), 0);
        expect(bridge.calledCommands, isNot(contains('peer:dial')));
        await signal.close();
      },
    );

    // TC-04-08: the network-change re-warm threads the (Go-inert) preferQuic
    // intent flag down to the peer:dial payload.
    test(
      'TC-04-08: network-change re-warm threads preferQuic to the dial',
      () async {
        var now = DateTime.utc(2026, 6, 27, 15, 30);
        await withClock(Clock(() => now), () async {
          final signal = StreamController<void>();
          await startWarmService(
            networkChangeSignal: signal.stream,
            activePeerId: () =>
                'peer-Q', // non-local → the re-warm fires a dial
          );
          signal.add(null);
          await _waitForCondition(() => dials() == 1, reason: 're-warm dial');
          await settle();
          final dialPayload = bridge.payloadsFor('peer:dial').last;
          expect(dialPayload?['preferQuic'], isTrue);
          await signal.close();
        });
      },
    );

    // TC-04-16: rapid network-change FLAPPING coalesces to ONE re-warm
    // (self-debounce), and the per-peer escalation count is preserved.
    test(
      'TC-04-16: flap-burst coalesced to one re-warm; escalation preserved',
      () async {
        var now = DateTime.utc(2026, 6, 27, 16);
        await withClock(Clock(() => now), () async {
          final signal = StreamController<void>();
          await startWarmService(
            networkChangeSignal: signal.stream,
            activePeerId: () => 'peer-A', // non-local → dial keeps failing
          );
          // Burst of 3 events within the floor window (clock NOT advanced).
          signal.add(null);
          await _waitForCondition(
            () => dials() == 1,
            reason: '1st re-warm dial',
          );
          await settle();
          signal.add(null);
          await settle();
          signal.add(null);
          await settle();
          expect(dials(), 1); // self-debounce coalesced the flap to ONE dial

          // Escalation preserved: the 1st failure set cooldown=5s (failureCount
          // 1). Advance past the floor, flap again → 2nd failure → cooldown 10s
          // (failureCount 2). A NORMAL warm 6s later is STILL debounced (6 < 10),
          // which only holds if failureCount was NOT reset per network event.
          now = now.add(const Duration(seconds: 6));
          signal.add(null);
          await _waitForCondition(
            () => dials() == 2,
            reason: '2nd re-warm dial',
          );
          await settle();
          now = now.add(const Duration(seconds: 6)); // <10s escalated cooldown
          final events = await _captureFlowEvents(() async {
            await service.warmPeer('peer-A'); // normal warm, NOT via the signal
            await settle();
          });
          expect(dials(), 2); // still debounced → escalation survived the flaps
          expect(
            events.any((e) => e['event'] == 'P2P_SERVICE_WARM_PEER_DEBOUNCED'),
            isTrue,
          );
          await signal.close();
        });
      },
    );
  });

  // ──────────────── 182: connectivity-restore inbox drain ────────────────
  // When connectivity is restored while the app is foreground (WiFi auto-
  // reconnect / handoff / router-back), onNetworkChanged must IMMEDIATELY pull
  // the relay's stored offline inbox — instead of waiting for the next ~30s
  // health-check poll or an app resume. The drain is roster-wide (fires even
  // with no active conversation peer), durable (inbox:retrieve_pending, never
  // the destructive inbox:retrieve — Report 48), debounced (rides the existing
  // 5s flap floor), migration-gated, and inherits the 141 not-started defer.
  // The seam is the already-present networkChangeSignal stream, subscribed to
  // onNetworkChanged in the constructor.
  group('182 connectivity-restore inbox drain', () {
    var retrievePendingCount = 0;
    var destructiveRetrieveCount = 0;

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 25));

    setUp(() {
      retrievePendingCount = 0;
      destructiveRetrieveCount = 0;
      bridge.whenCommand('inbox:retrieve_pending', (_) {
        retrievePendingCount++;
        return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
      });
      // Report 48: the destructive read must NEVER be used by the drain.
      bridge.whenCommand('inbox:retrieve', (_) {
        destructiveRetrieveCount++;
        return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
      });
    });

    // (Re)build `service` wired to a connectivity signal; start unless asked
    // not to, then let any start-time warm/drain settle and zero the counters
    // so each test measures ONLY the connectivity-triggered drain.
    Future<void> build({
      required Stream<void> networkChangeSignal,
      String? Function()? activePeerId,
      Future<bool> Function({String? peerId, required String operation})?
      accountMigrationNetworkGate,
      bool start = true,
    }) async {
      service.dispose();
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxStagingRepository,
        localP2PService: FakeLocalP2PService(),
        networkChangeSignal: networkChangeSignal,
        activePeerId: activePeerId,
        // The constructor's gate is non-nullable (permissive by default); when
        // a test does not inject one, pass an explicit allow-all gate.
        accountMigrationNetworkGate:
            accountMigrationNetworkGate ??
            ({peerId, required operation}) async => true,
      );
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
      if (start) {
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      }
      await settle();
      bridge.calledCommands.clear();
      bridge.payloadsByCommand.clear();
      retrievePendingCount = 0;
      destructiveRetrieveCount = 0;
    }

    // TC-182-01 (PROD-CRITICAL, drain-trigger leg): a connectivity event pulls
    // the inbox even with NO active peer, and does so WITHOUT the peer-scoped
    // re-warm (proving the drain sits before the active-peer guard).
    test(
      'TC-182-01: connectivity event drains the inbox even with NO active peer',
      () async {
        final signal = StreamController<void>();
        await build(
          networkChangeSignal: signal.stream,
          activePeerId: () => null, // no conversation open
        );
        final events = await _captureFlowEvents(() async {
          signal.add(null);
          await _waitForCondition(
            () => retrievePendingCount >= 1,
            reason:
                'connectivity restore must pull the offline inbox even with '
                'no active peer (HEAD: onNetworkChanged never drains)',
          );
        });
        expect(retrievePendingCount, greaterThanOrEqualTo(1));
        // NEW discriminator: the connectivity-triggered drain ran ...
        expect(
          events.any(
            (e) => e['event'] == 'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
          ),
          isTrue,
          reason: 'the connectivity-triggered drain discriminator must fire',
        );
        // ... while the peer-scoped re-warm did NOT (no active peer) — proving
        // the drain is roster-wide / placed BEFORE the active-peer guard.
        expect(
          events.any(
            (e) => e['event'] == 'P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM',
          ),
          isFalse,
          reason: 'no active peer ⇒ re-warm skipped, yet the drain still fired',
        );
        await signal.close();
      },
    );

    // TC-182-02: the connectivity drain uses the DURABLE retrieve, never the
    // destructive inbox:retrieve (Report 48 guardrail).
    test('TC-182-02: connectivity drain uses the durable retrieve, never the '
        'destructive read', () async {
      final signal = StreamController<void>();
      await build(networkChangeSignal: signal.stream, activePeerId: () => null);
      await _captureFlowEvents(() async {
        signal.add(null);
        await _waitForCondition(
          () => retrievePendingCount >= 1,
          reason: 'the durable inbox:retrieve_pending must be issued',
        );
      });
      expect(retrievePendingCount, greaterThanOrEqualTo(1));
      expect(
        destructiveRetrieveCount,
        0,
        reason:
            'Report 48: the connectivity drain must never call the '
            'destructive inbox:retrieve',
      );
      await signal.close();
    });

    // TC-182-03: with an active peer present, BOTH the drain and the existing
    // FDC-04 re-warm fire (the drain addition must not break the re-warm).
    test(
      'TC-182-03: connectivity drain AND re-warm both fire with an active peer',
      () async {
        final signal = StreamController<void>();
        await build(
          networkChangeSignal: signal.stream,
          activePeerId: () => 'peer-A',
        );
        final events = await _captureFlowEvents(() async {
          signal.add(null);
          await _waitForCondition(
            () => retrievePendingCount >= 1,
            reason: 'the drain fires alongside the re-warm',
          );
          await settle();
        });
        expect(
          events.any(
            (e) => e['event'] == 'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
          ),
          isTrue,
        );
        expect(
          events.any(
            (e) => e['event'] == 'P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM',
          ),
          isTrue,
          reason: 'adding the drain must not break the existing re-warm',
        );
        await signal.close();
      },
    );

    // TC-182-04: a WiFi flap-burst within the 5s floor coalesces to ONE drain
    // (the drain rides the existing flap debounce because it sits AFTER the
    // early-return).
    test(
      'TC-182-04: flap-burst coalesces to ONE connectivity drain (5s floor)',
      () async {
        final now = DateTime.utc(2026, 6, 30, 12);
        await withClock(Clock(() => now), () async {
          final signal = StreamController<void>();
          await build(
            networkChangeSignal: signal.stream,
            activePeerId: () => null,
          );
          final events = await _captureFlowEvents(() async {
            // 3 events within the 5s floor (clock NOT advanced).
            signal.add(null);
            await _waitForCondition(
              () => retrievePendingCount >= 1,
              reason: 'the first restore drains',
            );
            signal.add(null);
            signal.add(null);
            await settle();
          });
          expect(
            events
                .where(
                  (e) => e['event'] == 'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
                )
                .length,
            1,
            reason:
                'a flap-burst within the 5s floor must coalesce to ONE drain',
          );
          await signal.close();
        });
      },
    );

    // TC-182-05 (INV): the connectivity drain re-verifies the account-migration
    // network gate — a denied gate blocks the network side-effect.
    test(
      'TC-182-05: connectivity drain respects the account-migration gate',
      () async {
        final signal = StreamController<void>();
        await build(
          networkChangeSignal: signal.stream,
          activePeerId: () => null,
          accountMigrationNetworkGate: ({peerId, required operation}) async =>
              operation != 'p2p_drain_offline_inbox',
        );
        final events = await _captureFlowEvents(() async {
          signal.add(null);
          await settle();
        });
        // The connectivity path RAN (discriminator present) ...
        expect(
          events.any(
            (e) => e['event'] == 'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN',
          ),
          isTrue,
        );
        // ... but the migration gate blocked the network side-effect.
        expect(
          events.any(
            (e) =>
                e['event'] == 'P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED',
          ),
          isTrue,
        );
        expect(
          retrievePendingCount,
          0,
          reason: 'a denied migration gate must block the connectivity drain',
        );
        await signal.close();
      },
    );

    // TC-182-06 (lifecycle durability): a connectivity event before the node
    // starts DEFERS (141), then fires exactly once on the stopped->started
    // transition — never dropped.
    test('TC-182-06: connectivity event before node-start defers, then fires on '
        'start', () async {
      final signal = StreamController<void>();
      await build(
        networkChangeSignal: signal.stream,
        activePeerId: () => null,
        start: false,
      );
      final scheduled = await _captureFlowEvents(() async {
        signal.add(null);
        await settle();
      });
      expect(
        retrievePendingCount,
        0,
        reason: 'no inbox retrieve may be issued while the node is not started',
      );
      expect(
        scheduled.any(
          (e) => e['event'] == 'P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED',
        ),
        isTrue,
        reason:
            'a connectivity drain requested before start must defer, not drop',
      );
      // Drive stopped->started: the deferred drain fires once.
      final fired = await _captureFlowEvents(() async {
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await _waitForCondition(
          () => retrievePendingCount >= 1,
          reason: 'the deferred connectivity drain fires once the node starts',
        );
      });
      expect(retrievePendingCount, greaterThanOrEqualTo(1));
      expect(
        fired.any(
          (e) => e['event'] == 'P2P_SERVICE_PENDING_STARTUP_DRAIN_FIRED',
        ),
        isTrue,
      );
      await signal.close();
    });
  });

  group('account migration runtime gate', () {
    test(
      'blocks bridge and local network side effects before commands',
      () async {
        service.dispose();

        final blockedOperations = <String>{};
        final observedOperations = <String>[];
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: inboxStagingRepository,
          accountMigrationNetworkGate: ({peerId, required operation}) async {
            observedOperations.add(operation);
            return !blockedOperations.contains(operation);
          },
        );

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

        expect(
          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer'),
          isTrue,
        );
        bridge.calledCommands.clear();
        bridge.payloadsByCommand.clear();

        blockedOperations.addAll({
          'p2p_warm_background',
          'p2p_send_message',
          'p2p_send_message_with_reply',
          'p2p_discover_peer',
          'p2p_dial_peer',
          'p2p_store_inbox',
          'p2p_retrieve_inbox',
          'p2p_register_push_token',
          'p2p_immediate_health_check',
          'p2p_drain_offline_inbox',
          'p2p_drain_offline_inbox_full',
          'p2p_probe_relay',
          'p2p_discover_local_peer',
          'p2p_send_local_message',
          'p2p_send_local_media',
        });

        await service.warmBackground();
        expect(await service.sendMessage('remote-peer', 'hello'), isFalse);
        final reply = await service.sendMessageWithReply(
          'remote-peer',
          'hello',
        );
        expect(reply.sent, isFalse);
        expect(await service.discoverPeer('remote-peer'), isNull);
        expect(await service.dialPeer('remote-peer'), isFalse);
        expect(await service.storeInInbox('remote-peer', 'hello'), isFalse);
        expect(await service.retrieveInbox(), isEmpty);
        expect(await service.registerPushToken('token', 'ios'), isFalse);
        await service.performImmediateHealthCheck();
        await service.drainOfflineInbox();
        await service.drainOfflineInboxFully();
        expect(await service.probeRelay('remote-peer'), RelayProbeResult.error);
        expect(
          await service.discoverLocalPeer(
            'remote-peer',
            timeout: const Duration(milliseconds: 1),
          ),
          isFalse,
        );
        expect(
          await service.sendLocalMessage('remote-peer', 'hello', 'self-peer'),
          isFalse,
        );
        expect(
          await service.sendLocalMedia(
            peerId: 'remote-peer',
            filePath: '/tmp/media.jpg',
            mime: 'image/jpeg',
            mediaId: 'media-1',
            fromPeerId: 'self-peer',
          ),
          isFalse,
        );

        expect(bridge.calledCommands, isEmpty);
        expect(observedOperations, containsAll(blockedOperations));
      },
    );

    test(
      'uses local account peer for target-peer bridge operation gates',
      () async {
        service.dispose();

        final observedPeerByOperation = <String, String?>{};
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: inboxStagingRepository,
          accountMigrationNetworkGate: ({peerId, required operation}) async {
            observedPeerByOperation[operation] = peerId;
            return true;
          },
        );

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
          'message:send',
          (_) => jsonEncode({'ok': true, 'sent': true, 'acked': true}),
        );
        bridge.whenCommand(
          'rendezvous:discover',
          (_) => jsonEncode({'ok': true, 'peers': []}),
        );
        bridge.whenCommand(
          'peer:dial',
          (_) => jsonEncode({'ok': true, 'connected': true}),
        );
        bridge.whenCommand('inbox:store', (_) => jsonEncode({'ok': true}));
        bridge.whenCommand('relay:probe', (_) => jsonEncode({'ok': true}));

        expect(
          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer'),
          isTrue,
        );

        expect(await service.sendMessage('remote-peer', 'hello'), isTrue);
        expect(
          (await service.sendMessageWithReply('remote-peer', 'hello')).sent,
          isTrue,
        );
        expect(await service.discoverPeer('remote-peer'), isNull);
        expect(await service.dialPeer('remote-peer'), isTrue);
        expect(await service.storeInInbox('remote-peer', 'hello'), isTrue);
        bridge.whenCommand(
          'inbox:store',
          (_) => jsonEncode({
            'ok': true,
            'storeStatus': 'stored',
            'expiresAtMs': 1765619200000,
            'occupancy': 3,
            'capacity': 100,
          }),
        );
        final enriched = await service.storeInInboxDetailed(
          'remote-peer',
          'hello',
        );
        expect(enriched.status, InboxStoreStatus.stored);
        expect(enriched.expiresAtMs, 1765619200000);
        expect(enriched.occupancy, 3);
        expect(enriched.capacity, 100);

        bridge.whenCommand('inbox:store', (_) => jsonEncode({'ok': true}));
        final oldRelay = await service.storeInInboxDetailed(
          'remote-peer',
          'hello',
        );
        expect(oldRelay.status, InboxStoreStatus.stored);
        expect(oldRelay.expiresAtMs, isNull);

        bridge.whenCommand(
          'inbox:store',
          (_) => jsonEncode({'ok': true, 'storeStatus': 'stored'}),
        );
        final unproven = await service.storeInAckCustodyInboxDetailed(
          'remote-peer',
          'strict-envelope',
          custodyKind: AckCustodyKind.directTextV108,
        );
        expect(
          unproven.status,
          InboxStoreStatus.failed,
          reason: 'ack-or-expiry capability rejects generic OK',
        );
        expect(unproven.ackOrExpiryAccepted, isFalse);
        expect(
          bridge.payloadsFor('inbox:store').last,
          containsPair('custodyContract', ackOrExpiryInboxCustodyContract),
        );
        expect(
          bridge.payloadsFor('inbox:store').last,
          containsPair('custodyKind', 'direct_text_v108'),
        );

        bridge.whenCommand(
          'inbox:store',
          (_) => jsonEncode({
            'ok': true,
            'storeStatus': 'duplicate',
            'custodyContract': ackOrExpiryInboxCustodyContract,
          }),
        );
        final proven = await service.storeInAckCustodyInboxDetailed(
          'remote-peer',
          'strict-envelope',
          custodyKind: AckCustodyKind.directReactionV109,
        );
        expect(proven.status, InboxStoreStatus.duplicate);
        expect(proven.ackOrExpiryAccepted, isTrue);
        expect(
          bridge.payloadsFor('inbox:store').last,
          containsPair('custodyKind', 'direct_reaction_v109'),
        );

        bridge.whenCommand(
          'inbox:store',
          (_) => jsonEncode({
            'ok': false,
            'errorCode': 'INBOX_FULL',
            'error': 'recipient inbox full',
          }),
        );
        final full = await service.storeInInboxDetailed('remote-peer', 'hello');
        expect(full.status, InboxStoreStatus.rejectedFull);
        expect(full.errorCode, 'INBOX_FULL');
        expect(
          await service.probeRelay('remote-peer'),
          RelayProbeResult.connected,
        );
        expect(
          await service.discoverLocalPeer(
            'remote-peer',
            timeout: const Duration(milliseconds: 1),
          ),
          isFalse,
        );
        expect(
          await service.sendLocalMessage('remote-peer', 'hello', 'self-peer'),
          isFalse,
        );
        expect(
          await service.sendLocalMedia(
            peerId: 'remote-peer',
            filePath: '/tmp/media.jpg',
            mime: 'image/jpeg',
            mediaId: 'media-1',
            fromPeerId: 'self-peer',
          ),
          isFalse,
        );

        for (final operation in const [
          'p2p_send_message',
          'p2p_send_message_with_reply',
          'p2p_discover_peer',
          'p2p_dial_peer',
          'p2p_store_inbox',
          'p2p_probe_relay',
          'p2p_discover_local_peer',
          'p2p_send_local_message',
          'p2p_send_local_media',
        ]) {
          expect(
            observedPeerByOperation[operation],
            'self-peer',
            reason: operation,
          );
        }
      },
    );
  });

  // ───────────────────── FDC-11: lan:peer_found forwarder ─────────────────
  group('FDC-11 lan:peer_found forwarder', () {
    const lanPeerId = 'lan-peer';
    const lanAddrs = ['/ip4/192.168.1.50/udp/45000/quic-v1'];

    Future<FakeLocalP2PService> startService({
      Set<String> blockedOperations = const {},
      List<String>? observedOperations,
    }) async {
      service.dispose();
      final localP2P = FakeLocalP2PService();
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxStagingRepository,
        localP2PService: localP2P,
        accountMigrationNetworkGate: ({peerId, required operation}) async {
          observedOperations?.add(operation);
          return !blockedOperations.contains(operation);
        },
      );
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
      bridge.whenCommand('lan:peer_found', (_) => jsonEncode({'ok': true}));
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      bridge.calledCommands.clear();
      bridge.payloadsByCommand.clear();
      return localP2P;
    }

    // T11: with the runtime gate paused for 'p2p_lan_dial', a delivered LAN
    // peer-found issues NO bridge crossing (the move-feature gate lock).
    test(
      'lan:peer_found forward blocked when account network side-effects paused',
      () async {
        final observed = <String>[];
        final localP2P = await startService(
          blockedOperations: {'p2p_lan_dial'},
          observedOperations: observed,
        );

        localP2P.addLocalPeer(lanPeerId, libp2pAddresses: lanAddrs);
        await Future<void>.delayed(const Duration(milliseconds: 25));

        expect(bridge.calledCommands, isNot(contains('lan:peer_found')));
        expect(
          observed,
          contains('p2p_lan_dial'),
          reason: 'the runtime gate must be consulted at the forward point',
        );
      },
    );

    // With the gate open, the resolved LAN peer (carrying libp2p multiaddrs) is
    // forwarded exactly once; re-emitting the same peer does not double-forward.
    test('lan:peer_found forwarded once when the gate is open', () async {
      final localP2P = await startService();

      localP2P.addLocalPeer(lanPeerId, libp2pAddresses: lanAddrs);
      await _waitForCondition(
        () => bridge.calledCommands.contains('lan:peer_found'),
        reason: 'expected a lan:peer_found forward when the gate is open',
      );

      expect(
        bridge.calledCommands.where((c) => c == 'lan:peer_found').length,
        1,
      );
      final payload = bridge.payloadsFor('lan:peer_found').single;
      expect(payload?['peerId'], lanPeerId);
      expect(payload?['addresses'], lanAddrs);

      // Re-emitting the same peer must not re-cross the bridge (per-peer dedup).
      localP2P.addLocalPeer(lanPeerId, libp2pAddresses: lanAddrs);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(
        bridge.calledCommands.where((c) => c == 'lan:peer_found').length,
        1,
      );
    });

    // A WS-only peer (older client / no libp2p ports advertised) is never
    // forwarded to the libp2p dial.
    test('peer without libp2p addresses is not forwarded', () async {
      final localP2P = await startService();

      localP2P.addLocalPeer(lanPeerId); // libp2pAddresses defaults to []
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(bridge.calledCommands, isNot(contains('lan:peer_found')));
    });
  });

  // ──────────────── FDC-11 (174): LAN advert libp2p-port self-heal ──────────
  // The FDC-07 cold-start early seam derives the libp2p QUIC/TCP advert ports
  // from listenAddresses BEFORE the host has surfaced its resolved LAN listen
  // addrs, so it advertises null. The resolved addrs later arrive via the
  // addresses:updated push; _handleAddressesUpdated must re-derive and
  // re-advertise so a same-WiFi peer can build a non-empty libp2pAddresses.
  //
  // SAFETY: a re-advertise is a native bonsoir stop+start whose SYNC main-thread
  // DNS-SD read SIGKILLs iOS when Local Network is denied/pending, and the
  // suspected-denied gate can't protect a re-start fired inside the cold-start
  // window. So the publish is DEFERRED until a peer resolves over mDNS
  // (_localNetworkProven) — provably-safe AND the only moment the ports are
  // actually needed (a peer exists to dial).
  group('FDC-11 LAN advert self-heal (174)', () {
    const quicAddr = '/ip4/192.168.0.5/udp/45000/quic-v1';
    const tcpAddr = '/ip4/192.168.0.5/tcp/45001';
    const wsAddr = '/ip4/192.168.0.5/tcp/8080/ws';

    Future<FakeLocalP2PService> startWithListenAddrs(
      List<String> listenAddresses,
    ) async {
      service.dispose();
      final localP2P = FakeLocalP2PService();
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxStagingRepository,
        localP2PService: localP2P,
      );
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'self-peer',
          'isStarted': true,
          'listenAddresses': listenAddresses,
          'circuitAddresses': <String>[],
          'connections': <dynamic>[],
        }),
      );
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      // Latch local discovery active so the self-heal arm in
      // _handleAddressesUpdated runs (mirrors the startNode early seam).
      await service.startEarlyLocalDiscovery();
      return localP2P;
    }

    // A discovered same-WiFi peer (no libp2p addrs → not forwarded to the dial)
    // proves Local Network works, unblocking the deferred advert publish.
    void proveLocalNetwork(FakeLocalP2PService localP2P) =>
        localP2P.addLocalPeer('proof-peer');

    // TC-01: peer-proven → addresses:updated carrying libp2p ports → re-advertise.
    test(
      'addresses:updated re-advertises once Local Network is proven',
      () async {
        final localP2P = await startWithListenAddrs(const <String>[]);
        // Cold-start early seam derived null (no listen addrs yet).
        expect(localP2P.startedQuicPort, isNull);
        expect(localP2P.startedTcpPort, isNull);
        expect(localP2P.updateLibp2pPortsCallCount, 0);

        proveLocalNetwork(localP2P);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        bridge.onAddressesUpdated?.call(const [
          quicAddr,
          tcpAddr,
          wsAddr,
        ], const <String>[]);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(localP2P.updateLibp2pPortsCallCount, 1);
        expect(localP2P.updatedQuicPort, 45000);
        expect(localP2P.updatedTcpPort, 45001);
      },
    );

    // TC-01b: addresses:updated arrives BEFORE any peer → deferred; the
    // subsequent peer resolve flushes the held ports (either ordering converges).
    test(
      'addresses:updated defers, then a peer-resolve flushes the ports',
      () async {
        final localP2P = await startWithListenAddrs(const <String>[]);

        bridge.onAddressesUpdated?.call(const [
          quicAddr,
          tcpAddr,
        ], const <String>[]);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          localP2P.updateLibp2pPortsCallCount,
          0,
          reason: 'must defer the re-advertise before Local Network is proven',
        );

        proveLocalNetwork(localP2P);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(localP2P.updateLibp2pPortsCallCount, 1);
        expect(localP2P.updatedQuicPort, 45000);
        expect(localP2P.updatedTcpPort, 45001);
      },
    );

    // TC-06 (iOS watchdog SAFETY lock): addresses:updated with NO peer resolved
    // yet must NOT fire a native bonsoir re-advertise (the cold-start window
    // where a SYNC DNS-SD start() can SIGKILL the app on a denied prompt).
    test('does NOT re-advertise before Local Network is proven', () async {
      final localP2P = await startWithListenAddrs(const <String>[]);
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      bridge.onAddressesUpdated?.call(const [
        quicAddr,
        tcpAddr,
      ], const <String>[]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        localP2P.updateLibp2pPortsCallCount,
        0,
        reason:
            'no native bonsoir re-advertise may fire in the cold-start window',
      );
      final deferred = events.where(
        (e) => e['event'] == 'FDC_LAN_ADVERT_PORTS_DEFERRED',
      );
      expect(
        deferred,
        isNotEmpty,
        reason: 'the deferral must be device-observable',
      );
    });

    // TC-04: device-verifiable numeric (un-redacted int) port diagnostic.
    test('numeric advert-port diagnostic emits ints', () async {
      final localP2P = await startWithListenAddrs(const <String>[]);
      proveLocalNetwork(localP2P);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      bridge.onAddressesUpdated?.call(const [
        quicAddr,
        tcpAddr,
      ], const <String>[]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final advert = events.firstWhere(
        (e) =>
            e['event'] == 'FDC_LAN_ADVERT_PORTS' &&
            (e['details'] as Map)['source'] == 'addresses_updated',
        orElse: () => <String, dynamic>{},
      );
      expect(
        advert,
        isNotEmpty,
        reason: 'FDC_LAN_ADVERT_PORTS{source:addresses_updated} must fire',
      );
      final details = advert['details'] as Map<String, dynamic>;
      // Discriminator: explicit ints, NOT a redacted multiaddr string.
      expect(details['quicPort'], isA<int>());
      expect(details['quicPort'], 45000);
      expect(details['tcpPort'], 45001);
      expect(details['source'], 'addresses_updated');
    });

    // TC-05 (INV-lock, GREEN on HEAD): _startLocalDiscovery extracts the QUIC
    // and plain-TCP ports, never the /ws lane. The ws addr is ordered BEFORE the
    // plain-tcp addr so the /ws exclusion is genuinely exercised (otherwise the
    // loop would return the first plain-tcp match and never reach the ws lane,
    // making this lock vacuous).
    test(
      '_startLocalDiscovery extracts quic/tcp ports, not the ws lane',
      () async {
        final localP2P = await startWithListenAddrs(const [
          quicAddr,
          wsAddr,
          tcpAddr,
        ]);
        expect(localP2P.startedQuicPort, 45000);
        expect(localP2P.startedTcpPort, 45001); // plain tcp, NOT 8080 ws
      },
    );

    // TC-05c (INV-lock): a ws-only listenAddresses (no plain libp2p tcp) yields
    // a null tcp advert port — the ws lane is never mistaken for the tcp lane.
    test(
      '_startLocalDiscovery never picks the ws lane as the tcp port',
      () async {
        final localP2P = await startWithListenAddrs(const [quicAddr, wsAddr]);
        expect(localP2P.startedQuicPort, 45000);
        expect(localP2P.startedTcpPort, isNull); // 8080 ws is NOT the tcp port
      },
    );

    // TC-05b (INV-lock): empty listenAddresses → both ports null.
    test(
      '_startLocalDiscovery derives null from empty listenAddresses',
      () async {
        final localP2P = await startWithListenAddrs(const <String>[]);
        expect(localP2P.startedQuicPort, isNull);
        expect(localP2P.startedTcpPort, isNull);
      },
    );
  });

  group('transport inference', () {
    test(
      'account migration gate blocks inbound Go messages before stream emission',
      () async {
        final blockedService = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: inboxStagingRepository,
          accountMigrationNetworkGate: ({peerId, required operation}) async =>
              false,
        );
        addTearDown(blockedService.dispose);

        final received = <ChatMessage>[];
        final sub = blockedService.messageStream.listen(received.add);
        addTearDown(sub.cancel);

        bridge.onMessageReceived?.call(
          const ChatMessage(
            from: 'remote-peer',
            to: 'self-peer',
            content: 'hello',
            timestamp: '2026-01-01T00:00:00.000Z',
            isIncoming: true,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(received, isEmpty);
      },
    );

    test(
      'incoming Go transport wins over conflicting mixed direct and relay state',
      () async {
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

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

        final received = <ChatMessage>[];
        final sub = service.messageStream.listen(received.add);

        bridge.onPeerConnected?.call(
          const p2p.ConnectionState(
            peerId: 'remote-peer',
            multiaddrs: ['/ip4/192.168.1.10/tcp/4001'],
            direction: 'outbound',
            status: 'connected',
          ),
        );
        bridge.onPeerConnected?.call(
          const p2p.ConnectionState(
            peerId: 'remote-peer',
            multiaddrs: [
              '/dns4/relay.example/tcp/4001/p2p/relay-peer/p2p-circuit',
            ],
            direction: 'outbound',
            status: 'connected',
          ),
        );
        bridge.onMessageReceived?.call(
          const ChatMessage(
            from: 'remote-peer',
            to: 'self-peer',
            content: 'hello',
            timestamp: '2026-01-01T00:00:00.000Z',
            isIncoming: true,
            transport: 'direct',
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(received, hasLength(1));
        expect(received.single.transport, 'direct');

        await sub.cancel();
      },
    );

    test(
      'incoming Go message uses direct transport from peer connection',
      () async {
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

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

        final received = <ChatMessage>[];
        final sub = service.messageStream.listen(received.add);

        bridge.onPeerConnected?.call(
          const p2p.ConnectionState(
            peerId: 'remote-peer',
            multiaddrs: ['/ip4/192.168.1.10/tcp/4001'],
            direction: 'outbound',
            status: 'connected',
          ),
        );
        bridge.onMessageReceived?.call(
          const ChatMessage(
            from: 'remote-peer',
            to: 'self-peer',
            content: 'hello',
            timestamp: '2026-01-01T00:00:00.000Z',
            isIncoming: true,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(received, hasLength(1));
        expect(received.single.transport, 'direct');

        await sub.cancel();
      },
    );

    test(
      'incoming Go message uses relay transport from circuit connection',
      () async {
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

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

        final received = <ChatMessage>[];
        final sub = service.messageStream.listen(received.add);

        bridge.onPeerConnected?.call(
          const p2p.ConnectionState(
            peerId: 'remote-peer',
            multiaddrs: [
              '/dns4/relay.example/tcp/4001/p2p/relay-peer/p2p-circuit',
            ],
            direction: 'outbound',
            status: 'connected',
          ),
        );
        bridge.onMessageReceived?.call(
          const ChatMessage(
            from: 'remote-peer',
            to: 'self-peer',
            content: 'hello',
            timestamp: '2026-01-01T00:00:00.000Z',
            isIncoming: true,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(received, hasLength(1));
        expect(received.single.transport, 'relay');

        await sub.cancel();
      },
    );
  });

  group('sendMessageWithReply', () {
    test('parses additive transport from the bridge response', () async {
      bridge.whenCommand(
        'message:send',
        (_) => jsonEncode({
          'ok': true,
          'sent': true,
          'acked': true,
          'reply': '{"ack":true}',
          'transport': 'relay',
        }),
      );

      final result = await service.sendMessageWithReply(
        'remote-peer',
        '{"hello":"world"}',
      );

      expect(result.sent, isTrue);
      expect(result.acked, isTrue);
      expect(result.transport, 'relay');
    });
  });

  group('sendLocalMessageDurable', () {
    test(
      'returns detailed LAN ack and bool wrapper succeeds only on committed',
      () async {
        service.dispose();

        final localP2P = FakeLocalP2PService();
        service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: localP2P,
          inboxStagingRepository: inboxStagingRepository,
        );

        localP2P.sendMessageAck = LanSendAck.committed;
        expect(
          await service.sendLocalMessageDurable(
            'remote-peer',
            '{"text":"committed"}',
            'self-peer',
          ),
          LanSendAck.committed,
        );
        expect(
          await service.sendLocalMessage(
            'remote-peer',
            '{"text":"committed"}',
            'self-peer',
          ),
          isTrue,
        );

        localP2P.sendMessageAck = LanSendAck.legacyAck;
        expect(
          await service.sendLocalMessageDurable(
            'remote-peer',
            '{"text":"legacy"}',
            'self-peer',
          ),
          LanSendAck.legacyAck,
        );
        expect(
          await service.sendLocalMessage(
            'remote-peer',
            '{"text":"legacy"}',
            'self-peer',
          ),
          isFalse,
        );

        localP2P.sendMessageAck = LanSendAck.failed;
        expect(
          await service.sendLocalMessageDurable(
            'remote-peer',
            '{"text":"failed"}',
            'self-peer',
          ),
          LanSendAck.failed,
        );
        expect(
          await service.sendLocalMessage(
            'remote-peer',
            '{"text":"failed"}',
            'self-peer',
          ),
          isFalse,
        );
      },
    );
  });

  group('durable inbox staging', () {
    test('configures a LAN commit handler when local P2P is present', () {
      final localP2P = FakeLocalP2PService();

      service = P2PServiceImpl(
        bridge: bridge,
        localP2PService: localP2P,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      expect(localP2P.inboundChatCommitHandler, isNotNull);
    });

    test(
      'stages LAN chat into inbox_staging before the commit decision and deletes the row on committed replay',
      () async {
        final localP2P = FakeLocalP2PService();
        final repo = _GateableInboxStagingRepository();
        final stageGate = Completer<void>();
        repo.stageGate = stageGate;
        final replayGate = Completer<RecoveredInboxReplayOutcome>();
        final replayedStagedIds = <String?>[];
        var decisionCompleted = false;

        service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: localP2P,
          inboxStagingRepository: repo,
          replayLiveLanChatMessage: (message, {String? stagedEntryId}) async {
            replayedStagedIds.add(stagedEntryId);
            expect(message.transport, 'wifi');
            expect(message.confirmNonce, isNull);
            return replayGate.future;
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                fail('live LAN replay should prefer the live callback');
              },
        );

        final handler = localP2P.inboundChatCommitHandler!;
        final events = await _captureFlowEvents(() async {
          final decisionFuture =
              Future<LanInboundDecision>.sync(
                () => handler(_lanChatMessage(id: 'msg-lan-001'), nonce: 'n1'),
              )..then((_) {
                decisionCompleted = true;
              });

          await _waitForCondition(
            () => repo.entry('lan:n1') != null,
            reason: 'LAN row should be staged before the commit decision',
          );
          expect(decisionCompleted, isFalse);
          expect(repo.entry('lan:n1')!.messageType, 'chat_message');

          stageGate.complete();
          final decision = await decisionFuture;
          expect(decision.isCommitted, isTrue);

          await _waitForCondition(
            () => replayedStagedIds.isNotEmpty,
            reason: 'live LAN replay callback should be invoked',
          );
          expect(replayedStagedIds, ['lan:n1']);

          replayGate.complete((
            disposition: RecoveredInboxChatDisposition.committed,
            reasonCode: 'stored',
            reasonDetail: null,
          ));
          await _waitForCondition(
            () => repo.entry('lan:n1') == null,
            reason: 'committed LAN replay should delete the staged row',
          );
        });

        expect(
          events.any(
            (event) =>
                event['event'] == 'P2P_SERVICE_LAN_STAGED_CHAT_COMMITTED',
          ),
          isTrue,
        );
      },
    );

    test(
      'rejects LAN commit when the account-migration gate blocks inbound',
      () async {
        final localP2P = FakeLocalP2PService();
        final repo = InMemoryInboxStagingRepository();
        final emitted = <ChatMessage>[];

        service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: localP2P,
          inboxStagingRepository: repo,
          accountMigrationNetworkGate: ({peerId, required operation}) async {
            expect(operation, 'p2p_inbound_message');
            expect(peerId, 'self-peer');
            return false;
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                fail('migration-gated LAN messages should not replay');
              },
        );
        final sub = service.messageStream.listen(emitted.add);

        final events = await _captureFlowEvents(() async {
          final decision = await Future<LanInboundDecision>.sync(
            () => localP2P.inboundChatCommitHandler!(
              _lanChatMessage(id: 'msg-lan-gated'),
              nonce: 'n-gated',
            ),
          );

          expect(decision.isRejected, isTrue);
          expect(decision.reason, 'account_migration_blocked');
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });

        expect(repo.entry('lan:n-gated'), isNull);
        expect(emitted, isEmpty);
        expect(
          events.any(
            (event) =>
                event['event'] == 'ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED',
          ),
          isTrue,
        );

        await sub.cancel();
      },
    );

    test(
      'F3 step 2: two concurrent drains coalesce — the SAME un-acked relay page '
      'is fetched exactly once',
      () async {
        service.dispose();
        final repo = _GateableInboxStagingRepository();
        var replayCount = 0;

        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                replayCount++;
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
        );
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'self-peer',
            'isStarted': true,
            'listenAddresses': [],
          }),
        );
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        bridge.calledCommands.clear();

        // Register the page + gate only AFTER startup, so startup does not
        // drain it. retrieve_pending is a non-destructive read: it returns the
        // same page on every call until the entry is acked.
        final stageGate = Completer<void>();
        repo.stageGate = stageGate;
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-coalesce-1',
                from: 'remote-peer',
                message: _chatEnvelope(
                  id: 'm1',
                  text: 'hi',
                  senderPeerId: 'remote-peer',
                ),
              ),
            ],
            'hasMore': false,
          }),
        );

        // Drain A retrieves the page, then parks in stageEntries on the gate.
        final a = service.drainOfflineInbox();
        await _waitForCondition(
          () => bridge.calledCommands.contains('inbox:retrieve_pending'),
          reason: 'drain A should retrieve the pending page',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Drain B starts while A is still parked and the page is un-acked.
        final b = service.drainOfflineInbox();
        await Future<void>.delayed(const Duration(milliseconds: 30));

        stageGate.complete();
        await Future.wait([a, b]);

        final retrieveCount = bridge.calledCommands
            .where((c) => c == 'inbox:retrieve_pending')
            .length;
        expect(
          retrieveCount,
          1,
          reason:
              'the second concurrent drain must coalesce onto the first, not '
              'fetch the same un-acked relay page a second time',
        );
        // And the entry is delivered exactly once (no double notification /
        // double receipt re-mint).
        expect(replayCount, 1);
      },
    );

    test('F3 step 2 lock: a drain interrupted before commit leaves the entry '
        'recoverable — a later (serialized) drain still replays it', () async {
      service.dispose();
      final repo = InMemoryInboxStagingRepository();
      var attempt = 0;

      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async {
              attempt++;
              // First replay is "interrupted" (retryable → row retained); a
              // later drain must pick it back up and commit it.
              if (attempt == 1) {
                return (
                  disposition: RecoveredInboxChatDisposition.retryable,
                  reasonCode: 'decryption_deferred',
                  reasonDetail: null,
                );
              }
              return (
                disposition: RecoveredInboxChatDisposition.committed,
                reasonCode: 'stored',
                reasonDetail: null,
              );
            },
      );
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'self-peer',
          'isStarted': true,
          'listenAddresses': [],
        }),
      );
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      bridge.whenCommand(
        'inbox:retrieve_pending',
        (_) => jsonEncode({
          'ok': true,
          'messages': [
            _pendingInboxRow(
              entryId: 'entry-recover-1',
              from: 'remote-peer',
              message: _chatEnvelope(
                id: 'm1',
                text: 'hi',
                senderPeerId: 'remote-peer',
              ),
            ),
          ],
          'hasMore': false,
        }),
      );

      await service.drainOfflineInbox();
      // The first drain replayed once but did NOT commit → entry retained.
      expect(attempt, greaterThanOrEqualTo(1));

      await service.drainOfflineInbox();
      // A later serialized drain re-replays the still-pending entry: the
      // mutex + stage idempotency must never DROP an interrupted entry.
      expect(
        attempt,
        greaterThanOrEqualTo(2),
        reason: 'an interrupted-before-commit entry must be re-replayed',
      );
    });

    // 146 TC-07 (PROD-CRITICAL end-to-end leg): the serial staged-inbox drain
    // (`_replayStagedInboxEntries`) replays ALL entries even when each replayed
    // message's delivery-receipt SEND never acks. This drives the REAL handler
    // (`handleIncomingChatMessage`) through the real loop, with the receipt send
    // gated on a Completer that NEVER completes — modelling the notif-tap
    // scenario (sender offline; the live receipt never round-trips). On HEAD the
    // handler awaits that send, so the loop hangs on entry #1 and the drain
    // times out; the 146 fix detaches the send so the loop drains every entry.
    //
    // NOTE: this leg lives here, NOT in inbox_round_trip_test.dart — that file's
    // FakeP2PService.drainOfflineInboxCount injects to a stream and yields one
    // turn per entry WITHOUT awaiting the handler, so the receipt-await never
    // gates its drain (the test would prove nothing on HEAD). The real
    // P2PServiceImpl loop here awaits chatReplay per entry, which is the leg the
    // fix actually unblocks.
    test(
      '146 TC-07: the staged-inbox drain replays ALL entries without blocking '
      'on per-message delivery-receipt sends',
      () async {
        service.dispose();

        const senderPeerId = 'remote-peer';
        final contactRepo = InMemoryContactRepository();
        contactRepo.addTestContact(
          const ContactModel(
            peerId: senderPeerId,
            publicKey: 'pk',
            rendezvous: '/dns4/relay/tcp/443/p2p/relay',
            username: 'Alice',
            signature: 'sig',
            scannedAt: '2026-04-01T00:00:00.000Z',
          ),
        );
        final msgRepo = InMemoryMessageRepository();
        final hungReceipt = Completer<void>(); // intentionally never completes
        var replayInvocations = 0;
        var receiptHookInvocations = 0;

        final repo = InMemoryInboxStagingRepository();
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                replayInvocations++;
                final (result, _, _) = await handleIncomingChatMessage(
                  message: message,
                  messageRepo: msgRepo,
                  contactRepo: contactRepo,
                  transport: message.transport,
                  stagedEntryId: stagedEntryId,
                  sendDeliveryReceipt: (_) {
                    receiptHookInvocations++;
                    return hungReceipt.future; // NEVER completes
                  },
                );
                expect(result, HandleChatMessageResult.chatMessage);
                // Durable persist happened → commit (delete + ack the row).
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
        );

        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'self-peer',
            'isStarted': true,
            'listenAddresses': [],
          }),
        );
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

        const n = 3;
        // Register the pending page AFTER startup so startup does not drain it.
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              for (var i = 1; i <= n; i++)
                _pendingInboxRow(
                  entryId: 'entry-fnf-$i',
                  from: senderPeerId,
                  // ids must be >8 chars: the handler's CHAT_MSG_RECEIVE_STORED
                  // does an unguarded payload.id.substring(0, 8).
                  message: _chatEnvelope(
                    id: 'msg-fnf-00$i',
                    text: 'message $i',
                    senderPeerId: senderPeerId,
                  ),
                ),
            ],
            'hasMore': false,
          }),
        );

        // On HEAD this hangs on entry #1's awaited receipt → TimeoutException.
        final events = await _captureFlowEvents(() async {
          await service.drainOfflineInbox().timeout(const Duration(seconds: 5));
        });

        expect(replayInvocations, n, reason: 'all $n entries were replayed');
        expect(
          receiptHookInvocations,
          n,
          reason: 'a receipt send was started for every entry',
        );
        expect(
          hungReceipt.isCompleted,
          isFalse,
          reason: 'the receipt sends remain detached (still pending)',
        );
        final persisted = await msgRepo.getMessagesForContact(senderPeerId);
        expect(persisted, hasLength(n));
        // The handler must return CLEANLY (committed replay), not throw post-
        // persist: assert every entry committed and NO replay exception.
        final committed = events
            .where(
              (e) => e['event'] == 'P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED',
            )
            .length;
        expect(
          committed,
          n,
          reason:
              'every entry committed via a clean replay (not the catch path)',
        );
        expect(
          events.where(
            (e) => e['event'] == 'P2P_SERVICE_INBOX_STAGED_REPLAY_EXCEPTION',
          ),
          isEmpty,
          reason: 'the real handler must not throw during replay',
        );
      },
    );

    // 172 TC-06 (PROD-CRITICAL — the 2026-06-28 incident reproduction): a
    // message ACKed off the relay whose sender momentarily looks unknown
    // (contact row not yet materialized) must NOT be terminally rejected —
    // custody already transferred, the staged row is the only copy. Drives the
    // REAL handler (handleIncomingChatMessage) and the REAL mapper
    // (mapChatReplayOutcomeToDisposition) through the real drain loop: drain N
    // keeps the entry recoverable; after the contact materializes, drain N+1
    // re-drives it to committed and the message is finally persisted.
    test('172 TC-06: unknownSender on drain N becomes displayed on drain N+1 '
        'after the contact materializes', () async {
      service.dispose();

      const senderPeerId = 'remote-peer';
      final contactRepo = InMemoryContactRepository(); // no contact yet
      final msgRepo = InMemoryMessageRepository();
      final repo = InMemoryInboxStagingRepository();

      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        // Mirrors main.dart's replayInboxChatMessage: real handler -> real
        // mapper (no synthetic dispositions).
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async {
              final (result, _, _) = await handleIncomingChatMessage(
                message: message,
                messageRepo: msgRepo,
                contactRepo: contactRepo,
                transport: message.transport,
                stagedEntryId: stagedEntryId,
              );
              final state = switch (result) {
                HandleChatMessageResult.chatMessage =>
                  ChatMessageProcessState.stored,
                HandleChatMessageResult.unknownSender =>
                  ChatMessageProcessState.unknownSender,
                HandleChatMessageResult.duplicate =>
                  ChatMessageProcessState.duplicate,
                _ => throw StateError('unexpected result $result'),
              };
              return mapChatReplayOutcomeToDisposition(
                ChatMessageProcessOutcome(
                  state: state,
                  // Mirror ChatMessageListener: the use case verifies the
                  // prior row is persisted before returning duplicate.
                  duplicatePriorPersisted:
                      result == HandleChatMessageResult.duplicate,
                ),
              );
            },
      );

      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'self-peer',
          'isStarted': true,
          'listenAddresses': [],
        }),
      );
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      // One-shot page: after drain N's stage+ACK the relay copy is DELETED
      // (the incident precondition — the staged row is the only copy), so
      // later drains see an empty relay page and only the recoverable sweep
      // can save the message.
      var relayPageServed = false;
      bridge.whenCommand('inbox:retrieve_pending', (_) {
        if (relayPageServed) {
          return jsonEncode({
            'ok': true,
            'messages': <Map<String, dynamic>>[],
            'hasMore': false,
          });
        }
        relayPageServed = true;
        return jsonEncode({
          'ok': true,
          'messages': [
            _pendingInboxRow(
              entryId: 'entry-172-incident',
              from: senderPeerId,
              message: _chatEnvelope(
                id: 'msg-172-0001',
                text: 'acked then vanished',
                senderPeerId: senderPeerId,
              ),
            ),
          ],
          'hasMore': false,
        });
      });

      // Drain N: custody transfers (stage + ack), sender unknown.
      await service.drainOfflineInbox();
      final afterDrainN = repo.entry('entry-172-incident');
      expect(afterDrainN, isNotNull, reason: 'INV-1: the row must be kept');
      expect(
        afterDrainN!.status,
        'retryable',
        reason:
            'a transient unknownSender after custody transfer must stay '
            'recoverable, never terminal rejected (the incident class)',
      );
      expect(await msgRepo.getMessagesForContact(senderPeerId), isEmpty);

      // The contact materializes (intro recovery / contact-row race heals).
      contactRepo.addTestContact(
        const ContactModel(
          peerId: senderPeerId,
          publicKey: 'pk',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Alice',
          signature: 'sig',
          scannedAt: '2026-04-01T00:00:00.000Z',
        ),
      );

      // Drain N+1 re-drives the recoverable entry through the real handler.
      await service.drainOfflineInbox();
      final persisted = await msgRepo.getMessagesForContact(senderPeerId);
      expect(
        persisted,
        hasLength(1),
        reason: 'the once-unknown message must finally be displayed',
      );
      expect(persisted.single.id, 'msg-172-0001');
      expect(
        repo.entry('entry-172-incident'),
        isNull,
        reason: 'committed replay deletes the staged row',
      );
    });

    // 172 TC-05: a recoverable rejection that never heals must converge to
    // QUARANTINED via the attempt cap — kept + surfaced, never deleted, never
    // terminal `rejected` (bounded retry, no infinite storm).
    test('172 TC-05: recoverable rejection retried past the attempt cap '
        'transitions to quarantined, never deleted', () async {
      service.dispose();

      final repo = InMemoryInboxStagingRepository();
      var replays = 0;
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async {
              replays++;
              // The REAL mapper on a persistently-unknown sender (no
              // resolver context, contact never materializes).
              return mapChatReplayOutcomeToDisposition(
                const ChatMessageProcessOutcome(
                  state: ChatMessageProcessState.unknownSender,
                ),
              );
            },
      );

      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'self-peer',
          'isStarted': true,
          'listenAddresses': [],
        }),
      );
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      bridge.whenCommand(
        'inbox:retrieve_pending',
        (_) => jsonEncode({
          'ok': true,
          'messages': [
            _pendingInboxRow(
              entryId: 'entry-172-capped',
              from: 'remote-peer',
              message: _chatEnvelope(
                id: 'msg-172-0002',
                text: 'never heals',
                senderPeerId: 'remote-peer',
              ),
            ),
          ],
          'hasMore': false,
        }),
      );

      // Attempts 1..cap mark retryable; the next drain hits the cap gate.
      for (var i = 0; i <= maxInboxReplayAttempts + 1; i++) {
        await service.drainOfflineInbox();
      }

      final entry = repo.entry('entry-172-capped');
      expect(
        entry,
        isNotNull,
        reason: 'INV-1: the capped entry is KEPT, never deleteEntry-ed',
      );
      expect(
        entry!.status,
        'quarantined',
        reason:
            'an exhausted recoverable entry must quarantine (kept + '
            'surfaced), not sit terminal rejected or retry forever',
      );
      expect(entry.rejectReasonCode, 'attempt_cap_exceeded');
      expect(
        replays,
        lessThanOrEqualTo(maxInboxReplayAttempts + 1),
        reason: 'the cap bounds the retry storm',
      );
    });

    test(
      'marks LAN staged row retryable on decryptionDeferred replay outcome',
      () async {
        final localP2P = FakeLocalP2PService();
        final repo = InMemoryInboxStagingRepository();

        service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: localP2P,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                expect(stagedEntryId, 'lan:n-retry');
                return (
                  disposition: RecoveredInboxChatDisposition.retryable,
                  reasonCode: 'decryption_deferred',
                  reasonDetail: 'BRIDGE_TIMEOUT',
                );
              },
        );

        final decision = await Future<LanInboundDecision>.sync(
          () => localP2P.inboundChatCommitHandler!(
            _lanChatMessage(id: 'msg-lan-retry'),
            nonce: 'n-retry',
          ),
        );
        expect(decision.isCommitted, isTrue);

        await _waitForCondition(
          () => repo.entry('lan:n-retry')?.status == 'retryable',
          reason: 'LAN replay retryable outcome should mark the row retryable',
        );
        final entry = repo.entry('lan:n-retry')!;
        expect(entry.rejectReasonCode, 'decryption_deferred');
        expect(entry.rejectReasonDetail, 'BRIDGE_TIMEOUT');
      },
    );

    test(
      'quarantines LAN staged row on decryptionFailed replay outcome',
      () async {
        final localP2P = FakeLocalP2PService();
        final repo = InMemoryInboxStagingRepository();

        service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: localP2P,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                expect(stagedEntryId, 'lan:n-quarantine');
                return (
                  disposition: RecoveredInboxChatDisposition.quarantined,
                  reasonCode: 'decryption_failed',
                  reasonDetail: 'message authentication failed',
                );
              },
        );

        final decision = await Future<LanInboundDecision>.sync(
          () => localP2P.inboundChatCommitHandler!(
            _lanChatMessage(id: 'msg-lan-quarantine'),
            nonce: 'n-quarantine',
          ),
        );
        expect(decision.isCommitted, isTrue);

        await _waitForCondition(
          () => repo.entry('lan:n-quarantine')?.status == 'quarantined',
          reason: 'LAN replay quarantine outcome should quarantine the row',
        );
        final entry = repo.entry('lan:n-quarantine')!;
        expect(entry.rejectReasonCode, 'decryption_failed');
        expect(entry.rejectReasonDetail, 'message authentication failed');
      },
    );

    test(
      'LAN staged row left by a killed process is recovered by startup replay sweep',
      () async {
        final localP2P = FakeLocalP2PService();
        final repo = InMemoryInboxStagingRepository();
        final killedReplay = Completer<RecoveredInboxReplayOutcome>();

        service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: localP2P,
          inboxStagingRepository: repo,
          replayLiveLanChatMessage: (message, {String? stagedEntryId}) =>
              killedReplay.future,
          replayRecoveredInboxChatMessage: (message, {String? stagedEntryId}) =>
              killedReplay.future,
        );

        final decision = await Future<LanInboundDecision>.sync(
          () => localP2P.inboundChatCommitHandler!(
            _lanChatMessage(id: 'msg-lan-restart'),
            nonce: 'n-restart',
          ),
        );
        expect(decision.isCommitted, isTrue);
        expect(repo.entry('lan:n-restart'), isNotNull);

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
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        final replayed = <String?>[];
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                replayed.add(stagedEntryId);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await service.drainOfflineInbox();

        expect(replayed, ['lan:n-restart']);
        expect(repo.entry('lan:n-restart'), isNull);

        killedReplay.complete((
          disposition: RecoveredInboxChatDisposition.committed,
          reasonCode: 'late',
          reasonDetail: null,
        ));
      },
    );

    test(
      'live LAN replay routes through live replay callback so notifications are not suppressed',
      () async {
        final localP2P = FakeLocalP2PService();
        final repo = InMemoryInboxStagingRepository();
        final liveReplayed = <String?>[];
        final recoveredReplayed = <String?>[];

        service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: localP2P,
          inboxStagingRepository: repo,
          replayLiveLanChatMessage: (message, {String? stagedEntryId}) async {
            liveReplayed.add(stagedEntryId);
            return (
              disposition: RecoveredInboxChatDisposition.committed,
              reasonCode: 'stored',
              reasonDetail: null,
            );
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                recoveredReplayed.add(stagedEntryId);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
        );

        await Future<LanInboundDecision>.sync(
          () => localP2P.inboundChatCommitHandler!(
            _lanChatMessage(id: 'msg-lan-live'),
            nonce: 'n-live',
          ),
        );

        await _waitForCondition(
          () => liveReplayed.isNotEmpty,
          reason: 'live LAN replay callback should be used when present',
        );
        expect(liveReplayed, ['lan:n-live']);
        expect(recoveredReplayed, isEmpty);

        final fallbackLocalP2P = FakeLocalP2PService();
        final fallbackRecovered = <String?>[];
        service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: fallbackLocalP2P,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                fallbackRecovered.add(stagedEntryId);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
        );

        await Future<LanInboundDecision>.sync(
          () => fallbackLocalP2P.inboundChatCommitHandler!(
            _lanChatMessage(id: 'msg-lan-fallback'),
            nonce: 'n-fallback',
          ),
        );
        await _waitForCondition(
          () => fallbackRecovered.isNotEmpty,
          reason: 'recovered callback should be fallback for live LAN replay',
        );
        expect(fallbackRecovered, ['lan:n-fallback']);
      },
    );

    test(
      'R2 direct chat and deletion confirm only after durable staging returns',
      () async {
        final repo = _GateableInboxStagingRepository();
        final replayedEntryIds = <String?>[];
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage: (_, {String? stagedEntryId}) async {
            fail('live direct chat must use the live replay callback');
          },
          replayLiveDirectChatMessage: (_, {String? stagedEntryId}) async {
            replayedEntryIds.add(stagedEntryId);
            return (
              disposition: RecoveredInboxChatDisposition.committed,
              reasonCode: 'stored',
              reasonDetail: null,
            );
          },
          replayRecoveredInboxMessageDeletion:
              (_, {String? stagedEntryId}) async {
                replayedEntryIds.add(stagedEntryId);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'deleted',
                  reasonDetail: null,
                );
              },
        );
        bridge.whenCommand(
          'message:confirm',
          (_) => jsonEncode({'ok': true, 'confirmed': true}),
        );

        final cases = <({String envelope, String nonce, String type})>[
          (
            type: 'chat_message',
            nonce: 'nonce-r2-chat-stage',
            envelope: _chatEnvelope(
              id: 'msg-r2-stage-order',
              text: 'stage before confirm',
              senderPeerId: 'remote-peer',
            ),
          ),
          (
            type: 'message_deletion',
            nonce: 'nonce-r2-deletion-stage',
            envelope: jsonEncode({
              'type': 'message_deletion',
              'version': '1',
              'payload': {
                'messageId': 'msg-r2-stage-order',
                'senderPeerId': 'remote-peer',
              },
            }),
          ),
        ];

        for (final testCase in cases) {
          final stageGate = Completer<void>();
          repo.stageGate = stageGate;
          final priorConfirmCount = bridge
              .payloadsFor('message:confirm')
              .length;
          final stagedEntryId = 'direct:${testCase.nonce}';

          bridge.onMessageReceived?.call(
            ChatMessage(
              from: 'remote-peer',
              to: 'self-peer',
              content: testCase.envelope,
              timestamp: '2026-04-01T00:00:00.000Z',
              isIncoming: true,
              transport: 'direct',
              confirmNonce: testCase.nonce,
            ),
          );

          await _waitForCondition(
            () => repo.entry(stagedEntryId) != null,
            reason: '${testCase.type} should enter recovery custody',
          );
          expect(repo.entry(stagedEntryId)!.messageType, testCase.type);
          expect(
            bridge.payloadsFor('message:confirm'),
            hasLength(priorConfirmCount),
            reason: 'message:confirm must wait for stageEntries to return',
          );

          stageGate.complete();
          await _waitForCondition(
            () =>
                bridge.payloadsFor('message:confirm').length ==
                priorConfirmCount + 1,
            reason: '${testCase.type} should confirm after staging returns',
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            bridge.payloadsFor('message:confirm'),
            hasLength(priorConfirmCount + 1),
          );
          expect(
            bridge.payloadsFor('message:confirm').last,
            equals({'nonce': testCase.nonce, 'ok': true}),
          );
        }

        expect(replayedEntryIds, [
          'direct:nonce-r2-chat-stage',
          'direct:nonce-r2-deletion-stage',
        ]);
      },
    );

    test(
      'direct chat with confirmNonce stages locally, confirms, and commits via '
      'the live-direct replay callback (recovery callback never used)',
      () async {
        // 118 Phase 1: the LIVE direct path now routes through the
        // notify-capable live-direct callback; the suppressing recovery
        // callback must NOT see a `direct:` entry on the live path.
        final repo = InMemoryInboxStagingRepository();
        final replayedIds = <String>[];
        final replayedStagedEntryIds = <String?>[];
        final recoveredStagedEntryIds = <String?>[];
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayLiveDirectChatMessage:
              (message, {String? stagedEntryId}) async {
                replayedStagedEntryIds.add(stagedEntryId);
                final payload =
                    (jsonDecode(message.content)
                            as Map<String, dynamic>)['payload']
                        as Map<String, dynamic>;
                replayedIds.add(payload['id'] as String);
                expect(message.confirmNonce, isNull);
                expect(message.transport, 'direct');
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                recoveredStagedEntryIds.add(stagedEntryId);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
        );

        bridge.whenCommand(
          'message:confirm',
          (_) => jsonEncode({'ok': true, 'confirmed': true}),
        );

        bridge.onMessageReceived?.call(
          ChatMessage(
            from: 'remote-peer',
            to: 'self-peer',
            content: _chatEnvelope(
              id: 'msg-direct-001',
              text: 'hello direct',
              senderPeerId: 'remote-peer',
            ),
            timestamp: '2026-04-01T00:00:00.000Z',
            isIncoming: true,
            transport: 'direct',
            confirmNonce: 'nonce-direct-001',
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(replayedIds, ['msg-direct-001']);
        expect(replayedStagedEntryIds, ['direct:nonce-direct-001']);
        expect(recoveredStagedEntryIds, isEmpty);
        expect(repo.entry('direct:nonce-direct-001'), isNull);
        final confirmPayloads = bridge.payloadsFor('message:confirm');
        expect(confirmPayloads, hasLength(1));
        expect(
          confirmPayloads.single,
          equals({'nonce': 'nonce-direct-001', 'ok': true}),
        );
      },
    );

    test('direct chat with confirmNonce keeps staged row retryable when the '
        'live-direct replay callback asks for retry', () async {
      final repo = InMemoryInboxStagingRepository();
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        replayLiveDirectChatMessage: (_, {String? stagedEntryId}) async {
          return (
            disposition: RecoveredInboxChatDisposition.retryable,
            reasonCode: 'missing_mlkem_secret',
            reasonDetail: 'secret unavailable',
          );
        },
        replayRecoveredInboxChatMessage: (_, {String? stagedEntryId}) async {
          fail(
            'live direct retry must not route through the recovery '
            'callback',
          );
        },
      );

      bridge.whenCommand(
        'message:confirm',
        (_) => jsonEncode({'ok': true, 'confirmed': true}),
      );

      bridge.onMessageReceived?.call(
        ChatMessage(
          from: 'remote-peer',
          to: 'self-peer',
          content: _chatEnvelope(
            id: 'msg-direct-retry',
            text: 'retry me later',
            senderPeerId: 'remote-peer',
          ),
          timestamp: '2026-04-01T00:00:00.000Z',
          isIncoming: true,
          transport: 'direct',
          confirmNonce: 'nonce-direct-retry',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final entry = repo.entry('direct:nonce-direct-retry');
      expect(entry, isNotNull);
      expect(entry!.status, 'retryable');
      expect(entry.rejectReasonCode, 'missing_mlkem_secret');
      expect(entry.rejectReasonDetail, 'secret unavailable');
      final confirmPayloads = bridge.payloadsFor('message:confirm');
      expect(confirmPayloads, hasLength(1));
      expect(
        confirmPayloads.single,
        equals({'nonce': 'nonce-direct-retry', 'ok': true}),
      );
    });

    test(
      'reaction stage failure uses shared notify-capable fallback exactly once',
      () async {
        final replayed = <ChatMessage>[];
        final stagedIds = <String?>[];
        final rawMessages = <ChatMessage>[];
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: _ThrowingInboxStagingRepository(),
          replayRecoveredInboxReaction:
              (message, {String? stagedEntryId}) async {
                replayed.add(message);
                stagedIds.add(stagedEntryId);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'reaction_committed',
                  reasonDetail: null,
                );
              },
        );
        final sub = service.messageStream.listen(rawMessages.add);
        bridge.whenCommand(
          'message:confirm',
          (_) => jsonEncode({'ok': true, 'confirmed': true}),
        );

        bridge.onMessageReceived?.call(
          ChatMessage(
            from: 'remote-peer',
            to: 'self-peer',
            content: _reactionEnvelope(messageId: 'reaction-target'),
            timestamp: '2026-04-01T00:00:00.000Z',
            isIncoming: true,
            transport: 'direct',
            confirmNonce: 'nonce-reaction-stage-error',
          ),
        );

        await _waitForCondition(
          () => replayed.isNotEmpty,
          reason: 'reaction replay callback should receive staging fallback',
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(replayed, hasLength(1));
        expect(replayed.single.confirmNonce, isNull);
        expect(stagedIds, <String?>[null]);
        expect(rawMessages, isEmpty);
        expect(bridge.payloadsFor('message:confirm'), hasLength(1));

        await sub.cancel();
      },
    );

    test(
      'nonce-less direct reaction uses shared replay and never raw listener',
      () async {
        final replayed = <ChatMessage>[];
        final rawMessages = <ChatMessage>[];
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          replayRecoveredInboxReaction:
              (message, {String? stagedEntryId}) async {
                replayed.add(message);
                expect(stagedEntryId, isNull);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'reaction_committed',
                  reasonDetail: null,
                );
              },
        );
        final sub = service.messageStream.listen(rawMessages.add);

        bridge.onMessageReceived?.call(
          ChatMessage(
            from: 'remote-peer',
            to: 'self-peer',
            content: _reactionEnvelope(messageId: 'nonce-less-target'),
            timestamp: '2026-04-01T00:00:00.000Z',
            isIncoming: true,
            transport: 'direct',
          ),
        );

        await _waitForCondition(
          () => replayed.isNotEmpty,
          reason: 'shared reaction replay should receive nonce-less direct',
        );
        expect(replayed, hasLength(1));
        expect(rawMessages, isEmpty);
        await sub.cancel();
      },
    );

    test(
      'LAN reaction stage failure uses shared replay and never raw listener',
      () async {
        final localP2P = FakeLocalP2PService();
        final replayed = <ChatMessage>[];
        final rawMessages = <ChatMessage>[];
        service = P2PServiceImpl(
          bridge: bridge,
          localP2PService: localP2P,
          inboxStagingRepository: _ThrowingInboxStagingRepository(),
          replayRecoveredInboxReaction:
              (message, {String? stagedEntryId}) async {
                replayed.add(message);
                expect(stagedEntryId, isNull);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'reaction_committed',
                  reasonDetail: null,
                );
              },
        );
        final sub = service.messageStream.listen(rawMessages.add);

        final decision = await Future<LanInboundDecision>.sync(
          () => localP2P.inboundChatCommitHandler!(
            LocalChatMessage(
              from: 'remote-peer',
              to: 'self-peer',
              content: _reactionEnvelope(messageId: 'lan-stage-target'),
              timestamp: DateTime.utc(2026, 4),
              isIncoming: true,
            ),
            nonce: 'nonce-lan-reaction-stage-error',
          ),
        );

        expect(decision.isCommitted, isTrue);
        expect(replayed, hasLength(1));
        expect(rawMessages, isEmpty);
        await sub.cancel();
      },
    );

    test(
      'without replay callback direct chat still uses the legacy raw stream path',
      () async {
        final received = <ChatMessage>[];
        final sub = service.messageStream.listen(received.add);

        bridge.onMessageReceived?.call(
          ChatMessage(
            from: 'remote-peer',
            to: 'self-peer',
            content: _chatEnvelope(
              id: 'msg-direct-legacy',
              text: 'legacy path',
              senderPeerId: 'remote-peer',
            ),
            timestamp: '2026-04-01T00:00:00.000Z',
            isIncoming: true,
            transport: 'direct',
            confirmNonce: 'nonce-direct-legacy',
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(received, hasLength(1));
        expect(received.single.confirmNonce, 'nonce-direct-legacy');
        expect(
          inboxStagingRepository.entry('direct:nonce-direct-legacy'),
          isNull,
        );
        expect(bridge.calledCommands, isNot(contains('message:confirm')));

        await sub.cancel();
      },
    );

    test(
      'live direct chat does NOT fall back to the suppressing recovery '
      'callback when the live-direct callback is absent (no ?? recovery)',
      () async {
        // 118 Phase 1 (no-fallback guard): a direct: message must never reach
        // the suppressing recovery callback. When the live-direct callback is
        // absent (alternate entrypoint), it falls to the notify-capable
        // un-staged stream emit, NOT the recovery callback that swallows the
        // notification.
        final repo = InMemoryInboxStagingRepository();
        final recoveredStagedEntryIds = <String?>[];
        final emitted = <ChatMessage>[];

        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          // No replayLiveDirectChatMessage wired on purpose.
          replayLiveLanChatMessage: (message, {String? stagedEntryId}) async {
            return (
              disposition: RecoveredInboxChatDisposition.committed,
              reasonCode: 'stored',
              reasonDetail: null,
            );
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                recoveredStagedEntryIds.add(stagedEntryId);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
        );
        final sub = service.messageStream.listen(emitted.add);

        bridge.whenCommand(
          'message:confirm',
          (_) => jsonEncode({'ok': true, 'confirmed': true}),
        );

        bridge.onMessageReceived?.call(
          ChatMessage(
            from: 'remote-peer',
            to: 'self-peer',
            content: _chatEnvelope(
              id: 'msg-direct-nofallback',
              text: 'no fallback',
              senderPeerId: 'remote-peer',
            ),
            timestamp: '2026-04-01T00:00:00.000Z',
            isIncoming: true,
            transport: 'direct',
            confirmNonce: 'nonce-direct-nofallback',
          ),
        );

        await _waitForCondition(
          () => emitted.isNotEmpty,
          reason:
              'a live direct message must reach the notify-capable stream, '
              'not the suppressing recovery callback',
        );

        expect(recoveredStagedEntryIds, isEmpty);
        expect(emitted, hasLength(1));
        expect(emitted.single.confirmNonce, 'nonce-direct-nofallback');

        await sub.cancel();
      },
    );

    group('118 recovery-sweep prefix-aware routing', () {
      P2PServiceImpl buildSweepService({
        required InMemoryInboxStagingRepository repo,
        required List<String?> liveDirect,
        required List<String?> liveLan,
        required List<String?> recovered,
      }) {
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
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        return P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayLiveDirectChatMessage:
              (message, {String? stagedEntryId}) async {
                liveDirect.add(stagedEntryId);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
          replayLiveLanChatMessage: (message, {String? stagedEntryId}) async {
            liveLan.add(stagedEntryId);
            return (
              disposition: RecoveredInboxChatDisposition.committed,
              reasonCode: 'stored',
              reasonDetail: null,
            );
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                recovered.add(stagedEntryId);
                return (
                  disposition: RecoveredInboxChatDisposition.committed,
                  reasonCode: 'stored',
                  reasonDetail: null,
                );
              },
        );
      }

      InboxStagingEntry seedChatEntry(String entryId) => InboxStagingEntry(
        entryId: entryId,
        ownerPeerId: 'self-peer',
        senderPeerId: 'remote-peer',
        messageType: 'chat_message',
        relayTimestamp: '2026-04-01T00:00:00.000Z',
        envelope: _chatEnvelope(
          id: 'msg-$entryId',
          text: 'swept',
          senderPeerId: 'remote-peer',
        ),
        stagedAt: '2026-04-01T00:00:01.000Z',
      );

      test('a retried direct: entry stays notify-capable (live-direct) on the '
          'prefix-blind sweep', () async {
        final repo = InMemoryInboxStagingRepository();
        repo.seed(seedChatEntry('direct:nonce-retry-sweep'));
        final liveDirect = <String?>[];
        final liveLan = <String?>[];
        final recovered = <String?>[];
        service = buildSweepService(
          repo: repo,
          liveDirect: liveDirect,
          liveLan: liveLan,
          recovered: recovered,
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await service.drainOfflineInbox();

        expect(liveDirect, ['direct:nonce-retry-sweep']);
        expect(recovered, isEmpty);
        expect(liveLan, isEmpty);
        expect(repo.entry('direct:nonce-retry-sweep'), isNull);
      });

      test(
        'a retried lan: entry stays notify-capable (live-lan) on the sweep',
        () async {
          final repo = InMemoryInboxStagingRepository();
          repo.seed(seedChatEntry('lan:nonce-retry-sweep'));
          final liveDirect = <String?>[];
          final liveLan = <String?>[];
          final recovered = <String?>[];
          service = buildSweepService(
            repo: repo,
            liveDirect: liveDirect,
            liveLan: liveLan,
            recovered: recovered,
          );

          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
          await service.drainOfflineInbox();

          expect(liveLan, ['lan:nonce-retry-sweep']);
          expect(recovered, isEmpty);
          expect(liveDirect, isEmpty);
          expect(repo.entry('lan:nonce-retry-sweep'), isNull);
        },
      );

      test(
        'a genuine relay-recovered (non-prefixed) entry stays on the '
        'suppressing recovery callback even when live callbacks are wired',
        () async {
          final repo = InMemoryInboxStagingRepository();
          repo.seed(seedChatEntry('relay-recovered-1'));
          final liveDirect = <String?>[];
          final liveLan = <String?>[];
          final recovered = <String?>[];
          service = buildSweepService(
            repo: repo,
            liveDirect: liveDirect,
            liveLan: liveLan,
            recovered: recovered,
          );

          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
          await service.drainOfflineInbox();

          expect(recovered, ['relay-recovered-1']);
          expect(liveDirect, isEmpty);
          expect(liveLan, isEmpty);
          expect(repo.entry('relay-recovered-1'), isNull);
        },
      );
    });

    test('replays staged chat rows before fetching new relay pages', () async {
      final repo = InMemoryInboxStagingRepository();
      repo.seed(
        InboxStagingEntry(
          entryId: 'entry-existing',
          ownerPeerId: 'self-peer',
          senderPeerId: 'remote-peer',
          messageType: 'chat_message',
          relayTimestamp: '2026-04-01T00:00:00.000Z',
          envelope: jsonEncode({
            'type': 'chat_message',
            'version': '1',
            'payload': {
              'id': 'msg-existing',
              'text': 'hello',
              'senderPeerId': 'remote-peer',
              'senderUsername': 'Alice',
              'timestamp': '2026-04-01T00:00:00.000Z',
            },
          }),
          stagedAt: '2026-04-01T00:00:01.000Z',
        ),
      );
      final replayedIds = <String>[];

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
      bridge.whenCommand('inbox:retrieve_pending', (_) {
        expect(replayedIds, ['msg-existing']);
        return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
      });

      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async {
              final payload =
                  (jsonDecode(message.content)
                          as Map<String, dynamic>)['payload']
                      as Map<String, dynamic>;
              replayedIds.add(payload['id'] as String);
              return (
                disposition: RecoveredInboxChatDisposition.committed,
                reasonCode: 'stored',
                reasonDetail: null,
              );
            },
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.drainOfflineInbox();

      expect(repo.entry('entry-existing'), isNull);
      expect(bridge.calledCommands, contains('inbox:retrieve_pending'));
    });

    // TC-14 (145): the durable drain success telemetry carries per-segment
    // durations (retrieveMs/ackMs/replayMs) in addition to the staged/replayed
    // counts, so the relay round-trip can be profiled.
    test('P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS carries numeric '
        'retrieveMs/ackMs/replayMs', () async {
      final repo = InMemoryInboxStagingRepository();
      repo.seed(
        InboxStagingEntry(
          entryId: 'entry-timed',
          ownerPeerId: 'self-peer',
          senderPeerId: 'remote-peer',
          messageType: 'chat_message',
          relayTimestamp: '2026-04-01T00:00:00.000Z',
          envelope: jsonEncode({
            'type': 'chat_message',
            'version': '1',
            'payload': {
              'id': 'msg-timed',
              'text': 'hello',
              'senderPeerId': 'remote-peer',
              'senderUsername': 'Alice',
              'timestamp': '2026-04-01T00:00:00.000Z',
            },
          }),
          stagedAt: '2026-04-01T00:00:01.000Z',
        ),
      );

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
        'inbox:retrieve_pending',
        (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
      );

      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async => (
              disposition: RecoveredInboxChatDisposition.committed,
              reasonCode: 'stored',
              reasonDetail: null,
            ),
      );

      final events = await _captureFlowEvents(() async {
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await service.drainOfflineInbox();
      });

      final drainSuccess = events.firstWhere(
        (e) => e['event'] == 'P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
        orElse: () => <String, dynamic>{},
      );
      expect(
        drainSuccess,
        isNotEmpty,
        reason: 'a staged+replayed drain should emit STAGED_DRAIN_SUCCESS',
      );
      final details = drainSuccess['details'] as Map<String, dynamic>;
      // Existing fields preserved (additive change).
      expect(details['staged'], isA<int>());
      expect(details['replayed'], isA<int>());
      expect(details['note'], isNotNull);
      // New per-segment durations.
      expect(details['retrieveMs'], isA<int>());
      expect(details['retrieveMs'], greaterThanOrEqualTo(0));
      expect(details['ackMs'], isA<int>());
      expect(details['ackMs'], greaterThanOrEqualTo(0));
      expect(details['replayMs'], isA<int>());
      expect(details['replayMs'], greaterThanOrEqualTo(0));
    });

    test(
      'quarantined disposition keeps entry, marks quarantined, does not delete',
      () async {
        final repo = InMemoryInboxStagingRepository();
        repo.seed(
          InboxStagingEntry(
            entryId: 'entry-quarantine',
            ownerPeerId: 'self-peer',
            senderPeerId: 'remote-peer',
            messageType: 'chat_message',
            relayTimestamp: '2026-04-01T00:00:00.000Z',
            envelope: jsonEncode({
              'type': 'chat_message',
              'version': '2',
              'senderPeerId': 'remote-peer',
              'encrypted': {'kem': 'k', 'ciphertext': 'c', 'nonce': 'n'},
            }),
            stagedAt: '2026-04-01T00:00:01.000Z',
          ),
        );

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
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage: (_, {String? stagedEntryId}) async {
            return (
              disposition: RecoveredInboxChatDisposition.quarantined,
              reasonCode: 'decryption_failed',
              reasonDetail: 'message authentication failed',
            );
          },
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await service.drainOfflineInbox();

        final entry = repo.entry('entry-quarantine');
        expect(entry, isNotNull, reason: 'entry must never be deleted');
        expect(entry!.status, 'quarantined');
        expect(entry.rejectReasonCode, 'decryption_failed');
        expect(entry.rejectReasonDetail, 'message authentication failed');
      },
    );

    test('rejected disposition marks rejected', () async {
      final repo = InMemoryInboxStagingRepository();
      repo.seed(
        InboxStagingEntry(
          entryId: 'entry-reject',
          ownerPeerId: 'self-peer',
          senderPeerId: 'remote-peer',
          messageType: 'chat_message',
          relayTimestamp: '2026-04-01T00:00:00.000Z',
          envelope: jsonEncode({
            'type': 'chat_message',
            'version': '1',
            'payload': {
              'id': 'msg-reject',
              'text': 'hello',
              'senderPeerId': 'remote-peer',
              'senderUsername': 'Alice',
              'timestamp': '2026-04-01T00:00:00.000Z',
            },
          }),
          stagedAt: '2026-04-01T00:00:01.000Z',
        ),
      );

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
        'inbox:retrieve_pending',
        (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
      );

      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        replayRecoveredInboxChatMessage: (_, {String? stagedEntryId}) async {
          return (
            disposition: RecoveredInboxChatDisposition.rejected,
            reasonCode: 'blocked_sender',
            reasonDetail: null,
          );
        },
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.drainOfflineInbox();

      final entry = repo.entry('entry-reject');
      expect(entry, isNotNull);
      expect(entry!.status, 'rejected');
      expect(entry.rejectReasonCode, 'blocked_sender');
    });

    test('retryable past attempt cap transitions to quarantined', () async {
      final repo = InMemoryInboxStagingRepository();
      repo.seed(
        InboxStagingEntry(
          entryId: 'entry-capped',
          ownerPeerId: 'self-peer',
          senderPeerId: 'remote-peer',
          messageType: 'chat_message',
          relayTimestamp: '2026-04-01T00:00:00.000Z',
          envelope: jsonEncode({
            'type': 'chat_message',
            'version': '2',
            'senderPeerId': 'remote-peer',
            'encrypted': {'kem': 'k', 'ciphertext': 'c', 'nonce': 'n'},
          }),
          status: 'retryable',
          attemptCount: 9,
          stagedAt: '2026-04-01T00:00:01.000Z',
        ),
      );

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
        'inbox:retrieve_pending',
        (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
      );

      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        replayRecoveredInboxChatMessage: (_, {String? stagedEntryId}) async {
          return (
            disposition: RecoveredInboxChatDisposition.retryable,
            reasonCode: 'decryption_deferred',
            reasonDetail: null,
          );
        },
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

      // First drain: attempt_count 9 -> 10, still retryable.
      await service.drainOfflineInbox();
      var entry = repo.entry('entry-capped');
      expect(entry, isNotNull);
      expect(entry!.status, 'retryable');
      expect(entry.attemptCount, 10);

      // Second drain: marking retryable would exceed the cap -> quarantined.
      await service.drainOfflineInbox();
      entry = repo.entry('entry-capped');
      expect(entry, isNotNull, reason: 'capped entry must never be deleted');
      expect(entry!.status, 'quarantined');
      expect(entry.rejectReasonCode, 'attempt_cap_exceeded');
    });

    test('protected and shadow page stages once before custody ACK', () async {
      final order = <String>[];
      final repo = _RecordingInboxStagingRepository(order);
      final replayedIds = <String>[];

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
      bridge.whenCommand('inbox:retrieve_pending', (payload) {
        order.add('retrieve');
        expect(payload?['custodyContract'], ackOrExpiryInboxCustodyContract);
        return jsonEncode({
          'ok': true,
          'messages': [
            {
              'id': 'entry-001',
              'from': 'remote-peer',
              'message': jsonEncode({
                'type': 'chat_message',
                'version': '1',
                'payload': {
                  'id': 'msg-001',
                  'text': 'hello',
                  'senderPeerId': 'remote-peer',
                  'senderUsername': 'Alice',
                  'timestamp': '2026-04-01T00:00:00.000Z',
                },
              }),
              'timestamp': '2026-04-01T00:00:00.000Z',
            },
          ],
          'hasMore': false,
        });
      });
      bridge.whenCommand('inbox:ack', (payload) {
        expect(order, <String>['retrieve', 'stage', 'replay']);
        order.add('ack');
        expect(payload?['entryIds'], ['entry-001']);
        expect(payload?['custodyContract'], ackOrExpiryInboxCustodyContract);
        return jsonEncode({'ok': true, 'acked': 1});
      });

      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async {
              expect(repo.entry('entry-001'), isNotNull);
              order.add('replay');
              final payload =
                  (jsonDecode(message.content)
                          as Map<String, dynamic>)['payload']
                      as Map<String, dynamic>;
              replayedIds.add(payload['id'] as String);
              return (
                disposition: RecoveredInboxChatDisposition.committed,
                reasonCode: 'stored',
                reasonDetail: null,
              );
            },
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.drainOfflineInbox();

      expect(replayedIds, ['msg-001']);
      expect(repo.stageCallCount, 1);
      expect(order, <String>['retrieve', 'stage', 'replay', 'ack']);
      expect(repo.entry('entry-001'), isNull);
      expect(bridge.calledCommands, contains('inbox:retrieve_pending'));
      expect(bridge.calledCommands, contains('inbox:ack'));
    });

    test(
      'gate denial at the ACK boundary keeps relay entries unacked',
      () async {
        // A Move Account export pause can land while a drain is already past
        // its entry gate; the ACK boundary re-check must keep the relay copy
        // alive for the new phone.
        final repo = InMemoryInboxStagingRepository();
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
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              {
                'id': 'entry-gated-001',
                'from': 'remote-peer',
                'message': jsonEncode({
                  'type': 'chat_message',
                  'version': '1',
                  'payload': {
                    'id': 'msg-gated-001',
                    'text': 'hello',
                    'senderPeerId': 'remote-peer',
                    'senderUsername': 'Alice',
                    'timestamp': '2026-04-01T00:00:00.000Z',
                  },
                }),
                'timestamp': '2026-04-01T00:00:00.000Z',
              },
            ],
            'hasMore': false,
          }),
        );
        bridge.whenCommand(
          'inbox:ack',
          (_) => jsonEncode({'ok': true, 'acked': 1}),
        );

        final blockedOperations = <String>{'p2p_inbox_ack_after_stage'};
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          accountMigrationNetworkGate: ({peerId, required operation}) async =>
              !blockedOperations.contains(operation),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await service.drainOfflineInbox();

        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));
        expect(bridge.calledCommands, isNot(contains('inbox:ack')));
        expect(repo.entry('entry-gated-001'), isNotNull);
      },
    );

    test('gate denial stops backlog pagination between drain pages', () async {
      final repo = InMemoryInboxStagingRepository();
      var retrieveCalls = 0;
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
      bridge.whenCommand('inbox:retrieve_pending', (_) {
        retrieveCalls++;
        return jsonEncode({
          'ok': true,
          'messages': [
            {
              'id': 'entry-page-$retrieveCalls',
              'from': 'remote-peer',
              'message': jsonEncode({
                'type': 'chat_message',
                'version': '1',
                'payload': {
                  'id': 'msg-page-$retrieveCalls',
                  'text': 'hello',
                  'senderPeerId': 'remote-peer',
                  'senderUsername': 'Alice',
                  'timestamp': '2026-04-01T00:00:00.000Z',
                },
              }),
              'timestamp': '2026-04-01T00:00:00.000Z',
            },
          ],
          'hasMore': true,
        });
      });
      bridge.whenCommand(
        'inbox:ack',
        (_) => jsonEncode({'ok': true, 'acked': 1}),
      );

      final blockedOperations = <String>{'p2p_drain_offline_inbox_page'};
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        accountMigrationNetworkGate: ({peerId, required operation}) async =>
            !blockedOperations.contains(operation),
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async => (
              disposition: RecoveredInboxChatDisposition.committed,
              reasonCode: 'stored',
              reasonDetail: null,
            ),
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.drainOfflineInboxFully();

      // First page drained on the foreground budget; the continuation is
      // gated per page, so no second retrieve happens.
      expect(retrieveCalls, 1);
    });

    test(
      'retryable chat outcomes keep the staged row with exact reason',
      () async {
        final repo = InMemoryInboxStagingRepository();

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
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              {
                'id': 'entry-retry',
                'from': 'remote-peer',
                'message': jsonEncode({
                  'type': 'chat_message',
                  'version': '2',
                  'senderPeerId': 'remote-peer',
                  'encrypted': {
                    'kem': 'kem-blob',
                    'ciphertext': 'cipher-blob',
                    'nonce': 'nonce-blob',
                  },
                }),
                'timestamp': '2026-04-01T00:00:00.000Z',
              },
            ],
            'hasMore': false,
          }),
        );
        bridge.whenCommand(
          'inbox:ack',
          (_) => jsonEncode({'ok': true, 'acked': 1}),
        );

        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage: (_, {String? stagedEntryId}) async {
            return (
              disposition: RecoveredInboxChatDisposition.retryable,
              reasonCode: 'missing_mlkem_secret',
              reasonDetail: 'secret unavailable',
            );
          },
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await service.drainOfflineInbox();

        final entry = repo.entry('entry-retry');
        expect(entry, isNotNull);
        expect(entry!.status, 'retryable');
        expect(entry.rejectReasonCode, 'missing_mlkem_secret');
        expect(entry.rejectReasonDetail, 'secret unavailable');
        expect(entry.attemptCount, 1);
      },
    );

    test('stages, acks, and deletes committed introduction entries', () async {
      final repo = InMemoryInboxStagingRepository();
      final replayedIntroIds = <String>[];

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
        'inbox:retrieve_pending',
        (_) => jsonEncode({
          'ok': true,
          'messages': [
            {
              'id': 'entry-intro-001',
              'from': 'peer-a',
              'message': jsonEncode({
                'type': 'introduction',
                'version': '1',
                'payload': {
                  'action': 'send',
                  'introductionId': 'intro-001',
                  'introducerId': 'peer-a',
                  'recipientId': 'self-peer',
                  'introducedId': 'peer-c',
                  'timestamp': '2026-04-01T00:00:00.000Z',
                },
              }),
              'timestamp': '2026-04-01T00:00:00.000Z',
            },
          ],
          'hasMore': false,
        }),
      );
      bridge.whenCommand('inbox:ack', (payload) {
        expect(payload?['entryIds'], ['entry-intro-001']);
        return jsonEncode({'ok': true, 'acked': 1});
      });

      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        replayRecoveredInboxIntroductionMessage: (message) async {
          final payload =
              (jsonDecode(message.content) as Map<String, dynamic>)['payload']
                  as Map<String, dynamic>;
          replayedIntroIds.add(payload['introductionId'] as String);
          return (
            disposition: RecoveredInboxChatDisposition.committed,
            reasonCode: 'stored',
            reasonDetail: null,
          );
        },
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      await service.drainOfflineInbox();

      expect(replayedIntroIds, ['intro-001']);
      expect(repo.entry('entry-intro-001'), isNull);
      expect(bridge.calledCommands, contains('inbox:ack'));
    });

    test(
      'retryable introduction outcomes keep the staged row with exact reason',
      () async {
        final repo = InMemoryInboxStagingRepository();

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
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              {
                'id': 'entry-intro-retry',
                'from': 'peer-b',
                'message': jsonEncode({
                  'type': 'introduction',
                  'version': '1',
                  'payload': {
                    'action': 'accept',
                    'introductionId': 'intro-retry',
                    'responderId': 'peer-b',
                    'timestamp': '2026-04-01T00:00:00.000Z',
                  },
                }),
                'timestamp': '2026-04-01T00:00:00.000Z',
              },
            ],
            'hasMore': false,
          }),
        );
        bridge.whenCommand(
          'inbox:ack',
          (_) => jsonEncode({'ok': true, 'acked': 1}),
        );

        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxIntroductionMessage: (_) async {
            return (
              disposition: RecoveredInboxChatDisposition.retryable,
              reasonCode: 'missing_own_peer_id',
              reasonDetail: 'identity not ready',
            );
          },
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await service.drainOfflineInbox();

        final entry = repo.entry('entry-intro-retry');
        expect(entry, isNotNull);
        expect(entry!.status, 'retryable');
        expect(entry.rejectReasonCode, 'missing_own_peer_id');
        expect(entry.rejectReasonDetail, 'identity not ready');
        expect(entry.attemptCount, 1);
      },
    );

    test(
      'returns safe no-progress when retrieve_pending is unsupported',
      () async {
        final repo = InMemoryInboxStagingRepository();

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
        service = P2PServiceImpl(bridge: bridge, inboxStagingRepository: repo);

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

        final received = <ChatMessage>[];
        final sub = service.messageStream.listen(received.add);

        await service.drainOfflineInbox();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));
        expect(bridge.calledCommands, isNot(contains('inbox:retrieve')));
        expect(bridge.calledCommands, isNot(contains('inbox:ack')));
        expect(received, isEmpty);

        await sub.cancel();
      },
    );

    test(
      'skips malformed pending rows while still replaying valid ones',
      () async {
        final repo = InMemoryInboxStagingRepository();

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
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-valid',
                from: 'remote-peer',
                message: jsonEncode({
                  'type': 'chat_message',
                  'version': '1',
                  'payload': {
                    'id': 'msg-valid',
                    'text': 'pending row staged safely',
                    'senderPeerId': 'remote-peer',
                    'senderUsername': 'Alice',
                    'timestamp': '2026-04-01T00:00:00.000Z',
                  },
                }),
              ),
              {
                'from': 'remote-peer',
                'message': jsonEncode({
                  'type': 'chat_message',
                  'version': '1',
                  'payload': {
                    'id': 'msg-missing-id',
                    'text': 'pending row missing id',
                    'senderPeerId': 'remote-peer',
                    'senderUsername': 'Alice',
                    'timestamp': '2026-04-01T00:00:00.000Z',
                  },
                }),
                'timestamp': '2026-04-01T00:00:00.000Z',
              },
            ],
            'hasMore': false,
          }),
        );

        service = P2PServiceImpl(bridge: bridge, inboxStagingRepository: repo);

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

        final received = <ChatMessage>[];
        final sub = service.messageStream.listen(received.add);

        await service.drainOfflineInbox();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));
        expect(bridge.calledCommands, contains('inbox:ack'));
        expect(bridge.calledCommands, isNot(contains('inbox:retrieve')));
        expect(received, hasLength(1));
        expect(received.single.content, contains('msg-valid'));

        await sub.cancel();
      },
    );

    group('F7 reactions/deletions stage-before-ack', () {
      // RED #1: a relay-inbox message_reaction must hold its staged row until
      // the reaction replay COMMITS. On HEAD (no reaction arm) the entry takes
      // the generic fall-through: a bare emit then immediate deleteEntry BEFORE
      // the listener's saveReaction commits, so a kill in that window loses the
      // reaction. With the F7 arm the row survives until committed.
      test(
        'relay-inbox reaction holds its staged row until replay commits',
        () async {
          service.dispose();
          final repo = _DeleteSpyInboxStagingRepository();
          final replayGate = Completer<RecoveredInboxReplayOutcome>();
          final replayedStagedIds = <String?>[];

          service = P2PServiceImpl(
            bridge: bridge,
            inboxStagingRepository: repo,
            replayRecoveredInboxReaction:
                (message, {String? stagedEntryId}) async {
                  replayedStagedIds.add(stagedEntryId);
                  // Park: do NOT return committed yet. The staged row must
                  // remain until we release the gate below.
                  return replayGate.future;
                },
          );
          bridge.whenCommand(
            'node:start',
            (_) => jsonEncode({
              'ok': true,
              'peerId': 'self-peer',
              'isStarted': true,
              'listenAddresses': [],
            }),
          );
          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
          bridge.whenCommand(
            'inbox:retrieve_pending',
            (_) => jsonEncode({
              'ok': true,
              'messages': [
                _pendingInboxRow(
                  entryId: 'entry-reaction-1',
                  from: 'remote-peer',
                  message: _reactionEnvelope(messageId: 'm1'),
                ),
              ],
              'hasMore': false,
            }),
          );

          // Kick the drain (not awaited — the replay parks on the gate).
          unawaited(service.drainOfflineInbox());

          await _waitForCondition(
            () => replayedStagedIds.contains('entry-reaction-1'),
            reason:
                'reaction replay callback should be invoked with the '
                'staged entry id',
          );

          // While the replay is parked, the staged row must NOT be deleted.
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(
            repo.deletedEntryIds,
            isNot(contains('entry-reaction-1')),
            reason:
                'the reaction row must survive until the replay commits — '
                'deleting before commit loses the reaction on a kill',
          );
          expect(repo.entry('entry-reaction-1'), isNotNull);

          // Release the gate with a committed disposition → row is deleted.
          replayGate.complete((
            disposition: RecoveredInboxChatDisposition.committed,
            reasonCode: 'success',
            reasonDetail: null,
          ));
          await _waitForCondition(
            () => repo.deletedEntryIds.contains('entry-reaction-1'),
            reason: 'committed reaction replay should delete the staged row',
          );
          expect(repo.entry('entry-reaction-1'), isNull);
        },
      );

      // Preserved-behavior lock: a relay-inbox chat_message still stages,
      // replays, and deletes the row exactly once on committed — proving the
      // new reaction/deletion arms did not disturb the chat arm.
      test(
        'relay-inbox chat still deletes its row once on committed replay',
        () async {
          service.dispose();
          final repo = _DeleteSpyInboxStagingRepository();
          final replayedStagedIds = <String?>[];

          service = P2PServiceImpl(
            bridge: bridge,
            inboxStagingRepository: repo,
            replayRecoveredInboxChatMessage:
                (message, {String? stagedEntryId}) async {
                  replayedStagedIds.add(stagedEntryId);
                  return (
                    disposition: RecoveredInboxChatDisposition.committed,
                    reasonCode: 'stored',
                    reasonDetail: null,
                  );
                },
          );
          bridge.whenCommand(
            'node:start',
            (_) => jsonEncode({
              'ok': true,
              'peerId': 'self-peer',
              'isStarted': true,
              'listenAddresses': [],
            }),
          );
          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
          bridge.whenCommand(
            'inbox:retrieve_pending',
            (_) => jsonEncode({
              'ok': true,
              'messages': [
                _pendingInboxRow(
                  entryId: 'entry-chat-keep-1',
                  from: 'remote-peer',
                  message: _chatEnvelope(
                    id: 'm1',
                    text: 'hi',
                    senderPeerId: 'remote-peer',
                  ),
                ),
              ],
              'hasMore': false,
            }),
          );

          await service.drainOfflineInbox();

          await _waitForCondition(
            () => repo.entry('entry-chat-keep-1') == null,
            reason: 'committed chat replay should delete the staged row',
          );
          expect(replayedStagedIds, ['entry-chat-keep-1']);
          expect(
            repo.deletedEntryIds.where((id) => id == 'entry-chat-keep-1'),
            hasLength(1),
            reason: 'the chat row must be deleted exactly once',
          );
        },
      );
    });
  });

  group('Phase 1 — startup and warm background', () {
    test(
      'startNode returns before background warm continuation drains remaining inbox pages',
      () async {
        final firstPage = Completer<String>();

        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand('inbox:retrieve_pending', (_) => firstPage.future);
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );

        final started = await service.startNode(
          'cHJpdmF0ZWtleXRlc3Q=',
          'test-peer',
        );

        expect(started, isTrue);
        expect(firstPage.isCompleted, isFalse);

        await Future<void>.delayed(Duration.zero);
        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));

        firstPage.complete(
          jsonEncode({'ok': true, 'messages': const [], 'hasMore': false}),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );

    test(
      'warmBackground drains inbox while relay reservation is still pending',
      () async {
        // Set up: node is started but no circuit addresses (relay pending)
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': ['/ip4/127.0.0.1/tcp/4001'],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': ['/ip4/127.0.0.1/tcp/4001'],
            'circuitAddresses': [], // Still no relay
            'connections': [],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-1',
                from: 'sender1',
                message:
                    '{"type":"chat_message","version":"1","payload":{"id":"m1","text":"hello","senderPeerId":"sender1","senderUsername":"S","timestamp":"2026-01-01T00:00:00Z"}}',
                timestamp: 1700000000000,
              ),
            ],
            'hasMore': false,
          }),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        // Collect messages
        final messages = <ChatMessage>[];
        final sub = service.messageStream.listen(messages.add);

        await service.warmBackground();

        // Give stream time to propagate
        await Future.delayed(const Duration(milliseconds: 50));

        // Inbox should have been drained even though relay is pending
        expect(messages.length, 1);
        expect(messages.first.from, 'sender1');

        // Circuit addresses are still empty — relay not ready
        expect(service.currentState.circuitAddresses, isEmpty);

        await sub.cancel();
      },
    );

    test('resume drains inbox before online indicator turns green', () async {
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': [],
          'connections': [],
        }),
      );
      bridge.whenCommand(
        'inbox:retrieve_pending',
        (_) => jsonEncode({
          'ok': true,
          'messages': [
            _pendingInboxRow(
              entryId: 'entry-resume',
              from: 'sender1',
              message: 'msg1',
              timestamp: 1700000000000,
            ),
          ],
          'hasMore': false,
        }),
      );
      bridge.whenCommand(
        'node:status',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': [], // Not online yet
          'connections': [],
        }),
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      final messages = <ChatMessage>[];
      final sub = service.messageStream.listen(messages.add);

      // Call drainOfflineInbox (simulating resume)
      await service.drainOfflineInbox();

      await Future.delayed(const Duration(milliseconds: 50));

      // Inbox drained before circuit addresses exist
      expect(messages.length, 1);
      expect(service.currentState.circuitAddresses, isEmpty);

      await sub.cancel();
    });

    test(
      'startup inbox drain shows first page before background continuation completes',
      () async {
        var retrieveCallCount = 0;
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand('inbox:retrieve_pending', (_) {
          retrieveCallCount++;
          return jsonEncode({
            'ok': true,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-$retrieveCallCount',
                from: 'sender$retrieveCallCount',
                message: 'msg$retrieveCallCount',
                timestamp: 1700000000000,
              ),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        final messages = <ChatMessage>[];
        final sub = service.messageStream.listen(messages.add);

        await service.warmBackground();

        await Future.delayed(const Duration(milliseconds: 50));

        // First page retrieved
        expect(messages.isNotEmpty, true);
        expect(retrieveCallCount, greaterThanOrEqualTo(1));

        await sub.cancel();
      },
    );

    test(
      'drainOfflineInbox uses foreground timeout for the first page',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) =>
              jsonEncode({'ok': true, 'messages': const [], 'hasMore': false}),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        await service.drainOfflineInbox();

        final firstPayload = bridge.payloadsFor('inbox:retrieve_pending').first;
        expect(
          firstPayload?['timeoutMs'],
          P2PServiceImpl.foregroundInboxTimeout.inMilliseconds,
        );
      },
    );

    test(
      'drainOfflineInbox schedules remaining pages on background budget',
      () async {
        var retrieveCallCount = 0;
        final secondPage = Completer<String>();

        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand('inbox:retrieve_pending', (_) {
          retrieveCallCount++;
          if (retrieveCallCount == 1) {
            return jsonEncode({
              'ok': true,
              'messages': [
                _pendingInboxRow(
                  entryId: 'entry-1',
                  from: 'sender1',
                  message: 'msg1',
                  timestamp: 1700000000000,
                ),
              ],
              'hasMore': true,
            });
          }
          return secondPage.future;
        });

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        final messages = <ChatMessage>[];
        final sub = service.messageStream.listen(messages.add);

        await service.drainOfflineInbox();

        await Future<void>.delayed(Duration.zero);
        expect(messages.length, 1);
        expect(
          bridge.payloadsFor('inbox:retrieve_pending').first?['timeoutMs'],
          P2PServiceImpl.foregroundInboxTimeout.inMilliseconds,
        );

        expect(bridge.payloadsFor('inbox:retrieve_pending').length, 2);
        expect(
          bridge.payloadsFor('inbox:retrieve_pending')[1]?['timeoutMs'],
          isNull,
        );

        secondPage.complete(
          jsonEncode({
            'ok': true,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-2',
                from: 'sender2',
                message: 'msg2',
                timestamp: 1700000001000,
              ),
            ],
            'hasMore': false,
          }),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(messages.length, 2);

        await sub.cancel();
      },
    );

    test(
      'drainOfflineInboxFully waits for remaining pages before returning',
      () async {
        var retrieveCallCount = 0;
        final secondPage = Completer<String>();

        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand('inbox:retrieve_pending', (_) {
          retrieveCallCount++;
          if (retrieveCallCount == 1) {
            return jsonEncode({
              'ok': true,
              'messages': [
                _pendingInboxRow(
                  entryId: 'entry-1',
                  from: 'sender1',
                  message: 'msg1',
                  timestamp: 1700000000000,
                ),
              ],
              'hasMore': true,
            });
          }
          return secondPage.future;
        });

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        final messages = <ChatMessage>[];
        final sub = service.messageStream.listen(messages.add);

        DirectInboxDrainOutcome? outcome;
        var fullDrainReturned = false;
        final fullDrain = service.drainOfflineInboxFully().then((value) {
          outcome = value;
          fullDrainReturned = true;
        });
        await Future<void>.delayed(Duration.zero);

        expect(fullDrainReturned, isFalse);
        expect(messages.length, 1);
        expect(bridge.payloadsFor('inbox:retrieve_pending'), hasLength(2));

        secondPage.complete(
          jsonEncode({
            'ok': true,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-2',
                from: 'sender2',
                message: 'msg2',
                timestamp: 1700000001000,
              ),
            ],
            'hasMore': false,
          }),
        );

        await fullDrain;
        expect(fullDrainReturned, isTrue);
        expect(outcome?.isSuccessful, isTrue);
        expect(outcome?.hasMore, isFalse);
        expect(messages.length, 2);

        await sub.cancel();
      },
    );

    test(
      'drainOfflineInboxFully coalesces with an ordinary drain continuation',
      () async {
        var retrieveCallCount = 0;
        final secondPage = Completer<String>();

        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': <String>[],
            'circuitAddresses': <String>[],
            'connections': <dynamic>[],
          }),
        );
        bridge.whenCommand('inbox:retrieve_pending', (_) {
          retrieveCallCount += 1;
          if (retrieveCallCount == 1) {
            return jsonEncode({
              'ok': true,
              'messages': <Map<String, dynamic>>[
                _pendingInboxRow(
                  entryId: 'entry-ordinary-first',
                  from: 'sender-first',
                  message: 'message-first',
                  timestamp: 1700000000000,
                ),
              ],
              'hasMore': true,
            });
          }
          return secondPage.future;
        });
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        await service.drainOfflineInbox();
        await _waitForCondition(
          () => retrieveCallCount == 2,
          reason: 'ordinary drain should start its background continuation',
        );
        expect(retrieveCallCount, 2);

        var fullDrainReturned = false;
        final fullDrain = service.drainOfflineInboxFully().then((outcome) {
          fullDrainReturned = true;
          return outcome;
        });
        await Future<void>.delayed(Duration.zero);

        expect(fullDrainReturned, isFalse);
        expect(
          retrieveCallCount,
          2,
          reason: 'the full drain must join the existing continuation',
        );

        secondPage.complete(
          jsonEncode({
            'ok': true,
            'messages': <Map<String, dynamic>>[
              _pendingInboxRow(
                entryId: 'entry-ordinary-second',
                from: 'sender-second',
                message: 'message-second',
                timestamp: 1700000001000,
              ),
            ],
            'hasMore': false,
          }),
        );

        final outcome = await fullDrain;
        expect(outcome.isSuccessful, isTrue);
        expect(outcome.hasMore, isFalse);
        expect(retrieveCallCount, 2);
      },
    );

    test(
      'drainOfflineInboxFully reports a first-page retrieval failure',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': <String>[],
            'circuitAddresses': <String>[],
            'connections': <dynamic>[],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': false,
            'errorCode': 'relay_unavailable',
            'errorMessage': 'relay unavailable',
          }),
        );
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        final outcome = await service.drainOfflineInboxFully();

        expect(outcome.isSuccessful, isFalse);
        expect(outcome.hasMore, isTrue);
        expect(outcome.failureReason, contains('relay unavailable'));
      },
    );

    test(
      'drainOfflineInboxFully retains recovery when relay acknowledgement fails',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': <String>[],
            'circuitAddresses': <String>[],
            'connections': <dynamic>[],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': <Map<String, dynamic>>[
              _pendingInboxRow(
                entryId: 'entry-ack-failure',
                from: 'sender-ack-failure',
                message: 'message-ack-failure',
                timestamp: 1700000000000,
              ),
            ],
            'hasMore': false,
          }),
        );
        bridge.whenCommand(
          'inbox:ack',
          (_) => jsonEncode({
            'ok': false,
            'errorCode': 'relay_unavailable',
            'errorMessage': 'relay ack unavailable',
          }),
        );
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        final outcome = await service.drainOfflineInboxFully();

        expect(outcome.isSuccessful, isFalse);
        expect(outcome.hasMore, isTrue);
        expect(outcome.failureReason, contains('relay ack unavailable'));
      },
    );

    test(
      'drainOfflineInboxFully retains recovery when relay acknowledgement is partial',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': <String>[],
            'circuitAddresses': <String>[],
            'connections': <dynamic>[],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': <Map<String, dynamic>>[
              _pendingInboxRow(
                entryId: 'entry-partial-ack-1',
                from: 'sender-partial-ack',
                message: 'message-partial-ack-1',
                timestamp: 1700000000000,
              ),
              _pendingInboxRow(
                entryId: 'entry-partial-ack-2',
                from: 'sender-partial-ack',
                message: 'message-partial-ack-2',
                timestamp: 1700000000001,
              ),
            ],
            'hasMore': false,
          }),
        );
        bridge.whenCommand(
          'inbox:ack',
          (_) => jsonEncode({'ok': true, 'acked': 1}),
        );
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        final outcome = await service.drainOfflineInboxFully();

        expect(outcome.isSuccessful, isFalse);
        expect(outcome.hasMore, isTrue);
        expect(outcome.failureReason, contains('inbox_ack_incomplete'));
      },
    );

    test(
      'drainOfflineInboxFully retains recovery for an unstageable relay row',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': <String>[],
            'circuitAddresses': <String>[],
            'connections': <dynamic>[],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': <Map<String, dynamic>>[
              <String, dynamic>{'entryId': 'malformed-relay-row'},
            ],
            'hasMore': false,
          }),
        );
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        final outcome = await service.drainOfflineInboxFully();

        expect(outcome.isSuccessful, isFalse);
        expect(outcome.hasMore, isTrue);
        expect(outcome.failureReason, contains('malformed'));
        expect(bridge.calledCommands, isNot(contains('inbox:ack')));
      },
    );

    test('drainOfflineInboxFully reports page-cap remainder', () async {
      var retrieveCallCount = 0;
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': <String>[],
          'circuitAddresses': <String>[],
          'connections': <dynamic>[],
        }),
      );
      bridge.whenCommand('inbox:retrieve_pending', (_) {
        retrieveCallCount += 1;
        return jsonEncode({
          'ok': true,
          'messages': <Map<String, dynamic>>[
            _pendingInboxRow(
              entryId: 'entry-$retrieveCallCount',
              from: 'sender-$retrieveCallCount',
              message: 'message-$retrieveCallCount',
              timestamp: 1700000000000 + retrieveCallCount,
            ),
          ],
          'hasMore': true,
        });
      });
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      final outcome = await service.drainOfflineInboxFully();

      expect(retrieveCallCount, P2PServiceImpl.maxInboxPages);
      expect(outcome.isSuccessful, isFalse);
      expect(outcome.hasMore, isTrue);
      expect(outcome.failureReason, 'page_cap_reached');
    });

    test(
      'fast circuit fallback poll updates online state when push event is delayed',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        // node:status always returns circuit — the point is node:start had none
        // but the health check poll picks up the circuit address.
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
          }),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        // Initially no circuit from node:start
        expect(service.currentState.circuitAddresses, isEmpty);

        // Trigger health check manually — polls node:status
        await service.performImmediateHealthCheck();

        // Now should have circuit from the polled status
        expect(service.currentState.circuitAddresses, isNotEmpty);
      },
    );

    test(
      'early relay edge signal does not mark online before circuit or reservation readiness',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [], // No circuit yet — just relay socket
            'connections': [
              {
                'peerId': 'relay-peer',
                'address': '/dns4/relay/tcp/4001',
                'direction': 'outbound',
              },
            ],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        // Having a relay connection but no circuit addresses should not
        // mean we're "online" in the ConnectionStatusIndicator sense
        expect(service.currentState.circuitAddresses, isEmpty);
        expect(service.currentState.isStarted, true);
      },
    );

    test(
      'cold start after reboot prioritizes inbox retrieval before secondary warm tasks',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-cold-start',
                from: 'sender1',
                message: 'queued-msg',
                timestamp: 1700000000000,
              ),
            ],
            'hasMore': false,
          }),
        );

        // Full startNode includes warmBackground
        await service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        await Future<void>.delayed(Duration.zero);

        // Inbox retrieve_pending should have been called during warm background
        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));

        // inbox:retrieve_pending should come before subsequent node:status
        // health checks.
        final inboxIdx = bridge.calledCommands.indexOf(
          'inbox:retrieve_pending',
        );
        expect(inboxIdx, greaterThanOrEqualTo(0));
      },
    );

    test(
      'cold start quick retry burst runs before watchdog timer path',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        // startNode triggers warmBackground which includes inbox drain
        await service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        await Future<void>.delayed(Duration.zero);

        // Inbox was attempted early (during warm, before watchdog timer)
        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));

        // The health check timer interval is 30s, so inbox drain runs
        // well before the first health check would fire
        expect(P2PServiceImpl.healthCheckInterval.inSeconds, 30);
      },
    );

    test(
      'background relay healing keeps longer retry cadence than foreground send',
      () async {
        // This verifies the design: health check interval (30s) is much longer
        // than interactive timeouts (1.5-4s)
        expect(
          P2PServiceImpl.healthCheckInterval.inSeconds,
          greaterThanOrEqualTo(30),
        );
      },
    );
  });

  group('Phase 4 — relay session manager and reservation-aware health', () {
    test('health check uses relayState when present', () async {
      // When node:status returns relayState, the parsed NodeState should
      // include it for health decisions.
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': ['/p2p-circuit/relay1'],
          'connections': [],
          'relayState': 'online',
          'healthyRelayCount': 1,
          'watchdogRestartCount': 0,
          'needsGroupRecovery': true,
        }),
      );
      bridge.whenCommand(
        'inbox:retrieve',
        (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
      );
      bridge.whenCommand(
        'node:status',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': ['/p2p-circuit/relay1'],
          'connections': [],
          'relayState': 'online',
          'healthyRelayCount': 1,
          'watchdogRestartCount': 0,
          'needsGroupRecovery': true,
        }),
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // The NodeState should include the relayState field.
      expect(service.currentState.relayState, 'online');
      expect(service.currentState.healthyRelayCount, 1);
      expect(service.currentState.watchdogRestartCount, 0);
      expect(service.currentState.needsGroupRecovery, isTrue);
    });

    test(
      'legacy circuitAddresses path still works when relayState absent',
      () async {
        // When the Go bridge does not include relayState (pre-Phase 4),
        // the parser should still work and relayState should be null.
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': ['/ip4/127.0.0.1/tcp/4001'],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            // No relayState, healthyRelayCount, or watchdogRestartCount
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
          }),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        // Legacy fields work.
        expect(service.currentState.isStarted, true);
        expect(service.currentState.circuitAddresses, isNotEmpty);

        // New fields are null (absent from response).
        expect(service.currentState.relayState, isNull);
        expect(service.currentState.healthyRelayCount, isNull);
      },
    );

    test('relay state push updates current state without restart', () async {
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': [],
          'connections': [],
          'relayState': 'starting',
          'healthyRelayCount': 0,
        }),
      );
      bridge.whenCommand(
        'inbox:retrieve',
        (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
      );
      bridge.whenCommand(
        'node:status',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': ['/p2p-circuit/relay1'],
          'connections': [],
          'relayState': 'online',
          'healthyRelayCount': 1,
        }),
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Initially starting with no circuits.
      expect(service.currentState.relayState, 'starting');

      // After health check, the state should update in place (no restart).
      await service.performImmediateHealthCheck();

      // The relay state should be updated from the status response.
      expect(service.currentState.relayState, 'online');
      expect(service.currentState.healthyRelayCount, 1);
      expect(service.currentState.circuitAddresses, isNotEmpty);
    });

    test(
      'relay state push updates current state without waiting for addresses update',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'starting',
            'healthyRelayCount': 0,
            'watchdogRestartCount': 0,
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        bridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
          'watchdogRestartCount': 2,
          'needsGroupRecovery': true,
        });

        expect(service.currentState.relayState, 'online');
        expect(service.currentState.healthyRelayCount, 1);
        expect(service.currentState.watchdogRestartCount, 2);
        expect(service.currentState.needsGroupRecovery, isTrue);
      },
    );

    test(
      'addresses updated with empty circuits does not trigger recovery when relayState is online',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
          }),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        bridge.calledCommands.clear();

        bridge.onAddressesUpdated?.call(const [], const []);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(bridge.calledCommands, isNot(contains('relay:reconnect')));
        expect(bridge.calledCommands, isNot(contains('node:status')));
        expect(service.currentState.relayState, 'online');
      },
    );

    test(
      'health check prefers relayState when present even if circuit addresses are empty',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
          }),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        bridge.calledCommands.clear();

        await service.performImmediateHealthCheck();

        expect(bridge.calledCommands, contains('node:status'));
        expect(bridge.calledCommands, isNot(contains('relay:reconnect')));
        expect(service.currentState.relayState, 'online');
        expect(service.currentState.circuitAddresses, isEmpty);
      },
    );

    test(
      'relay state degradation push triggers immediate recovery without addresses fallback',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 0,
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        var statusCallCount = 0;
        bridge.whenCommand('node:status', (_) {
          statusCallCount++;
          if (statusCallCount == 1) {
            return jsonEncode({
              'ok': true,
              'peerId': 'test-peer',
              'isStarted': true,
              'listenAddresses': [],
              'circuitAddresses': [],
              'connections': [],
              'relayState': 'degraded',
              'healthyRelayCount': 0,
              'watchdogRestartCount': 0,
            });
          }
          return jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 0,
          });
        });
        bridge.whenCommand(
          'relay:reconnect',
          (_) => jsonEncode({'ok': true, 'recoveryMode': 'in_place'}),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        bridge.calledCommands.clear();

        final events = await _captureFlowEvents(() async {
          bridge.onRelayStateChanged?.call({
            'relayState': 'degraded',
            'healthyRelayCount': 0,
            'watchdogRestartCount': 0,
            'reason': 'relay_disconnected',
          });
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });

        expect(bridge.calledCommands, contains('relay:reconnect'));
        expect(service.lastRecoveryMethod, equals('in_place'));
        expect(service.currentState.relayState, 'online');

        final starts = events
            .where((event) => event['event'] == 'RELAY_RECOVERY_START')
            .toList(growable: false);
        expect(
          starts,
          isNotEmpty,
          reason: 'Push recovery should be attributed',
        );
        final details = starts.first['details'] as Map<String, dynamic>;
        expect(details['recoverySource'], 'relay_state_push');
      },
    );

    test(
      'relay reconnect uses recoveryMode and does not require legacy recoveryMethod',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 0,
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        var statusCallCount = 0;
        bridge.whenCommand('node:status', (_) {
          statusCallCount++;
          if (statusCallCount == 1) {
            return jsonEncode({
              'ok': true,
              'peerId': 'test-peer',
              'isStarted': true,
              'listenAddresses': [],
              'circuitAddresses': [],
              'connections': [],
              'relayState': 'degraded',
              'healthyRelayCount': 0,
              'watchdogRestartCount': 0,
            });
          }
          return jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 0,
          });
        });
        bridge.whenCommand(
          'relay:reconnect',
          (_) => jsonEncode({'ok': true, 'recoveryMethod': 'watchdog_restart'}),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        await service.performImmediateHealthCheck();

        expect(service.lastRecoveryMethod, equals('in_place'));
        expect(service.currentState.relayState, 'online');
      },
    );

    test(
      'NW-004 relay reconnect propagates needsGroupRecovery for group topic repair',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 0,
            'needsGroupRecovery': false,
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        var statusCallCount = 0;
        bridge.whenCommand('node:status', (_) {
          statusCallCount++;
          if (statusCallCount == 1) {
            return jsonEncode({
              'ok': true,
              'peerId': 'test-peer',
              'isStarted': true,
              'listenAddresses': [],
              'circuitAddresses': [],
              'connections': [],
              'relayState': 'degraded',
              'healthyRelayCount': 0,
              'watchdogRestartCount': 0,
              'needsGroupRecovery': false,
            });
          }
          return jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/repaired'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 1,
            'needsGroupRecovery': true,
          });
        });
        bridge.whenCommand(
          'relay:reconnect',
          (_) => jsonEncode({'ok': true, 'recoveryMode': 'watchdog_restart'}),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        bridge.calledCommands.clear();

        final observedStates = <NodeState>[];
        final subscription = service.stateStream.listen(observedStates.add);
        addTearDown(subscription.cancel);

        await service.performImmediateHealthCheck();

        expect(bridge.calledCommands, contains('relay:reconnect'));
        expect(service.lastRecoveryMethod, 'watchdog_restart');
        expect(service.currentState.relayState, 'online');
        expect(service.currentState.needsGroupRecovery, isTrue);
        expect(
          observedStates.any((state) => state.needsGroupRecovery == true),
          isTrue,
          reason:
              'reconnect state stream must tell Flutter to repair group topics',
        );
      },
    );

    test(
      'relay reconnect forwards Phase 3b foreground attribution into recovery event',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 0,
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        var statusCallCount = 0;
        bridge.whenCommand('node:status', (_) {
          statusCallCount++;
          if (statusCallCount == 1) {
            return jsonEncode({
              'ok': true,
              'peerId': 'test-peer',
              'isStarted': true,
              'listenAddresses': [],
              'circuitAddresses': [],
              'connections': [],
              'relayState': 'degraded',
              'healthyRelayCount': 0,
              'watchdogRestartCount': 0,
            });
          }
          return jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 0,
          });
        });
        bridge.whenCommand(
          'relay:reconnect',
          (_) => jsonEncode({
            'ok': true,
            'recoveryMode': 'in_place',
            'relayRefreshMs': 1250,
            'relayWarmMs': 110,
            'reserveRpcMs': 0,
            'circuitAddressWaitMs': 970,
            'personalReregisterMs': 45,
            'relayWarmParallelism': 2,
            'foregroundRecoveryPath': 'foreground_success',
            'foregroundRelayDialTimeoutMs': 3000,
            'autorelayRetryCadenceMs': 1000,
          }),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        final events = await _captureFlowEvents(() async {
          await service.performImmediateHealthCheck();
        });

        final recovered = events
            .where((event) {
              if (event['event'] != 'RELAY_OUTAGE_TIMING') {
                return false;
              }
              final details = event['details'] as Map<String, dynamic>;
              return details['phase'] == 'recovered';
            })
            .toList(growable: false);

        expect(
          recovered,
          isNotEmpty,
          reason: 'Should emit recovered outage event',
        );
        final details = recovered.first['details'] as Map<String, dynamic>;
        expect(details['relayWarmParallelism'], 2);
        expect(details['foregroundRecoveryPath'], 'foreground_success');
        expect(details['foregroundRelayDialTimeoutMs'], 3000);
        expect(details['autorelayRetryCadenceMs'], 1000);
        expect(details['circuitAddressWaitMs'], 970);
      },
    );

    test(
      'status push burst coalescing does not lose final online state',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        // Simulate a burst of status updates via the addresses:updated push.
        // The final state should be the one that sticks.
        var statusCallCount = 0;
        bridge.whenCommand('node:status', (_) {
          statusCallCount++;
          // Each call returns progressively more connected state.
          if (statusCallCount <= 2) {
            return jsonEncode({
              'ok': true,
              'peerId': 'test-peer',
              'isStarted': true,
              'listenAddresses': [],
              'circuitAddresses': [],
              'connections': [],
            });
          }
          return jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
          });
        });

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        // Simulate multiple health checks (as if push events triggered them).
        await service.performImmediateHealthCheck();
        await service.performImmediateHealthCheck();
        await service.performImmediateHealthCheck();

        // The final state should reflect online.
        expect(service.currentState.circuitAddresses, isNotEmpty);
      },
    );
  });

  group('Phase 6 readiness proof windows', () {
    test(
      'retrieve_pending ok:false does not record inbox proof success',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'degraded',
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': false, 'errorMessage': 'relay unavailable'}),
        );
        bridge.whenCommand('inbox:store', (_) => jsonEncode({'ok': true}));

        final events = await _captureFlowEvents(() async {
          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
          await service.warmBackground();
        });

        expect(service.currentState.sendCapabilityReady, isTrue);
        expect(service.currentState.inboxCapabilityReady, isFalse);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.connecting,
        );

        expect(
          events.where((e) => e['event'] == 'FIRST_INBOX_SUCCESS_IN_WINDOW'),
          isEmpty,
        );
        expect(
          events.where((e) => e['event'] == 'TIME_TO_SENDABLE_BADGE'),
          isEmpty,
        );
        expect(
          events.where(
            (e) => e['event'] == 'P2P_SERVICE_INBOX_RETRIEVE_PENDING_ERROR',
          ),
          hasLength(1),
        );

        final proofResults = events
            .where((e) => e['event'] == 'READINESS_PROOF_RESULT')
            .map((e) => e['details'] as Map<String, dynamic>)
            .toList();
        expect(
          proofResults.any(
            (details) =>
                details['capability'] == 'inbox' &&
                details['success'] == false &&
                details['proofSource'] == 'drain_offline_inbox' &&
                details['failureReason'] == 'relay unavailable',
          ),
          isTrue,
        );
      },
    );

    test(
      'retrieve_pending ok:true empty inbox records inbox proof success',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'degraded',
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        bridge.whenCommand('inbox:store', (_) => jsonEncode({'ok': true}));

        final events = await _captureFlowEvents(() async {
          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
          await service.warmBackground();
        });

        expect(service.currentState.sendCapabilityReady, isTrue);
        expect(service.currentState.inboxCapabilityReady, isTrue);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.online,
        );

        final firstInbox = events
            .where((e) => e['event'] == 'FIRST_INBOX_SUCCESS_IN_WINDOW')
            .map((e) => e['details'] as Map<String, dynamic>)
            .toList();
        expect(firstInbox, hasLength(1));
        expect(firstInbox.single['source'], 'drain_offline_inbox');
        expect(firstInbox.single['trigger'], 'system_action');
        expect(
          events.where((e) => e['event'] == 'TIME_TO_SENDABLE_BADGE'),
          hasLength(1),
        );
      },
    );

    test(
      'warmBackground reaches sendable state from proactive proofs before relay-ready',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'degraded',
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        bridge.whenCommand('inbox:store', (_) => jsonEncode({'ok': true}));

        final events = await _captureFlowEvents(() async {
          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
          await service.warmBackground();
        });

        expect(service.currentState.sendCapabilityReady, isTrue);
        expect(service.currentState.inboxCapabilityReady, isTrue);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.online,
        );

        final windowStarts = events
            .where((e) => e['event'] == 'READINESS_PROOF_WINDOW_START')
            .toList();
        expect(windowStarts, hasLength(1));

        final proofResults = events
            .where((e) => e['event'] == 'READINESS_PROOF_RESULT')
            .map((e) => e['details'] as Map<String, dynamic>)
            .toList();
        expect(
          proofResults.any(
            (details) =>
                details['capability'] == 'send' && details['success'] == true,
          ),
          isTrue,
        );
        expect(
          proofResults.any(
            (details) =>
                details['capability'] == 'inbox' && details['success'] == true,
          ),
          isTrue,
        );

        final sendable = events
            .where((e) => e['event'] == 'TIME_TO_SENDABLE_BADGE')
            .toList();
        expect(sendable, hasLength(1));
        final relayReady = events
            .where((e) => e['event'] == 'TIME_TO_RELAY_READY_BADGE')
            .toList();
        expect(relayReady, isEmpty);
      },
    );

    test(
      'warmBackground retries proactive send proof after an initial startup failure and reaches Online without user action',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'degraded',
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        var inboxStoreCallCount = 0;
        bridge.whenCommand('inbox:store', (_) {
          inboxStoreCallCount += 1;
          return jsonEncode({'ok': inboxStoreCallCount >= 2});
        });

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        final reachedPlainOnline = service.stateStream.firstWhere(
          (state) => state.badgeReadinessState == BadgeReadinessState.online,
        );

        final events = await _captureFlowEvents(() async {
          await service.warmBackground();
          await reachedPlainOnline;
        });

        expect(inboxStoreCallCount, 2);
        expect(service.currentState.sendCapabilityReady, isTrue);
        expect(service.currentState.inboxCapabilityReady, isTrue);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.online,
        );

        final sendProofResults = events
            .where((e) => e['event'] == 'READINESS_PROOF_RESULT')
            .map((e) => e['details'] as Map<String, dynamic>)
            .where((details) => details['capability'] == 'send')
            .toList(growable: false);
        expect(
          sendProofResults.any(
            (details) =>
                details['success'] == false &&
                details['proofSource'] == 'system_inbox_store_probe' &&
                details['failureReason'] == 'store_returned_false',
          ),
          isTrue,
        );
        expect(
          sendProofResults.any(
            (details) =>
                details['success'] == true &&
                details['proofSource'] == 'system_inbox_store_probe',
          ),
          isTrue,
        );

        final firstSend = events
            .where((e) => e['event'] == 'FIRST_SEND_SUCCESS_IN_WINDOW')
            .map((e) => e['details'] as Map<String, dynamic>)
            .single;
        expect(firstSend['source'], 'system_inbox_store_probe');
        expect(firstSend['trigger'], 'system_action');

        expect(
          events.where((e) => e['event'] == 'TIME_TO_SENDABLE_BADGE'),
          hasLength(1),
        );
      },
    );

    test(
      'relay-ready transition retries proactive send proof after earlier startup failures and reaches Online. without user action',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'degraded',
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        var inboxStoreCallCount = 0;
        bridge.whenCommand('inbox:store', (_) {
          inboxStoreCallCount += 1;
          return jsonEncode({'ok': inboxStoreCallCount >= 3});
        });

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        await service.warmBackground();
        for (var i = 0; i < 10 && inboxStoreCallCount < 2; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(inboxStoreCallCount, 2);
        expect(service.currentState.sendCapabilityReady, isFalse);
        expect(service.currentState.inboxCapabilityReady, isTrue);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.connecting,
        );

        final reachedRelayReady = service.stateStream.firstWhere(
          (state) =>
              state.badgeReadinessState == BadgeReadinessState.onlineDotted,
        );

        final events = await _captureFlowEvents(() async {
          bridge.onRelayStateChanged?.call({
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 0,
            'needsGroupRecovery': false,
            'reason': 'relay_connected',
          });
          await reachedRelayReady;
        });

        expect(inboxStoreCallCount, 3);
        expect(service.currentState.sendCapabilityReady, isTrue);
        expect(service.currentState.inboxCapabilityReady, isTrue);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.onlineDotted,
        );

        final firstSend = events
            .where((e) => e['event'] == 'FIRST_SEND_SUCCESS_IN_WINDOW')
            .map((e) => e['details'] as Map<String, dynamic>)
            .single;
        expect(firstSend['source'], 'system_inbox_store_probe');
        expect(firstSend['trigger'], 'system_action');

        expect(
          events.where((e) => e['event'] == 'TIME_TO_SENDABLE_BADGE'),
          hasLength(1),
        );
        expect(
          events.where((e) => e['event'] == 'TIME_TO_RELAY_READY_BADGE'),
          hasLength(1),
        );
      },
    );

    test(
      'relay-ready alone does not unlock the service-owned ready state',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
          }),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        expect(service.currentState.relayReady, isTrue);
        expect(service.currentState.sendCapabilityReady, isFalse);
        expect(service.currentState.inboxCapabilityReady, isFalse);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.connecting,
        );
      },
    );

    test(
      'successful inbox retrieval completes a send-only proof window when relay-ready is already true',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        service.recordSuccessfulSendProof(
          source: 'test_send',
          trigger: 'user_action',
          sendPath: 'direct',
        );

        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.connecting,
        );

        final events = await _captureFlowEvents(() async {
          final messages = await service.retrieveInbox();
          expect(messages, isEmpty);
        });

        expect(service.currentState.inboxCapabilityReady, isTrue);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.onlineDotted,
        );
        expect(
          events.where((e) => e['event'] == 'TIME_TO_SENDABLE_BADGE'),
          hasLength(1),
        );
        expect(
          events.where((e) => e['event'] == 'TIME_TO_RELAY_READY_BADGE'),
          hasLength(1),
        );
      },
    );

    test(
      'background resume starts a new proof window instead of reusing stale proof',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
          }),
        );
        // 189: the resume health check now ALSO drains the offline inbox
        // (drain-on-every-tick, Fix A). A drain that succeeds is a legitimate
        // FRESH inbox proof for the new window — so this test's subject
        // (stale proofs must not be REUSED) needs the degraded relay to fail
        // retrieve_pending during the resume tick.
        var retrievePendingFails = false;
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode(
            retrievePendingFails
                ? {'ok': false, 'errorCode': 'RELAY_DEGRADED'}
                : {'ok': true, 'messages': [], 'hasMore': false},
          ),
        );
        var inboxStoreCallCount = 0;
        bridge.whenCommand('inbox:store', (_) {
          inboxStoreCallCount += 1;
          return jsonEncode({'ok': inboxStoreCallCount == 1});
        });
        var statusCallCount = 0;
        bridge.whenCommand('node:status', (_) {
          statusCallCount += 1;
          return jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': <String>[],
            'connections': [],
            'relayState': statusCallCount == 1 ? 'degraded' : 'degraded',
          });
        });
        bridge.whenCommand('relay:reconnect', (_) => jsonEncode({'ok': true}));

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        await service.warmBackground();
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.onlineDotted,
        );

        retrievePendingFails = true;
        service.markResumeStarted();
        final events = await _captureFlowEvents(() async {
          await service.performImmediateHealthCheck();
          service.clearResumeStarted();
        });

        expect(service.currentState.sendCapabilityReady, isFalse);
        expect(service.currentState.inboxCapabilityReady, isFalse);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.connecting,
        );

        final windowStart = events
            .where((e) => e['event'] == 'READINESS_PROOF_WINDOW_START')
            .map((e) => e['details'] as Map<String, dynamic>)
            .last;
        expect(windowStart['phase'], 'background_resume');
      },
    );
  });

  group('FDC-14b directReady producer', () {
    test('directReady is set when a non-circuit connection is held', () async {
      await startNodeForDirectReadyProducer(
        relayState: 'online',
        circuitAddresses: const ['/p2p-circuit/relay1'],
      );

      connectPeerForDirectReadyProducer(
        peerId: 'direct-peer',
        multiaddrs: const ['/ip4/192.168.1.10/udp/45000/quic-v1'],
      );

      expect(service.currentState.directReady, isTrue);
      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.onlineDirect,
      );
    });

    test('directReady stays false for a circuit-only connection', () async {
      await startNodeForDirectReadyProducer(
        relayState: 'online',
        circuitAddresses: const ['/p2p-circuit/relay1'],
      );

      expect(service.currentState.connections, isEmpty);
      expect(service.currentState.directReady, isFalse);
      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.onlineDotted,
      );

      connectPeerForDirectReadyProducer(
        peerId: 'relay-path-peer',
        multiaddrs: const [
          '/dns4/relay.example/tcp/4001/p2p/relay-peer/p2p-circuit',
        ],
      );

      expect(service.currentState.directReady, isFalse);
      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.onlineDotted,
      );
    });

    test('directReady stays false for a relay-server connection', () async {
      await startNodeForDirectReadyProducer(
        relayState: 'online',
        circuitAddresses: const ['/p2p-circuit/relay1'],
      );

      connectPeerForDirectReadyProducer(
        peerId: 'relay-server-peer',
        multiaddrs: const ['/dns4/relay.example/tcp/4001'],
        isRelay: true,
      );

      expect(service.currentState.directReady, isFalse);
      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.onlineDotted,
      );
    });

    test(
      'directReady for a connection holding both a circuit and a direct multiaddr',
      () async {
        await startNodeForDirectReadyProducer(
          relayState: 'online',
          circuitAddresses: const ['/p2p-circuit/relay1'],
        );

        connectPeerForDirectReadyProducer(
          peerId: 'mixed-peer',
          multiaddrs: const [
            '/ip4/192.168.1.10/udp/45000/quic-v1',
            '/dns4/relay.example/tcp/4001/p2p/relay-peer/p2p-circuit',
          ],
        );

        expect(service.currentState.directReady, isTrue);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.onlineDirect,
        );
      },
    );

    test(
      'directReady reverts to false when the direct connection disconnects',
      () async {
        await startNodeForDirectReadyProducer(
          relayState: 'online',
          circuitAddresses: const ['/p2p-circuit/relay1'],
        );

        connectPeerForDirectReadyProducer(
          peerId: 'direct-peer',
          multiaddrs: const ['/ip4/192.168.1.10/udp/45000/quic-v1'],
        );
        expect(service.currentState.directReady, isTrue);

        disconnectPeerForDirectReadyProducer('direct-peer');

        expect(service.currentState.directReady, isFalse);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.onlineDotted,
        );
      },
    );

    test(
      'directReady true with capability not ready stays connecting',
      () async {
        await startNodeForDirectReadyProducer(
          relayState: 'online',
          circuitAddresses: const ['/p2p-circuit/relay1'],
          proveReadiness: false,
        );

        connectPeerForDirectReadyProducer(
          peerId: 'direct-peer',
          multiaddrs: const ['/ip4/192.168.1.10/udp/45000/quic-v1'],
        );

        expect(service.currentState.directReady, isTrue);
        expect(service.currentState.usabilityReady, isFalse);
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.connecting,
        );
      },
    );

    test(
      'reaching onlineDirect via a direct connection emits TIME_TO_ONLINE_BADGE exactly once',
      () async {
        await startNodeForDirectReadyProducer(relayState: 'degraded');
        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.online,
        );

        final events = await _captureFlowEvents(() async {
          connectPeerForDirectReadyProducer(
            peerId: 'direct-peer',
            multiaddrs: const ['/ip4/192.168.1.10/udp/45000/quic-v1'],
          );
        });

        expect(
          service.currentState.badgeReadinessState,
          BadgeReadinessState.onlineDirect,
        );
        expect(
          events.where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE'),
          hasLength(1),
        );
      },
    );

    test('reshuffle from onlineDotted to onlineDirect does not re-emit '
        'TIME_TO_ONLINE_BADGE (P-5 case 2: ready->ready emits zero)', () async {
      await startNodeForDirectReadyProducer(relayState: 'online');
      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.onlineDotted,
      );

      final events = await _captureFlowEvents(() async {
        connectPeerForDirectReadyProducer(
          peerId: 'direct-peer',
          multiaddrs: const ['/ip4/192.168.1.10/udp/45000/quic-v1'],
        );
      });

      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.onlineDirect,
      );
      expect(
        events.where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE'),
        isEmpty,
      );
    });

    test('onlineDirect does not emit TIME_TO_RELAY_READY_BADGE', () async {
      await startNodeForDirectReadyProducer(relayState: 'degraded');

      final events = await _captureFlowEvents(() async {
        connectPeerForDirectReadyProducer(
          peerId: 'direct-peer',
          multiaddrs: const ['/ip4/192.168.1.10/udp/45000/quic-v1'],
        );
      });

      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.onlineDirect,
      );
      expect(
        events.where((e) => e['event'] == 'TIME_TO_RELAY_READY_BADGE'),
        isEmpty,
      );
    });
  });

  group('§24 TIME_TO_ONLINE_BADGE', () {
    test(
      'cold start emits TIME_TO_ONLINE_BADGE after first online state via relay push',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'starting',
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        final events = await _captureFlowEvents(() async {
          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

          // Simulate relay coming online after a delay
          await Future<void>.delayed(const Duration(milliseconds: 50));
          bridge.onRelayStateChanged?.call({
            'relayState': 'online',
            'healthyRelayCount': 1,
          });
        });

        final badge = events
            .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE')
            .toList();
        expect(badge, hasLength(1));
        final details = badge.first['details'] as Map<String, dynamic>;
        expect(details['totalMs'], greaterThanOrEqualTo(50));
        expect(details['phase'], 'cold_start');
        expect(details['source'], 'relay_state_push');
      },
    );

    test(
      'fast circuit check path emits timing via health_check_poll',
      () async {
        bridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': [],
            'connections': [],
            'relayState': 'starting',
          }),
        );
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        bridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'test-peer',
            'isStarted': true,
            'listenAddresses': [],
            'circuitAddresses': ['/p2p-circuit/relay1'],
            'connections': [],
            'relayState': 'online',
            'healthyRelayCount': 1,
          }),
        );

        final events = await _captureFlowEvents(() async {
          await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

          // No relay push — health check poll discovers online
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await service.performImmediateHealthCheck();
        });

        final badge = events
            .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE')
            .toList();
        expect(badge, hasLength(1));
        final details = badge.first['details'] as Map<String, dynamic>;
        expect(details['totalMs'], greaterThanOrEqualTo(50));
        expect(details['source'], 'health_check_poll');
        expect(details['phase'], 'cold_start');
      },
    );

    test('already-online start emits near-zero timing', () async {
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': ['/p2p-circuit/relay1'],
          'connections': [],
          'relayState': 'online',
          'healthyRelayCount': 1,
        }),
      );

      final events = await _captureFlowEvents(() async {
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
      });

      final badge = events
          .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE')
          .toList();
      expect(badge, hasLength(1));
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['totalMs'], lessThan(500));
      expect(details['phase'], 'cold_start');
      expect(details['source'], 'start_response');
    });

    test('recovery emits TIME_TO_ONLINE_BADGE with phase=recovery', () async {
      // Start online
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': ['/p2p-circuit/relay1'],
          'connections': [],
          'relayState': 'online',
          'healthyRelayCount': 1,
        }),
      );
      bridge.whenCommand(
        'relay:reconnect',
        (_) => jsonEncode({'ok': true, 'recoveryMode': 'in_place'}),
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      // Now capture events during degradation → recovery
      final events = await _captureFlowEvents(() async {
        // Go degraded
        bridge.onRelayStateChanged?.call({
          'relayState': 'degraded',
          'healthyRelayCount': 0,
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Come back online
        bridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
        });
      });

      final badge = events
          .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE')
          .toList();
      expect(badge, hasLength(1));
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['totalMs'], greaterThanOrEqualTo(50));
      expect(details['phase'], 'recovery');
      expect(details['source'], 'relay_state_push');
    });

    test('no duplicate timing on transient flicker', () async {
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': ['/p2p-circuit/relay1'],
          'connections': [],
          'relayState': 'online',
          'healthyRelayCount': 1,
        }),
      );

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

      final events = await _captureFlowEvents(() async {
        // Flicker: online → degraded → online quickly
        bridge.onRelayStateChanged?.call({
          'relayState': 'degraded',
          'healthyRelayCount': 0,
        });
        bridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
        });
        // Second flicker
        bridge.onRelayStateChanged?.call({
          'relayState': 'degraded',
          'healthyRelayCount': 0,
        });
        bridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
        });
      });

      // Each degraded→online transition emits one recovery event
      final badges = events
          .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE')
          .toList();
      // Two distinct recovery cycles = two events (not four)
      expect(badges, hasLength(2));
      for (final b in badges) {
        expect((b['details'] as Map<String, dynamic>)['phase'], 'recovery');
      }
    });

    test('hot restart emits timing with phase=hot_restart', () async {
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': false,
          'errorCode': 'ALREADY_STARTED',
          'errorMessage': 'node already started',
        }),
      );
      bridge.whenCommand(
        'node:status',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'test-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': ['/p2p-circuit/relay1'],
          'connections': [],
          'relayState': 'online',
          'healthyRelayCount': 1,
        }),
      );

      final events = await _captureFlowEvents(() async {
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
      });

      final badge = events
          .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE')
          .toList();
      expect(badge, hasLength(1));
      final details = badge.first['details'] as Map<String, dynamic>;
      expect(details['phase'], 'hot_restart');
      expect(details['totalMs'], greaterThanOrEqualTo(0));
    });
  });

  // 141: A notif-open opportunistic drain requested while the libp2p node has
  // not yet reached `isStarted` must be DEFERRED (not dropped) and fired once
  // on the next stopped->started transition — so the just-arrived 1:1 message
  // surfaces promptly on open instead of only on the next ~30s health tick.
  group('141 notif-open deferred startup drain', () {
    test('drainOfflineInbox defers when node not started and fires on '
        'started transition', () async {
      var retrievePendingCount = 0;
      bridge.whenCommand('inbox:retrieve_pending', (_) {
        retrievePendingCount++;
        return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
      });
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

      // Phase 1 — node not started: the opportunistic drain must be
      // DEFERRED (scheduled), neither run nor silently dropped.
      final scheduledEvents = await _captureFlowEvents(() async {
        await service.drainOfflineInbox();
      });
      expect(
        retrievePendingCount,
        0,
        reason: 'no inbox retrieve may be issued while the node is not started',
      );
      expect(
        scheduledEvents.where(
          (e) => e['event'] == 'P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN',
        ),
        isEmpty,
        reason: 'the drain must not begin while the node is not started',
      );
      expect(
        scheduledEvents.where(
          (e) => e['event'] == 'P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED',
        ),
        isNotEmpty,
        reason:
            'an opportunistic drain requested before the node starts '
            'must be deferred (scheduled), not dropped',
      );

      // Phase 2 — drive the stopped->started transition. The deferred drain
      // must fire exactly once, AFTER the transition (never while stopped).
      final firedEvents = await _captureFlowEvents(() async {
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await _waitForCondition(
          () => retrievePendingCount >= 1,
          reason:
              'the deferred drain should issue an inbox retrieve once '
              'the node reaches started',
        );
      });
      final fired = firedEvents
          .where((e) => e['event'] == 'P2P_SERVICE_PENDING_STARTUP_DRAIN_FIRED')
          .toList();
      expect(
        fired,
        hasLength(1),
        reason:
            'the deferred drain fires exactly once on the '
            'stopped->started transition',
      );
      expect(
        retrievePendingCount,
        greaterThanOrEqualTo(1),
        reason: 'the inbox retrieve is issued only after the node started',
      );
    });

    test('drainOfflineInbox runs immediately when already started '
        '(no deferral, single fire)', () async {
      var retrievePendingCount = 0;
      bridge.whenCommand('inbox:retrieve_pending', (_) {
        retrievePendingCount++;
        return jsonEncode({'ok': true, 'messages': [], 'hasMore': false});
      });
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
        'node:status',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'self-peer',
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': [],
          'connections': [],
        }),
      );
      bridge.whenCommand('node:stop', (_) => jsonEncode({'ok': true}));

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
      // Ignore any startup-driven retrieves; measure only the explicit drain.
      retrievePendingCount = 0;

      final events = await _captureFlowEvents(() async {
        await service.drainOfflineInbox();
      });
      expect(
        retrievePendingCount,
        1,
        reason: 'the started-path drain runs immediately and exactly once',
      );
      expect(
        events.where(
          (e) => e['event'] == 'P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN',
        ),
        isNotEmpty,
        reason: 'the started-path drain begins immediately',
      );
      expect(
        events.where(
          (e) => e['event'] == 'P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED',
        ),
        isEmpty,
        reason: 'no deferral is scheduled when the node is already started',
      );

      // The started-path drain must NOT arm the deferral latch. Prove it with
      // a REAL stop->start cycle (the only thing that drives a
      // stopped->started edge): a phantom latch wrongly set on the started
      // path would fire here. (A weaker check via performImmediateHealthCheck
      // would not — it never crosses the !started->started edge the fire hook
      // guards on, so it cannot catch an over-latch regression.)
      final cycleEvents = await _captureFlowEvents(() async {
        await service.stopNode();
        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(
        cycleEvents.where(
          (e) => e['event'] == 'P2P_SERVICE_PENDING_STARTUP_DRAIN_FIRED',
        ),
        isEmpty,
        reason:
            'the started-path drain must not arm the deferral latch — a '
            'later stop->start cycle must not fire a phantom deferred drain',
      );
    });
  });

  // 147: bounded-concurrent decrypt fan-out ahead of the serial commit loop.
  // The relay-inbox drain replays staged entries serially; the expensive,
  // independent part of each iteration is the per-message decrypt. The fix adds
  // an injected `predecryptInboxChatEntry` fn and a bounded pre-decrypt pass in
  // `_replayStagedInboxEntries` that overlaps N decrypts (≤ the cap) before the
  // unchanged serial commit loop. Commit/persist stays serial-in-order; only
  // the decrypt fans out. These tests inject a fake decrypt fn (latches, never
  // wall-clock) and a fake replay callback that records commit order.
  group('147 inbox replay decrypt fan-out', () {
    String envIdOf(ChatMessage message) {
      final json = jsonDecode(message.content) as Map<String, dynamic>;
      return (json['payload'] as Map<String, dynamic>)['id'] as String;
    }

    Future<void> startNode(P2PServiceImpl s) async {
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'self-peer',
          'isStarted': true,
          'listenAddresses': [],
        }),
      );
      await s.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
    }

    void stagePending(List<String> ids) {
      bridge.whenCommand(
        'inbox:retrieve_pending',
        (_) => jsonEncode({
          'ok': true,
          'messages': [
            for (final id in ids)
              _pendingInboxRow(
                entryId: 'entry-$id',
                from: 'remote-peer',
                message: _chatEnvelope(
                  id: id,
                  text: 'text-$id',
                  senderPeerId: 'remote-peer',
                ),
              ),
          ],
          'hasMore': false,
        }),
      );
    }

    RecoveredInboxReplayOutcome committed() => (
      disposition: RecoveredInboxChatDisposition.committed,
      reasonCode: 'stored',
      reasonDetail: null,
    );

    test(
      '147 TC-A1: prefetch decrypts chat entries concurrently up to the bound',
      () async {
        service.dispose();
        final n = P2PServiceImpl.maxConcurrentInboxDecrypts;
        var inFlight = 0;
        var maxConcurrent = 0;
        final release = Completer<void>();
        final repo = InMemoryInboxStagingRepository();
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          predecryptInboxChatEntry: (message) async {
            inFlight++;
            if (inFlight > maxConcurrent) maxConcurrent = inFlight;
            // Release only once ALL n are simultaneously at the latch — proving
            // genuine overlap, not interleaving. With the bound ≥ n this is
            // reached; force the bound to 1 and it never is (drain deadlocks).
            if (inFlight >= n && !release.isCompleted) release.complete();
            await release.future;
            inFlight--;
            return 'pt-${envIdOf(message)}';
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async => committed(),
        );
        await startNode(service);
        stagePending([for (var i = 1; i <= n; i++) 'm$i']);

        await service.drainOfflineInbox().timeout(const Duration(seconds: 5));

        expect(maxConcurrent, n, reason: 'all $n decrypts overlapped at once');
        expect(maxConcurrent, greaterThan(1));
      },
    );

    test(
      '147 TC-A5: decrypt fan-out is bounded — in-flight never exceeds the cap '
      'for a large batch',
      () async {
        service.dispose();
        final cap = P2PServiceImpl.maxConcurrentInboxDecrypts;
        const n = 20;
        var inFlight = 0;
        var peak = 0;
        var calls = 0;
        final release = Completer<void>();
        final repo = InMemoryInboxStagingRepository();
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          predecryptInboxChatEntry: (message) async {
            calls++;
            inFlight++;
            if (inFlight > peak) peak = inFlight;
            if (inFlight >= cap && !release.isCompleted) release.complete();
            await release.future;
            inFlight--;
            return 'pt-${envIdOf(message)}';
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async => committed(),
        );
        await startNode(service);
        stagePending([for (var i = 1; i <= n; i++) 'm$i']);

        await service.drainOfflineInbox().timeout(const Duration(seconds: 5));

        expect(peak, lessThanOrEqualTo(cap), reason: 'never exceed the cap');
        expect(peak, greaterThan(1), reason: 'still genuinely concurrent');
        expect(calls, n, reason: 'every chat entry was prefetched');
      },
    );

    test(
      '147 TC-A2: commit/persist stays in arrival order when decrypts finish '
      'out of order',
      () async {
        service.dispose();
        final commitLog = <String>[];
        final completionLog = <String>[];
        final inFlightIds = <String>[];
        final gates = <String, Completer<void>>{
          'm1': Completer<void>(),
          'm2': Completer<void>(),
          'm3': Completer<void>(),
        };
        final repo = InMemoryInboxStagingRepository();
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          predecryptInboxChatEntry: (message) async {
            final id = envIdOf(message);
            inFlightIds.add(id);
            if (inFlightIds.length == 3) {
              // All three are at the latch → release them in REVERSE arrival
              // order so decrypt COMPLETES m3, m2, m1.
              for (final rid in ['m3', 'm2', 'm1']) {
                gates[rid]!.complete();
              }
            }
            await gates[id]!.future;
            completionLog.add(id);
            return 'pt-$id';
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                commitLog.add(envIdOf(message));
                return committed();
              },
        );
        await startNode(service);
        stagePending(['m1', 'm2', 'm3']);

        await service.drainOfflineInbox().timeout(const Duration(seconds: 5));

        expect(completionLog, [
          'm3',
          'm2',
          'm1',
        ], reason: 'decrypts finished out of (reverse) order');
        expect(commitLog, [
          'm1',
          'm2',
          'm3',
        ], reason: 'commit/persist stayed in arrival order despite that');
      },
    );

    test(
      '147 TC-A4: a prefetch decrypt failure falls back to in-handler decrypt; '
      'the entry is never dropped',
      () async {
        service.dispose();
        final received = <String, String?>{};
        final repo = InMemoryInboxStagingRepository();
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          predecryptInboxChatEntry: (message) async {
            final id = envIdOf(message);
            if (id == 'mX') {
              throw Exception('prefetch boom'); // omit from the map
            }
            return 'pt-$id';
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                // The handler receives predecryptedText via the message; a failed
                // prefetch leaves it null → the handler would decrypt itself.
                received[envIdOf(message)] = message.predecryptedText;
                return committed();
              },
        );
        await startNode(service);
        stagePending(['mX', 'mY']);

        await service.drainOfflineInbox().timeout(const Duration(seconds: 5));

        expect(
          received.keys,
          containsAll(<String>['mX', 'mY']),
          reason: 'a prefetch failure must NOT drop the entry',
        );
        expect(
          received['mX'],
          isNull,
          reason: 'omitted entry falls back to in-handler decrypt',
        );
        expect(
          received['mY'],
          'pt-mY',
          reason: 'the prefetched plaintext flows',
        );
      },
    );

    test(
      '147 TC-A7 (PROD-CRITICAL): a same-peer drain completes only because the '
      'decrypts overlap (serial would deadlock on the barrier)',
      () async {
        service.dispose();
        const n = 3;
        var waiting = 0;
        final commitLog = <String>[];
        final barrier = Completer<void>(); // releases once ≥2 wait together
        final repo = InMemoryInboxStagingRepository();
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          predecryptInboxChatEntry: (message) async {
            waiting++;
            if (waiting >= 2 && !barrier.isCompleted) barrier.complete();
            await barrier.future; // a lone serial waiter blocks forever
            return 'pt-${envIdOf(message)}';
          },
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                commitLog.add(envIdOf(message));
                return committed();
              },
        );
        await startNode(service);
        stagePending([for (var i = 1; i <= n; i++) 'm$i']);

        // On serial HEAD only one decrypt is ever in flight → the barrier
        // (target 2) is never reached → this would time out.
        await service.drainOfflineInbox().timeout(const Duration(seconds: 5));

        expect(commitLog, ['m1', 'm2', 'm3'], reason: 'all committed in order');
      },
    );
  });

  group('TC-360-01a linked transport peer qualification', () {
    late _FakeBridge bridge;
    late InMemoryInboxStagingRepository inboxStagingRepository;

    setUp(() {
      bridge = _FakeBridge();
      inboxStagingRepository = InMemoryInboxStagingRepository();
    });

    P2PServiceImpl buildService(
      String? Function() requiredTransportPeerId, {
      String? Function()? logicalAccountPeerId,
      AccountMigrationNetworkGate? gate,
    }) {
      return P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: inboxStagingRepository,
        requiredTransportPeerId: requiredTransportPeerId,
        logicalAccountPeerId: logicalAccountPeerId,
        accountMigrationNetworkGate:
            gate ?? allowAccountMigrationNetworkSideEffects,
      );
    }

    void stubStart({required String peerId}) {
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': peerId,
          'isStarted': true,
          'listenAddresses': <String>[],
          'circuitAddresses': <String>[],
          'connections': <dynamic>[],
          'relayState': 'online',
          'healthyRelayCount': 1,
        }),
      );
      bridge.whenCommand(
        'inbox:retrieve',
        (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
      );
      bridge.whenCommand('node:stop', (_) => jsonEncode({'ok': true}));
    }

    test('TC-360-01a linked-secondary transport identity is distinct stable '
        'and fail-closed', () async {
      // ── Ordinary primary: no required peer, no qualification. ──
      stubStart(peerId: 'primary-peer');
      final primaryService = buildService(() => null);
      addTearDown(primaryService.dispose);
      expect(
        await primaryService.startNode('cHJpdmF0ZWtleXRlc3Q=', 'primary-peer'),
        isTrue,
      );
      expect(bridge.calledCommands, isNot(contains('node:stop')));

      // ── Linked, matching peer: qualification passes; 361 parks the
      // generic warm/discovery owners for the linked role. ──
      bridge = _FakeBridge();
      inboxStagingRepository = InMemoryInboxStagingRepository();
      stubStart(peerId: 'transport-peer');
      final matchingService = buildService(() => 'transport-peer');
      addTearDown(matchingService.dispose);
      expect(
        await matchingService.startNode(
          'cHJpdmF0ZWtleXRlc3Q=',
          'transport-peer',
        ),
        isTrue,
      );
      expect(bridge.calledCommands, isNot(contains('node:stop')));

      // ── Linked, MISMATCHED returned peer: the node is STOPPED and start
      // reports failure, before any Dart warm/inbox/QR work can proceed.
      //
      // Continuing here would put this installation back on the account's
      // shared relay mailbox while its contacts address a device peer nobody
      // is listening on — the exact failure the linked role exists to
      // prevent. ──
      bridge = _FakeBridge();
      inboxStagingRepository = InMemoryInboxStagingRepository();
      stubStart(peerId: 'some-other-peer');
      final mismatchedService = buildService(() => 'transport-peer');
      addTearDown(mismatchedService.dispose);
      expect(
        await mismatchedService.startNode(
          'cHJpdmF0ZWtleXRlc3Q=',
          'transport-peer',
        ),
        isFalse,
      );
      expect(
        bridge.calledCommands,
        contains('node:stop'),
        reason: 'a mismatched node must be stopped, not warmed',
      );
      expect(
        bridge.calledCommands,
        isNot(contains('inbox:retrieve')),
        reason: 'no inbox work may run on an unqualified transport',
      );

      // ── Hot-restart resync path is qualified too: `node:start` reports
      // "already started" and the peer comes from `node:status`. ──
      bridge = _FakeBridge();
      inboxStagingRepository = InMemoryInboxStagingRepository();
      bridge.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': false,
          'errorCode': 'ALREADY_STARTED',
          'errorMessage': 'node already started',
        }),
      );
      bridge.whenCommand(
        'node:status',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'stale-hot-restart-peer',
          'isStarted': true,
          'listenAddresses': <String>[],
          'circuitAddresses': <String>[],
          'connections': <dynamic>[],
          'relayState': 'online',
          'healthyRelayCount': 1,
        }),
      );
      bridge.whenCommand('node:stop', (_) => jsonEncode({'ok': true}));
      final hotRestartService = buildService(() => 'transport-peer');
      addTearDown(hotRestartService.dispose);
      expect(
        await hotRestartService.startNode(
          'cHJpdmF0ZWtleXRlc3Q=',
          'transport-peer',
        ),
        isFalse,
        reason:
            'a node left running by a previous role must not be adopted by '
            'a linked secondary just because it answered node:status',
      );
      expect(bridge.calledCommands, contains('node:status'));
      expect(bridge.calledCommands, contains('node:stop'));
    });

    test(
      'TC-360-01a linked-secondary post-start operations ask account authority '
      'about the account peer while the bridge uses the transport',
      () async {
        // The defect this pins: node start is only the FIRST gated operation.
        // Warm/background, send, inbox store/retrieve/ack, health and recovery
        // also consult the account-migration gate, and most pass no peer at
        // all — falling through to `_currentState.peerId`, which on a linked
        // secondary IS the transport peer. Normalizing only at the start call
        // sites left every one of those asking about an identity that account
        // authority does not cover.
        const accountPeer =
            '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
        const transportPeer =
            '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR';

        stubStart(peerId: transportPeer);
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        final gatePeerIds = <String?>[];
        final gateOperations = <String>[];
        final service = buildService(
          () => transportPeer,
          logicalAccountPeerId: () => accountPeer,
          gate: ({String? peerId, required String operation}) async {
            gatePeerIds.add(peerId);
            gateOperations.add(operation);
            return true;
          },
        );
        addTearDown(service.dispose);

        expect(
          await service.startNode('cHJpdmF0ZWtleXRlc3Q=', transportPeer),
          isTrue,
        );

        // Drive POST-START gated operations that pass no peer of their own.
        await service.retrieveInbox();
        await service.warmBackground();

        expect(
          gateOperations.length,
          greaterThan(2),
          reason: 'post-start operations must actually consult the gate',
        );
        expect(
          gatePeerIds.toSet(),
          <String>{accountPeer},
          reason:
              'EVERY gated operation — not just node start — must ask account '
              'authority about the LOGICAL account peer',
        );
        expect(
          gatePeerIds,
          isNot(contains(transportPeer)),
          reason:
              'account authority must never be asked about the per-device '
              'transport peer it does not cover',
        );

        // ...while the BRIDGE still ran on the transport identity.
        final startPayload = bridge.payloadsFor('node:start').single!;
        expect(startPayload['namespace'], contains(transportPeer));
        expect(service.currentState.peerId, transportPeer);

        // An ordinary primary is unchanged: no logical override, so the gate
        // sees exactly the peer it always saw.
        bridge = _FakeBridge();
        inboxStagingRepository = InMemoryInboxStagingRepository();
        stubStart(peerId: 'primary-peer');
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        final primaryGatePeerIds = <String?>[];
        final primary = buildService(
          () => null,
          gate: ({String? peerId, required String operation}) async {
            primaryGatePeerIds.add(peerId);
            return true;
          },
        );
        addTearDown(primary.dispose);
        expect(
          await primary.startNode('cHJpdmF0ZWtleXRlc3Q=', 'primary-peer'),
          isTrue,
        );
        await primary.retrieveInbox();
        expect(primaryGatePeerIds.toSet(), <String>{'primary-peer'});
      },
    );
  });

  test('TC-361-03b linked runtime starts only direct blob-free event owners — '
      'linked node start parks generic discovery and warm while a primary '
      'still warms', () async {
    void stubStartOn(_FakeBridge target, {required String peerId}) {
      target.whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': peerId,
          'isStarted': true,
          'listenAddresses': <String>[],
          'circuitAddresses': <String>[],
          'connections': <dynamic>[],
          'relayState': 'online',
          'healthyRelayCount': 1,
        }),
      );
      target.whenCommand(
        'inbox:retrieve',
        (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
      );
      target.whenCommand('node:status', (_) => jsonEncode({'ok': true}));
    }

    // ── Linked role: the transport qualifier is published, so node start
    // must stop at qualification — no warm body, no generic discovery. ──
    final linkedBridge = _FakeBridge();
    stubStartOn(linkedBridge, peerId: 'transport-peer');
    final linked = P2PServiceImpl(
      bridge: linkedBridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
      requiredTransportPeerId: () => 'transport-peer',
      accountMigrationNetworkGate: allowAccountMigrationNetworkSideEffects,
    );
    addTearDown(linked.dispose);
    final linkedEvents = await _captureFlowEvents(() async {
      expect(
        await linked.startNode('cHJpdmF0ZWtleXRlc3Q=', 'transport-peer'),
        isTrue,
      );
      // Give any wrongly-fired unawaited warm/discovery body time to run.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final linkedEventNames = linkedEvents
        .map((event) => event['event'])
        .toList(growable: false);
    expect(
      linkedEventNames,
      contains('P2P_SERVICE_LINKED_ROLE_GENERIC_START_SKIPPED'),
      reason: 'the linked role must take the restricted-start branch',
    );
    expect(
      linkedEventNames,
      isNot(contains('P2P_SERVICE_WARM_BACKGROUND_BEGIN')),
      reason: 'the generic warm body must stay parked for the linked role',
    );
    expect(
      linkedBridge.calledCommands,
      isNot(contains('inbox:retrieve')),
      reason:
          'no broad inbox work may start from node start on the linked '
          'role; the restricted runtime owns the exact replay explicitly',
    );

    // ── Ordinary primary: byte-identical incumbent behavior — the warm
    // body still fires from node start. ──
    final primaryBridge = _FakeBridge();
    stubStartOn(primaryBridge, peerId: 'primary-peer');
    final primary = P2PServiceImpl(
      bridge: primaryBridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
      accountMigrationNetworkGate: allowAccountMigrationNetworkSideEffects,
    );
    addTearDown(primary.dispose);
    final primaryEvents = await _captureFlowEvents(() async {
      expect(
        await primary.startNode('cHJpdmF0ZWtleXRlc3Q=', 'primary-peer'),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(
      primaryEvents.map((event) => event['event']),
      contains('P2P_SERVICE_WARM_BACKGROUND_BEGIN'),
      reason: 'a primary keeps the incumbent warm start',
    );
  });
  group('TC-375-07b coordinator-owned re-registration', () {
    test(
      'TC-375-07b persisted token and every relay health retry use the one coordinator',
      () async {
        // Persisted-token restore: a fresh process with a stored token gains
        // trigger eligibility through the constructor restore, and the
        // trigger itself is handed to the installed coordinator owner.
        final store = _FakePushTokenStore(
          stored: (token: 'persisted-token', platform: 'android'),
        );
        final restoreBridge = _FakeBridge();
        restoreBridge.whenCommand(
          'inbox:ack',
          (_) => jsonEncode({'ok': true, 'acked': 1}),
        );
        restoreBridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        restoreBridge.whenCommand(
          'node:start',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'self-peer',
            'isStarted': true,
            'listenAddresses': <String>[],
            'circuitAddresses': <String>[],
            'connections': <dynamic>[],
            'relayState': 'degraded',
            'healthyRelayCount': 0,
          }),
        );
        restoreBridge.whenCommand(
          'node:status',
          (_) => jsonEncode({
            'ok': true,
            'peerId': 'self-peer',
            'isStarted': true,
            'listenAddresses': <String>[],
            'circuitAddresses': <String>[],
            'connections': <dynamic>[],
            'relayState': 'degraded',
            'healthyRelayCount': 0,
          }),
        );
        final restoreService = P2PServiceImpl(
          bridge: restoreBridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          pushTokenStore: store,
        );
        addTearDown(restoreService.dispose);
        final retryTriggers = <String>[];
        restoreService.installPushRegistrationRetryNow(() async {
          retryTriggers.add('retry');
        });
        await restoreService.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
        for (var i = 0; i < 100 && store.reads == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(store.reads, greaterThanOrEqualTo(1));

        // relay:state push transition (unhealthy -> healthy): one trigger.
        restoreBridge.onRelayStateChanged?.call({
          'relayState': 'online',
          'healthyRelayCount': 1,
          'watchdogRestartCount': 0,
        });
        for (var i = 0; i < 100 && retryTriggers.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(
          retryTriggers,
          hasLength(1),
          reason:
              'the restored persisted token makes the relay-state '
              'transition hand exactly one trigger to the coordinator',
        );
        expect(
          restoreBridge.calledCommands.where(
            (cmd) => cmd == 'inbox:register_token',
          ),
          isEmpty,
          reason: 'no raw bridge registration path remains in the service',
        );

        // Legacy addresses transition (relayState absent): the same one
        // coordinator owns the trigger.
        final addressesBridge = _FakeBridge();
        addressesBridge.whenCommand(
          'inbox:ack',
          (_) => jsonEncode({'ok': true, 'acked': 1}),
        );
        addressesBridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        addressesBridge.whenCommand(
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
        addressesBridge.whenCommand('inbox:register_token', (_) {
          return jsonEncode({'ok': true, 'status': 'registered'});
        });
        final addressesService = P2PServiceImpl(
          bridge: addressesBridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
        );
        addTearDown(addressesService.dispose);
        var addressesTriggers = 0;
        addressesService.installPushRegistrationRetryNow(() async {
          addressesTriggers++;
        });
        await addressesService.startNodeCore(
          'cHJpdmF0ZWtleXRlc3Q=',
          'self-peer',
        );
        expect(
          await addressesService.registerPushToken('token-a', 'android'),
          isTrue,
          reason: 'fixture: seed trigger eligibility via a normal frame',
        );
        addressesBridge.onAddressesUpdated?.call(
          const <String>[],
          const <String>['/p2p-circuit/relay1'],
        );
        for (var i = 0; i < 100 && addressesTriggers == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(addressesTriggers, 1);

        // Health-check recovery path: a degraded relay recovered by
        // performImmediateHealthCheck hands its re-registration to the same
        // coordinator owner instead of any raw bridge call.
        var stickyRelayState = 'online';
        final recoveryBridge = _FakeBridge();
        recoveryBridge.whenCommand(
          'inbox:ack',
          (_) => jsonEncode({'ok': true, 'acked': 1}),
        );
        recoveryBridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );
        String recoveryStatus() => jsonEncode({
          'ok': true,
          'peerId': 'self-peer',
          'isStarted': true,
          'listenAddresses': <String>[],
          'circuitAddresses': <String>[
            if (stickyRelayState == 'online') '/p2p-circuit/relay1',
          ],
          'connections': <dynamic>[],
          'relayState': stickyRelayState,
          'healthyRelayCount': stickyRelayState == 'online' ? 1 : 0,
          'watchdogRestartCount': 0,
        });
        recoveryBridge.whenCommand('node:start', (_) => recoveryStatus());
        recoveryBridge.whenCommand('node:status', (_) => recoveryStatus());
        recoveryBridge.whenCommand(
          'relay:reconnect',
          (_) => jsonEncode({'ok': false, 'errorCode': 'RELAY_ERROR'}),
        );
        recoveryBridge.whenCommand('inbox:register_token', (_) {
          return jsonEncode({'ok': true, 'status': 'registered'});
        });
        final recoveryService = P2PServiceImpl(
          bridge: recoveryBridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
        );
        addTearDown(recoveryService.dispose);
        var recoveryTriggers = 0;
        recoveryService.installPushRegistrationRetryNow(() async {
          recoveryTriggers++;
        });
        await recoveryService.startNodeCore(
          'cHJpdmF0ZWtleXRlc3Q=',
          'self-peer',
        );
        expect(
          await recoveryService.registerPushToken('token-r', 'android'),
          isTrue,
        );
        stickyRelayState = 'degraded';
        recoveryBridge.onRelayStateChanged?.call({
          'relayState': 'degraded',
          'healthyRelayCount': 0,
          'watchdogRestartCount': 0,
          'reason': 'relay_disconnected',
        });
        await recoveryService.performImmediateHealthCheck();
        expect(recoveryTriggers, 0, reason: 'degradation is not a trigger');
        // The next recovery attempt succeeds: the reconnect itself restores
        // the healthy relay, and the post-recovery status confirms it.
        recoveryBridge.whenCommand('relay:reconnect', (_) {
          stickyRelayState = 'online';
          return jsonEncode({'ok': true});
        });
        await recoveryService.performImmediateHealthCheck();
        for (var i = 0; i < 100 && recoveryTriggers == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(
          recoveryTriggers,
          greaterThanOrEqualTo(1),
          reason:
              'the health-check recovery path routes its re-registration '
              'through the one coordinator owner',
        );
        final rawFramesAfterSeed = recoveryBridge.calledCommands
            .where((cmd) => cmd == 'inbox:register_token')
            .length;
        expect(
          rawFramesAfterSeed,
          1,
          reason:
              'only the seeded fixture frame exists; recovery itself '
              'sent nothing raw',
        );
      },
    );
  });
}

final class _FakePushTokenStore implements PushTokenStore {
  _FakePushTokenStore({required this.stored});

  final ({String token, String platform})? stored;
  int reads = 0;

  @override
  Future<({String token, String platform})?> readToken() async {
    reads++;
    return stored;
  }

  @override
  Future<void> writeToken(String token, String platform) async {}

  @override
  Future<void> clearToken() async {}
}
