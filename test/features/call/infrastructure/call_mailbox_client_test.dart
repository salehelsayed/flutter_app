import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeBridge implements Bridge {
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final Map<String, Map<String, Object?>> responses =
      <String, Map<String, Object?>>{};
  Future<String>? pendingResponse;

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    requests.add(request);
    final pending = pendingResponse;
    if (pending != null) return pending;
    return jsonEncode(
      responses[request['cmd']] ?? const <String, Object?>{'ok': false},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeBridge bridge;
  late BridgeCallMailboxClient client;

  setUp(() {
    bridge = _FakeBridge();
    client = BridgeCallMailboxClient(bridge: bridge);
  });

  test(
    'idle mailbox polls do not crowd out correlated call diagnostics',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      bridge.responses['call_retrieve_v1'] = <String, Object?>{
        'ok': true,
        'receiptAtMs': 2000,
        'expiresAtMs': 45000,
        'hasMore': false,
        'events': <Object?>[],
      };
      await client.retrieve();
      expect(
        (await diagnostics.eventsForTesting()).where(
          (event) => event['action'] == 'retrieve',
        ),
        isEmpty,
      );
      expect(
        (bridge.requests.single['payload'] as Map).containsKey('diagnostics'),
        isFalse,
      );
      final trace = diagnostics.beginAttempt(role: 'callee')!;
      const handle = '11111111-2222-4333-8444-555555555555';
      diagnostics.bindCall(callHandle: handle, traceId: trace, role: 'callee');
      await client.retrieve(callHandle: handle);
      expect(
        (await diagnostics.eventsForTesting()).where(
          (event) => event['action'] == 'retrieve',
        ),
        everyElement(containsPair('traceId', trace)),
      );
      expect(
        (await diagnostics.eventsForTesting()).where(
          (event) => event['action'] == 'retrieve',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'opt-in correlates store metadata without changing encrypted payload or exporting authority',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final traceId = diagnostics.beginAttempt()!;
      const handle = '11111111-2222-4333-8444-555555555555';
      diagnostics.bindCall(callHandle: handle, traceId: traceId);
      bridge.responses['call_store_v1'] = <String, Object?>{
        'ok': true,
        'storeStatus': 'stored',
        'receiptAtMs': 1000,
        'expiresAtMs': 45000,
        'eventCount': 1,
        'totalBytes': 512,
        'pendingHandles': 1,
      };
      const envelope = '{"ciphertext":"private-encrypted-envelope"}';
      await client.store(
        const CallMailboxStoreRequest(
          recipientDevicePeerId: 'private-recipient',
          callHandle: handle,
          messageId: 'private-message-id',
          envelopeJson: envelope,
          expiresAtMs: 45000,
          wakeHandle: 'private-wake-handle',
        ),
      );
      final payload = bridge.requests.single['payload'] as Map;
      expect(payload['envelope'], envelope);
      expect((payload['diagnostics'] as Map)['traceId'], traceId);
      final events = await diagnostics.eventsForTesting();
      expect(
        events.any(
          (event) =>
              event['action'] == 'store' &&
              event['outcome'] == 'ok' &&
              event['traceId'] == traceId,
        ),
        isTrue,
      );
      final exported = jsonEncode(events);
      for (final forbidden in [
        handle,
        'private-recipient',
        'private-encrypted-envelope',
        'private-wake-handle',
      ]) {
        expect(exported, isNot(contains(forbidden)));
      }
      await diagnostics.setEnabled(false);
      bridge.requests.clear();
      await client.store(
        const CallMailboxStoreRequest(
          recipientDevicePeerId: 'private-recipient',
          callHandle: handle,
          messageId: 'private-message-id',
          envelopeJson: envelope,
          expiresAtMs: 45000,
          wakeHandle: 'private-wake-handle',
        ),
      );
      expect(
        (bridge.requests.single['payload'] as Map).containsKey('diagnostics'),
        isFalse,
      );
    },
  );

  test('stores through the dedicated call_store_v1 action', () async {
    bridge.responses['call_store_v1'] = <String, Object?>{
      'ok': true,
      'storeStatus': 'stored',
      'receiptAtMs': 1_000,
      'expiresAtMs': 45_000,
      'eventCount': 1,
      'totalBytes': 512,
      'pendingHandles': 1,
    };

    final result = await client.store(
      const CallMailboxStoreRequest(
        recipientDevicePeerId: 'recipient-device',
        callHandle: '0123456789abcdef0123456789abcdef',
        messageId: '550e8400-e29b-41d4-a716-446655440000',
        envelopeJson: '{"type":"call_signal","version":"1"}',
        expiresAtMs: 45_000,
        wakeHandle: 'abcdef0123456789abcdef0123456789',
      ),
    );

    expect(result.status, CallMailboxStoreStatus.stored);
    expect(bridge.requests, hasLength(1));
    expect(bridge.requests.single['cmd'], 'call_store_v1');
    final payload = bridge.requests.single['payload'] as Map<String, dynamic>;
    expect(payload['toPeerId'], 'recipient-device');
    expect(payload['callHandle'], '0123456789abcdef0123456789abcdef');
    expect(payload['messageId'], '550e8400-e29b-41d4-a716-446655440000');
    expect(payload, isNot(contains('chatMessage')));
  });

  test('a store receipt carries the wake outcome', () async {
    const request = CallMailboxStoreRequest(
      recipientDevicePeerId: 'recipient-device',
      callHandle: '0123456789abcdef0123456789abcdef',
      messageId: '550e8400-e29b-41d4-a716-446655440000',
      envelopeJson: '{"type":"call_signal","version":"1"}',
      expiresAtMs: 45_000,
      wakeHandle: 'abcdef0123456789abcdef0123456789',
    );
    final base = <String, Object?>{
      'ok': true,
      'storeStatus': 'stored',
      'receiptAtMs': 1_000,
      'expiresAtMs': 45_000,
      'eventCount': 1,
      'totalBytes': 512,
      'pendingHandles': 1,
    };

    bridge.responses['call_store_v1'] = <String, Object?>{
      ...base,
      'wake': 'dispatched',
    };
    expect(
      (await client.store(request)).wake,
      CallMailboxWakeStatus.dispatched,
    );

    bridge.responses['call_store_v1'] = <String, Object?>{
      ...base,
      'wake': 'failed',
    };
    expect((await client.store(request)).wake, CallMailboxWakeStatus.failed);

    bridge.responses['call_store_v1'] = base;
    expect((await client.store(request)).wake, CallMailboxWakeStatus.none);
  });

  test('retrieves typed attributed events through call_retrieve_v1', () async {
    bridge.responses['call_retrieve_v1'] = <String, Object?>{
      'ok': true,
      'receiptAtMs': 2_000,
      'expiresAtMs': 45_000,
      'hasMore': false,
      'events': <Object?>[
        <String, Object?>{
          'callHandle': '0123456789abcdef0123456789abcdef',
          'messageId': '550e8400-e29b-41d4-a716-446655440000',
          'senderPeerId': 'authenticated-sender-device',
          'recipientDevicePeerId': 'recipient-device',
          'envelope': '{"type":"call_signal","version":"1"}',
          'receiptAtMs': 2_000,
          'expiresAtMs': 45_000,
        },
      ],
    };

    final result = await client.retrieve(limit: 16);

    expect(result.events, hasLength(1));
    expect(
      result.events.single.authenticatedSenderDevicePeerId,
      'authenticated-sender-device',
    );
    expect(result.events.single.recipientDevicePeerId, 'recipient-device');
    expect(bridge.requests.single['cmd'], 'call_retrieve_v1');
    expect(bridge.requests.single['payload'], <String, Object?>{'limit': 16});
  });

  test('ack and cancel never use the chat inbox actions', () async {
    bridge.responses['call_ack_v1'] = const <String, Object?>{
      'ok': true,
      'acked': 1,
    };
    bridge.responses['call_cancel_v1'] = const <String, Object?>{
      'ok': true,
      'canceled': true,
    };

    await client.ack(
      callHandle: '0123456789abcdef0123456789abcdef',
      messageIds: const <String>['550e8400-e29b-41d4-a716-446655440000'],
    );
    await client.cancel(
      recipientDevicePeerId: 'recipient-device',
      callHandle: '0123456789abcdef0123456789abcdef',
    );

    expect(bridge.requests.map((request) => request['cmd']), <Object?>[
      'call_ack_v1',
      'call_cancel_v1',
    ]);
    expect(
      bridge.requests.map((request) => request['cmd'].toString()),
      everyElement(isNot(startsWith('inbox:'))),
    );
  });

  // Device 2026-09-05 17:15Z: an invite the relay refused
  // (CALL_RECIPIENT_CAPACITY) was never stored, yet terminal cleanup kept
  // cancelling it. The relay answers CALL_UNAUTHORIZED for a handle it holds
  // nothing of, so the cleanup stayed blocked and every native terminal replay
  // was rejected with terminalCleanupPending. Nothing of ours is left to
  // cancel behind that answer: never stored, already terminal, or expired.
  test(
    'cancel treats an unauthorized relay answer as an absent invite',
    () async {
      final diagnostics = <Map<String, dynamic>>[];
      debugSetFlowEventSink(diagnostics.add);
      addTearDown(() => debugSetFlowEventSink(null));
      bridge.responses['call_cancel_v1'] = const <String, Object?>{
        'ok': false,
        'errorCode': 'CALL_UNAUTHORIZED',
        'errorMessage': 'raw relay detail must not be emitted',
      };

      expect(
        await client.cancel(
          recipientDevicePeerId: 'recipient-device',
          callHandle: '0123456789abcdef0123456789abcdef',
        ),
        isTrue,
      );
      final failures = diagnostics
          .where((event) => event['event'] == 'CALL_MAILBOX_BRIDGE_FAILURE')
          .map((event) => event['details'])
          .toList(growable: false);
      expect(failures, <Object?>[
        <String, Object?>{
          'operation': 'call_cancel_v1',
          'code': 'CALL_UNAUTHORIZED',
        },
      ]);
      expect(jsonEncode(diagnostics), isNot(contains('raw relay detail')));
    },
  );

  test('only cancel tolerates the unauthorized answer', () async {
    for (final code in const <String>[
      'CALL_BACKEND_UNAVAILABLE',
      'CALL_RATE_LIMITED',
      'CALL_INVALID_REQUEST',
      'CALL_CONTROL_UNAVAILABLE',
      'INTERNAL_ERROR',
    ]) {
      bridge.responses['call_cancel_v1'] = <String, Object?>{
        'ok': false,
        'errorCode': code,
      };
      await expectLater(
        client.cancel(
          recipientDevicePeerId: 'recipient-device',
          callHandle: '0123456789abcdef0123456789abcdef',
        ),
        throwsA(
          isA<CallMailboxException>().having(
            (error) => error.code,
            'code',
            CallMailboxErrorCode.bridgeFailure,
          ),
        ),
        reason: code,
      );
    }

    bridge.responses['call_ack_v1'] = const <String, Object?>{
      'ok': false,
      'errorCode': 'CALL_UNAUTHORIZED',
    };
    await expectLater(
      client.ack(
        callHandle: '0123456789abcdef0123456789abcdef',
        messageIds: const <String>['550e8400-e29b-41d4-a716-446655440000'],
      ),
      throwsA(
        isA<CallMailboxException>().having(
          (error) => error.code,
          'code',
          CallMailboxErrorCode.bridgeFailure,
        ),
      ),
    );
  });

  test('rejects oversized envelopes before crossing the bridge', () async {
    await expectLater(
      client.store(
        CallMailboxStoreRequest(
          recipientDevicePeerId: 'recipient-device',
          callHandle: '0123456789abcdef0123456789abcdef',
          messageId: '550e8400-e29b-41d4-a716-446655440000',
          envelopeJson: 'x' * (BridgeCallMailboxClient.maxSignalBytes + 1),
          expiresAtMs: 45_000,
          wakeHandle: 'abcdef0123456789abcdef0123456789',
        ),
      ),
      throwsA(
        isA<CallMailboxException>().having(
          (error) => error.code,
          'code',
          CallMailboxErrorCode.oversized,
        ),
      ),
    );
    expect(bridge.requests, isEmpty);
  });

  test('bounds an unresponsive native mailbox bridge', () async {
    bridge.pendingResponse = Completer<String>().future;
    client = BridgeCallMailboxClient(
      bridge: bridge,
      requestTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      client.retrieve(),
      throwsA(
        isA<CallMailboxException>().having(
          (error) => error.code,
          'code',
          CallMailboxErrorCode.bridgeFailure,
        ),
      ),
    );
  });

  test(
    'reports only allowlisted mailbox operations and bridge error codes',
    () async {
      final diagnostics = <Map<String, dynamic>>[];
      debugSetFlowEventSink(diagnostics.add);
      addTearDown(() => debugSetFlowEventSink(null));
      bridge.responses['call_store_v1'] = const <String, Object?>{
        'ok': false,
        'errorCode': 'INVALID_INPUT',
        'errorMessage':
            'raw-error secret-token /ip4/203.0.113.8/tcp/4001/p2p/relay-peer',
        'recipientDevicePeerId': 'recipient-device-secret',
        'callHandle': '0123456789abcdef0123456789abcdef',
        'messageId': '550e8400-e29b-41d4-a716-446655440000',
        'wakeHandle': 'abcdef0123456789abcdef0123456789',
        'envelope': 'secret-envelope',
        'receiptAtMs': 1_000,
        'expiresAtMs': 45_000,
      };

      await expectLater(
        client.store(
          const CallMailboxStoreRequest(
            recipientDevicePeerId: 'recipient-device-secret',
            callHandle: '0123456789abcdef0123456789abcdef',
            messageId: '550e8400-e29b-41d4-a716-446655440000',
            envelopeJson: 'secret-envelope',
            expiresAtMs: 45_000,
            wakeHandle: 'abcdef0123456789abcdef0123456789',
          ),
        ),
        throwsA(
          isA<CallMailboxException>().having(
            (error) => error.code,
            'code',
            CallMailboxErrorCode.bridgeFailure,
          ),
        ),
      );

      bridge.responses['call_retrieve_v1'] = const <String, Object?>{
        'ok': false,
        'errorCode': 'SECRET_recipient-device-secret',
        'errorMessage': 'raw-error secret-token',
      };
      await expectLater(
        client.retrieve(callHandle: '0123456789abcdef0123456789abcdef'),
        throwsA(isA<CallMailboxException>()),
      );

      final failures = diagnostics
          .where((event) => event['event'] == 'CALL_MAILBOX_BRIDGE_FAILURE')
          .map((event) => event['details'])
          .toList(growable: false);
      expect(failures, <Object?>[
        <String, Object?>{
          'operation': 'call_store_v1',
          'code': 'INVALID_INPUT',
        },
        <String, Object?>{'operation': 'call_retrieve_v1', 'code': 'UNKNOWN'},
      ]);

      final diagnosticText = jsonEncode(failures);
      for (final forbidden in const <String>[
        'recipient-device-secret',
        '0123456789abcdef0123456789abcdef',
        '550e8400-e29b-41d4-a716-446655440000',
        'abcdef0123456789abcdef0123456789',
        'secret-envelope',
        'secret-token',
        'raw-error',
        '/ip4/203.0.113.8/tcp/4001/p2p/relay-peer',
        '1000',
        '45000',
        'SECRET_recipient-device-secret',
      ]) {
        expect(diagnosticText, isNot(contains(forbidden)));
      }
    },
  );

  test('reports only fixed relay call-control error codes', () async {
    const safeRelayCodes = <String>[
      'CALL_BACKEND_UNAVAILABLE',
      'CALL_INVALID_REQUEST',
      'CALL_UNAUTHORIZED',
      'CALL_IDENTITY_CONFLICT',
      'CALL_REPLAY',
      'CALL_EXPIRY_INVALID',
      'CALL_ENVELOPE_TOO_LARGE',
      'CALL_RECIPIENT_CAPACITY',
      'CALL_EVENT_CAPACITY',
      'CALL_BYTE_CAPACITY',
      'CALL_RATE_LIMITED',
      'CALL_STALE_EPOCH',
    ];
    final diagnostics = <Map<String, dynamic>>[];
    debugSetFlowEventSink(diagnostics.add);
    addTearDown(() => debugSetFlowEventSink(null));

    for (final code in safeRelayCodes) {
      bridge.responses[callRetrieveV1BridgeCommand] = <String, Object?>{
        'ok': false,
        'errorCode': code,
        'errorMessage': 'raw relay detail must not be emitted',
      };
      await expectLater(
        client.retrieve(),
        throwsA(
          isA<CallMailboxException>().having(
            (error) => error.code,
            'code',
            CallMailboxErrorCode.bridgeFailure,
          ),
        ),
      );
    }

    final failures = diagnostics
        .where((event) => event['event'] == 'CALL_MAILBOX_BRIDGE_FAILURE')
        .map((event) => event['details'] as Map<String, Object?>)
        .toList(growable: false);
    expect(failures.map((failure) => failure['code']), safeRelayCodes);
    expect(jsonEncode(failures), isNot(contains('raw relay detail')));
  });

  test('diagnostic sink failure preserves the mailbox exception', () async {
    debugSetFlowEventSink((_) => throw StateError('diagnostic sink failed'));
    addTearDown(() => debugSetFlowEventSink(null));
    bridge.responses['call_cancel_v1'] = const <String, Object?>{
      'ok': false,
      'errorCode': 'CALL_CONTROL_UNAVAILABLE',
    };

    await expectLater(
      client.cancel(
        recipientDevicePeerId: 'recipient-device',
        callHandle: '0123456789abcdef0123456789abcdef',
      ),
      throwsA(
        isA<CallMailboxException>().having(
          (error) => error.code,
          'code',
          CallMailboxErrorCode.bridgeFailure,
        ),
      ),
    );
  });
}
