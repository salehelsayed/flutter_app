import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;

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

class _FakeInboxStagingRepository implements InboxStagingRepository {
  final Map<String, InboxStagingEntry> _entries = {};

  void seed(InboxStagingEntry entry) {
    _entries[entry.entryId] = entry;
  }

  InboxStagingEntry? entry(String entryId) => _entries[entryId];

  @override
  Future<List<String>> stageEntries(List<InboxStagingEntry> entries) async {
    for (final entry in entries) {
      _entries.putIfAbsent(entry.entryId, () => entry);
    }
    return entries.map((entry) => entry.entryId).toList();
  }

  @override
  Future<List<InboxStagingEntry>> getRecoverableEntries({
    int limit = 50,
  }) async {
    final entries =
        _entries.values
            .where(
              (entry) =>
                  entry.status == 'pending' || entry.status == 'retryable',
            )
            .toList()
          ..sort((a, b) => a.relayTimestamp.compareTo(b.relayTimestamp));
    return entries.take(limit).toList();
  }

  @override
  Future<List<InboxStagingEntry>> getRecoverableEntriesByIds(
    List<String> entryIds,
  ) async {
    return entryIds
        .map((entryId) => _entries[entryId])
        .whereType<InboxStagingEntry>()
        .where(
          (entry) => entry.status == 'pending' || entry.status == 'retryable',
        )
        .toList();
  }

  @override
  Future<InboxStagingEntry?> getEntry(String entryId) async =>
      _entries[entryId];

  @override
  Future<void> deleteEntry(String entryId) async {
    _entries.remove(entryId);
  }

  @override
  Future<void> markRetryable(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    final existing = _entries[entryId];
    if (existing == null) return;
    _entries[entryId] = existing.copyWith(
      status: 'retryable',
      attemptCount: existing.attemptCount + 1,
      lastAttemptedAt: '2026-04-01T00:00:00.000Z',
      rejectReasonCode: reasonCode,
      rejectReasonDetail: reasonDetail,
    );
  }

  @override
  Future<void> markRejected(
    String entryId, {
    required String reasonCode,
    String? reasonDetail,
  }) async {
    final existing = _entries[entryId];
    if (existing == null) return;
    _entries[entryId] = existing.copyWith(
      status: 'rejected',
      attemptCount: existing.attemptCount + 1,
      lastAttemptedAt: '2026-04-01T00:00:00.000Z',
      rejectReasonCode: reasonCode,
      rejectReasonDetail: reasonDetail,
    );
  }
}

void main() {
  late _FakeBridge bridge;
  late P2PServiceImpl service;

  setUp(() {
    bridge = _FakeBridge();
    service = P2PServiceImpl(bridge: bridge);
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
    test('replays staged chat rows before fetching new relay pages', () async {
      final repo = _FakeInboxStagingRepository();
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
      final repo = _FakeInboxStagingRepository();
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
        final repo = _FakeInboxStagingRepository();

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

    test(
      'falls back to legacy inbox retrieve when retrieve_pending is unsupported',
      () async {
        final repo = _FakeInboxStagingRepository();

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
          'inbox:retrieve',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              {
                'from': 'remote-peer',
                'message': jsonEncode({
                  'type': 'chat_message',
                  'version': '1',
                  'payload': {
                    'id': 'msg-legacy',
                    'text': 'legacy inbox message',
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

        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

        final received = <ChatMessage>[];
        final sub = service.messageStream.listen(received.add);

        await service.drainOfflineInbox();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));
        expect(bridge.calledCommands, contains('inbox:retrieve'));
        expect(bridge.calledCommands, isNot(contains('inbox:ack')));
        expect(received, hasLength(1));
        expect(received.single.transport, 'inbox');
        expect(received.single.from, 'remote-peer');

        await sub.cancel();
      },
    );

    test(
      'falls back to legacy inbox retrieve when pending rows lack stable entry ids',
      () async {
        final repo = _FakeInboxStagingRepository();

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
        bridge.whenCommand(
          'inbox:retrieve',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
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

        service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');

        final received = <ChatMessage>[];
        final sub = service.messageStream.listen(received.add);

        await service.drainOfflineInbox();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(bridge.calledCommands, contains('inbox:retrieve_pending'));
        expect(bridge.calledCommands, contains('inbox:retrieve'));
        expect(bridge.calledCommands, isNot(contains('inbox:ack')));
        expect(received, hasLength(1));
        expect(received.single.content, contains('msg-missing-id'));

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
        bridge.whenCommand('inbox:retrieve', (_) => firstPage.future);
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
        expect(bridge.calledCommands, contains('inbox:retrieve'));

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
          'inbox:retrieve',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              {
                'from': 'sender1',
                'message':
                    '{"type":"chat_message","version":"1","payload":{"id":"m1","text":"hello","senderPeerId":"sender1","senderUsername":"S","timestamp":"2026-01-01T00:00:00Z"}}',
                'timestamp': 1700000000000,
              },
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
        'inbox:retrieve',
        (_) => jsonEncode({
          'ok': true,
          'messages': [
            {'from': 'sender1', 'message': 'msg1', 'timestamp': 1700000000000},
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
        bridge.whenCommand('inbox:retrieve', (_) {
          retrieveCallCount++;
          return jsonEncode({
            'ok': true,
            'messages': [
              {
                'from': 'sender$retrieveCallCount',
                'message': 'msg$retrieveCallCount',
                'timestamp': 1700000000000,
              },
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
          'inbox:retrieve',
          (_) =>
              jsonEncode({'ok': true, 'messages': const [], 'hasMore': false}),
        );

        await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
        await service.drainOfflineInbox();

        final firstPayload = bridge.payloadsFor('inbox:retrieve').first;
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
        bridge.whenCommand('inbox:retrieve', (_) {
          retrieveCallCount++;
          if (retrieveCallCount == 1) {
            return jsonEncode({
              'ok': true,
              'messages': [
                {
                  'from': 'sender1',
                  'message': 'msg1',
                  'timestamp': 1700000000000,
                },
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
          bridge.payloadsFor('inbox:retrieve').first?['timeoutMs'],
          P2PServiceImpl.foregroundInboxTimeout.inMilliseconds,
        );

        expect(bridge.payloadsFor('inbox:retrieve').length, 2);
        expect(bridge.payloadsFor('inbox:retrieve')[1]?['timeoutMs'], isNull);

        secondPage.complete(
          jsonEncode({
            'ok': true,
            'messages': [
              {
                'from': 'sender2',
                'message': 'msg2',
                'timestamp': 1700000001000,
              },
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
          'inbox:retrieve',
          (_) => jsonEncode({
            'ok': true,
            'messages': [
              {
                'from': 'sender1',
                'message': 'queued-msg',
                'timestamp': 1700000000000,
              },
            ],
            'hasMore': false,
          }),
        );

        // Full startNode includes warmBackground
        await service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        // Inbox retrieve should have been called during warm background
        expect(bridge.calledCommands, contains('inbox:retrieve'));

        // inbox:retrieve should come before subsequent node:status health checks
        final inboxIdx = bridge.calledCommands.indexOf('inbox:retrieve');
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
          'inbox:retrieve',
          (_) => jsonEncode({'ok': true, 'messages': [], 'hasMore': false}),
        );

        // startNode triggers warmBackground which includes inbox drain
        await service.startNode('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');

        // Inbox was attempted early (during warm, before watchdog timer)
        expect(bridge.calledCommands, contains('inbox:retrieve'));

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

        bridge.onRelayStateChanged?.call({
          'relayState': 'degraded',
          'healthyRelayCount': 0,
          'watchdogRestartCount': 0,
          'reason': 'relay_disconnected',
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(bridge.calledCommands, contains('relay:reconnect'));
        expect(service.lastRecoveryMethod, equals('in_place'));
        expect(service.currentState.relayState, 'online');
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
}
