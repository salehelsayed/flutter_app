import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

void main() {
  late _RecordingBridge bridge;
  late P2PServiceImpl service;

  setUp(() {
    bridge = _RecordingBridge();
    service = P2PServiceImpl(
      bridge: bridge,
      receivedWakeTokenStore: _ReceivedTokenStore('wake-token-from-peer'),
      inboxStagingRepository: InMemoryInboxStagingRepository(),
    );
    bridge.whenCommand(
      'inbox:store',
      (_) => jsonEncode(<String, Object?>{'ok': true, 'storeStatus': 'stored'}),
    );
  });

  tearDown(() {
    service.dispose();
  });

  test('buffers store until ready', () async {
    final pending = service.storeInInboxDetailed(
      'recipient-peer',
      'wake payload',
      timeoutMs: 1000,
    );
    await Future<void>.delayed(Duration.zero);
    expect(bridge.commands, isNot(contains('inbox:store')));

    await Future<void>.delayed(const Duration(milliseconds: 20));
    bridge.whenCommand(
      'node:start',
      (_) => jsonEncode(<String, Object?>{
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': <String>[],
        'circuitAddresses': <String>[],
        'connections': <Object?>[],
      }),
    );
    expect(
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer'),
      isTrue,
    );

    final outcome = await pending;
    expect(outcome.status, InboxStoreStatus.stored);
    expect(
      bridge.commands.where((command) => command == 'inbox:store'),
      hasLength(1),
    );
    final payload = bridge.payloadsFor('inbox:store').single;
    expect(payload?['wakeToken'], 'wake-token-from-peer');
    expect(payload?['timeoutMs'], isA<int>());
    expect(payload?['timeoutMs'] as int, lessThan(1000));
  });

  test(
    'normal tokenless store dispatches without waiting for startup',
    () async {
      service.dispose();
      service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );

      final outcome = await service
          .storeInInboxDetailed(
            'group-peer',
            'ordinary payload',
            timeoutMs: 500,
          )
          .timeout(const Duration(milliseconds: 100));

      expect(outcome.status, InboxStoreStatus.stored);
      expect(
        bridge.commands.where((command) => command == 'inbox:store'),
        hasLength(1),
      );
      expect(
        bridge.payloadsFor('inbox:store').single,
        isNot(contains('wakeToken')),
      );
    },
  );

  test(
    'disposal completes a buffered store as failed without dispatch',
    () async {
      final pending = service.storeInInboxDetailed(
        'recipient-peer',
        'wake payload',
        timeoutMs: 1000,
      );
      await Future<void>.delayed(Duration.zero);

      service.dispose();
      final outcome = await pending.timeout(const Duration(milliseconds: 100));

      expect(outcome.status, InboxStoreStatus.failed);
      expect(bridge.commands, isNot(contains('inbox:store')));
    },
  );
}

final class _RecordingBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = <String, FutureOr<String> Function(Map<String, dynamic>?)>{};
  final List<String> commands = <String>[];
  final Map<String, List<Map<String, dynamic>?>> _payloads =
      <String, List<Map<String, dynamic>?>>{};

  void whenCommand(
    String command,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[command] = handler;
  }

  List<Map<String, dynamic>?> payloadsFor(String command) =>
      List<Map<String, dynamic>?>.unmodifiable(
        _payloads[command] ?? const <Map<String, dynamic>?>[],
      );

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
    final command = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;
    commands.add(command);
    _payloads
        .putIfAbsent(command, () => <Map<String, dynamic>?>[])
        .add(payload);
    final handler = _handlers[command];
    if (handler == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'errorCode': 'UNHANDLED',
      });
    }
    return handler(payload);
  }
}

final class _ReceivedTokenStore implements ReceivedWakeTokenStore {
  _ReceivedTokenStore(this.token);

  final String? token;

  @override
  Future<Map<String, String>?> readTokenFor(String peerId) async =>
      token == null
      ? null
      : <String, String>{'tok': token!, 'ts': '2026-07-27T00:00:00.000Z'};

  @override
  Future<void> writeTokenFor(String peerId, String token, String ts) async {}

  @override
  Future<void> removeTokenFor(String peerId) async {}

  @override
  Future<void> clear() async {}
}
