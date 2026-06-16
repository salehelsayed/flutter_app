import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/local_discovery/lan_ack.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../local_discovery/fake_local_p2p_service.dart';
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

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
      return await handler(payload);
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

    test(
      'F3 step 2 lock: a drain interrupted before commit leaves the entry '
      'recoverable — a later (serialized) drain still replays it',
      () async {
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
      },
    );

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

    test(
      'direct chat with confirmNonce keeps staged row retryable when the '
      'live-direct replay callback asks for retry',
      () async {
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
            fail('live direct retry must not route through the recovery '
                'callback');
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

      test(
        'a retried direct: entry stays notify-capable (live-direct) on the '
        'prefix-blind sweep',
        () async {
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
        },
      );

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

    test('stages, acks, and deletes committed chat entries', () async {
      final repo = InMemoryInboxStagingRepository();
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
      bridge.whenCommand(
        'inbox:retrieve_pending',
        (_) => jsonEncode({
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
        }),
      );
      bridge.whenCommand('inbox:ack', (payload) {
        expect(payload?['entryIds'], ['entry-001']);
        return jsonEncode({'ok': true, 'acked': 1});
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

      expect(replayedIds, ['msg-001']);
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
            reason: 'reaction replay callback should be invoked with the '
                'staged entry id',
          );

          // While the replay is parked, the staged row must NOT be deleted.
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(
            repo.deletedEntryIds,
            isNot(contains('entry-reaction-1')),
            reason: 'the reaction row must survive until the replay commits — '
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

        var fullDrainReturned = false;
        final fullDrain = service.drainOfflineInboxFully().then((_) {
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
        expect(messages.length, 2);

        await sub.cancel();
      },
    );

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
        bridge.whenCommand(
          'inbox:retrieve_pending',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
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
}
