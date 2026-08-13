// ignore_for_file: overridden_fields

import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

class _FakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = {};
  final calledCommands = <String>[];
  final payloadsByCommand = <String, List<Map<String, dynamic>?>>{};
  bool _initialized = false;

  void whenCommand(
    String command,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[command] = handler;
  }

  List<Map<String, dynamic>?> payloadsFor(String command) =>
      List.unmodifiable(payloadsByCommand[command] ?? const []);

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
    final command = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;
    calledCommands.add(command);
    payloadsByCommand.putIfAbsent(command, () => []).add(payload);
    final handler = _handlers[command];
    if (handler != null) {
      return await handler(payload);
    }
    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $command',
    });
  }

  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String>, List<String>)? onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

Map<String, dynamic> _pendingInboxRow({
  required String entryId,
  required String from,
  String messageId = 'msg-001',
  String text = 'hello',
  Object? timestamp = '2026-04-01T00:00:00.000Z',
}) {
  return {
    'id': entryId,
    'from': from,
    'message': jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': messageId,
        'text': text,
        'senderPeerId': from,
        'senderUsername': 'Alice',
        'timestamp': '2026-04-01T00:00:00.000Z',
      },
    }),
    'timestamp': timestamp,
  };
}

Map<String, dynamic> _pendingProtectedGroupRow({required String entryId}) =>
    <String, dynamic>{
      'id': entryId,
      'from': 'physical-sender',
      'message': jsonEncode(<String, dynamic>{
        'type': 'group_authority_v1',
        'version': '1',
        'id': '15:member_removed10:transition17:physical-linked',
        'senderPeerId': 'physical-sender',
        'recipientPeerId': 'physical-linked',
        'encrypted': <String, dynamic>{
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      }),
      'timestamp': '2026-04-01T00:00:00.000Z',
    };

Future<void> _start(P2PServiceImpl service, _FakeBridge bridge) async {
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
  bridge.calledCommands.clear();
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(milliseconds: 500),
  String reason = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for $reason');
}

RecoveredInboxReplayOutcome _committed() => (
  disposition: RecoveredInboxChatDisposition.committed,
  reasonCode: 'stored',
  reasonDetail: null,
);

String _requireAckOrExpiryCustodyContract(Map<String, dynamic>? payload) {
  expect(payload?['custodyContract'], ackOrExpiryInboxCustodyContract);
  return payload!['custodyContract'] as String;
}

void main() {
  tearDown(() {
    debugSetFlowEventSink(null);
  });

  group('replay-before-ack ordering', () {
    test(
      'TC-363-01b protected self bootstrap commits atomically before exact relay ACK',
      () async {
        expect(
          const InboxStoreOutcome(
            status: InboxStoreStatus.stored,
            storeStatus: 'stored',
          ).ackOrExpiryAccepted,
          isFalse,
          reason:
              'a generic or ambiguous store response cannot retire either '
              'bootstrap owner',
        );
        expect(
          const InboxStoreOutcome(
            status: InboxStoreStatus.stored,
            storeStatus: 'stored',
            custodyContract: ackOrExpiryInboxCustodyContract,
          ).ackOrExpiryAccepted,
          isTrue,
        );
        final bridge = _FakeBridge();
        final repo = InMemoryInboxStagingRepository();
        var ackAttempts = 0;
        var replayAttempts = 0;
        var bootstrapAvailable = false;
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode(<String, dynamic>{
            'ok': true,
            'custodyContract': custodyContract,
            'messages': <Map<String, dynamic>>[
              _pendingProtectedGroupRow(entryId: 'protected-entry'),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          ackAttempts++;
          if (ackAttempts == 1) throw StateError('ack unavailable');
          return jsonEncode(<String, dynamic>{
            'ok': true,
            'acked': 1,
            'custodyContract': custodyContract,
          });
        });
        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredProtectedGroupEnvelope: (message) async {
            replayAttempts++;
            if (!bootstrapAvailable) {
              return (
                disposition:
                    ProtectedGroupReplayDisposition.prerequisiteWaiting,
                reasonCode: 'bootstrap_required',
                reasonDetail: null,
              );
            }
            return (
              disposition: ProtectedGroupReplayDisposition.applied,
              reasonCode: 'applied',
              reasonDetail: null,
            );
          },
        );
        await _start(service, bridge);

        for (var drain = 0; drain < 12; drain++) {
          await service.drainOfflineInbox();
        }
        expect(repo.entry('protected-entry')?.attemptCount, 0);
        expect(repo.entry('protected-entry')?.status, 'retryable');
        expect(ackAttempts, 0);

        bootstrapAvailable = true;
        await service.drainOfflineInbox();
        expect(repo.entry('protected-entry'), isNotNull);
        expect(replayAttempts, 13);
        expect(ackAttempts, 1);

        await service.drainOfflineInbox();
        expect(repo.entry('protected-entry'), isNull);
        expect(
          replayAttempts,
          13,
          reason: 'terminal local evidence is ACKed without reapplying it',
        );
        expect(ackAttempts, 2);
        expect(bridge.payloadsFor('inbox:ack').last?['entryIds'], <String>[
          'protected-entry',
        ]);

        service.dispose();
      },
    );

    test(
      'staged entries replay and reach the render stream even when the inbox ack never completes',
      () async {
        final bridge = _FakeBridge();
        final ack = Completer<void>();
        final replayedEntryIds = <String?>[];
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode({
            'ok': true,
            'custodyContract': custodyContract,
            'messages': [
              _pendingInboxRow(entryId: 'entry-never-ack', from: 'remote-peer'),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) async {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          await ack.future;
          return jsonEncode({
            'ok': true,
            'acked': 1,
            'custodyContract': custodyContract,
          });
        });

        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                replayedEntryIds.add(stagedEntryId);
                return _committed();
              },
        );
        await _start(service, bridge);

        var drainCompleted = false;
        final drain = service.drainOfflineInbox()
          ..then((_) {
            drainCompleted = true;
          });
        await _waitFor(
          () => bridge.calledCommands.contains('inbox:ack'),
          reason: 'ack attempted',
        );
        await _waitFor(
          () => replayedEntryIds.isNotEmpty,
          reason: 'replay before ack completion',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(replayedEntryIds, ['entry-never-ack']);
        expect(ack.isCompleted, isFalse);
        expect(drainCompleted, isFalse);
        expect(bridge.payloadsFor('inbox:ack').single?['entryIds'], [
          'entry-never-ack',
        ]);

        ack.complete();
        await drain;
        service.dispose();
      },
    );

    test(
      'replay commit precedes ack completion and the ack is still sent exactly once',
      () async {
        final bridge = _FakeBridge();
        final ackGate = Completer<void>();
        final flow = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flow.add);
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode({
            'ok': true,
            'custodyContract': custodyContract,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-delayed-ack',
                from: 'remote-peer',
                messageId: 'msg-delayed-ack',
              ),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) async {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          await ackGate.future;
          return jsonEncode({
            'ok': true,
            'acked': 1,
            'custodyContract': custodyContract,
          });
        });

        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async => _committed(),
        );
        await _start(service, bridge);

        final drain = service.drainOfflineInbox();
        await _waitFor(
          () => bridge.calledCommands.contains('inbox:ack'),
          reason: 'ack call entered',
        );
        ackGate.complete();
        await drain;

        final names = flow.map((event) => event['event']).toList();
        final replayIndex = names.indexOf(
          'P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED',
        );
        final ackIndex = names.indexOf(
          'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS',
        );
        expect(replayIndex, isNonNegative);
        expect(ackIndex, isNonNegative);
        expect(replayIndex, lessThan(ackIndex));
        expect(
          bridge.calledCommands.where((c) => c == 'inbox:ack'),
          hasLength(1),
        );
        expect(bridge.payloadsFor('inbox:ack').single?['entryIds'], [
          'entry-delayed-ack',
        ]);

        service.dispose();
      },
    );

    test(
      'ack throw after replay is swallowed and replayed count still contributes to drain success',
      () async {
        final bridge = _FakeBridge();
        final flow = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flow.add);
        var replayCount = 0;
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode({
            'ok': true,
            'custodyContract': custodyContract,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-ack-throws',
                from: 'remote-peer',
              ),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) {
          _requireAckOrExpiryCustodyContract(payload);
          throw StateError('ack down');
        });

        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                replayCount++;
                return _committed();
              },
        );
        await _start(service, bridge);

        await service.drainOfflineInbox();

        expect(replayCount, 1);
        expect(
          flow.map((event) => event['event']),
          contains('P2P_SERVICE_INBOX_ACK_AFTER_STAGE_EXCEPTION'),
        );
        expect(
          flow.map((event) => event['event']),
          contains('P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS'),
        );

        service.dispose();
      },
    );

    test('migration-gated page stays staged-not-replayed-not-acked', () async {
      final bridge = _FakeBridge();
      final repo = InMemoryInboxStagingRepository();
      final flow = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flow.add);
      var replayCount = 0;
      bridge.whenCommand('inbox:retrieve_pending', (payload) {
        final custodyContract = _requireAckOrExpiryCustodyContract(payload);
        return jsonEncode({
          'ok': true,
          'custodyContract': custodyContract,
          'messages': [
            _pendingInboxRow(entryId: 'entry-gated', from: 'remote-peer'),
          ],
          'hasMore': false,
        });
      });
      bridge.whenCommand('inbox:ack', (payload) {
        final custodyContract = _requireAckOrExpiryCustodyContract(payload);
        return jsonEncode({
          'ok': true,
          'acked': 1,
          'custodyContract': custodyContract,
        });
      });

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        accountMigrationNetworkGate: ({peerId, required operation}) async =>
            operation != 'p2p_inbox_ack_after_stage',
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async {
              replayCount++;
              return _committed();
            },
      );
      await _start(service, bridge);

      await service.drainOfflineInbox();

      expect(repo.entry('entry-gated'), isNotNull);
      expect(replayCount, 0);
      expect(bridge.calledCommands, isNot(contains('inbox:ack')));
      expect(
        flow.map((event) => event['event']),
        contains('P2P_SERVICE_INBOX_ACK_SKIPPED_GATED'),
      );

      service.dispose();
    });
  });
}
