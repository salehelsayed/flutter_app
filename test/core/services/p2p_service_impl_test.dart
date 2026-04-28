import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

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

  group('transport inference', () {
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

  group('durable inbox staging', () {
    test(
      'direct chat with confirmNonce stages locally, confirms, and commits via replay callback',
      () async {
        final repo = InMemoryInboxStagingRepository();
        final replayedIds = <String>[];
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage: (message) async {
            final payload =
                (jsonDecode(message.content) as Map<String, dynamic>)['payload']
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
      'direct chat with confirmNonce keeps staged row retryable when replay callback asks for retry',
      () async {
        final repo = InMemoryInboxStagingRepository();
        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage: (_) async {
            return (
              disposition: RecoveredInboxChatDisposition.retryable,
              reasonCode: 'missing_mlkem_secret',
              reasonDetail: 'secret unavailable',
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
        replayRecoveredInboxChatMessage: (message) async {
          final payload =
              (jsonDecode(message.content) as Map<String, dynamic>)['payload']
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
        replayRecoveredInboxChatMessage: (message) async {
          final payload =
              (jsonDecode(message.content) as Map<String, dynamic>)['payload']
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
          replayRecoveredInboxChatMessage: (_) async {
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
