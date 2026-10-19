import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/debug/keepalive_drop_e2e_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_keepalive_drop_campaign.dart';
import '../../integration_test/support/sims_runtime_protocol.dart';
import '../../tool/sims/device_criteria.dart';

void main() {
  test('receiver stop needs the successful stop_node acknowledgment', () {
    expect(
      keepaliveReceiverStopAcknowledged({
        'status': 'complete',
        'success': true,
        'nodeAction': {'action': 'stop_node', 'stopped': true},
      }),
      isTrue,
    );
  });
  test(
    'incomplete or wrong receiver stop evidence cannot prepare the send',
    () {
      for (final result in <Map<String, Object?>>[
        {},
        {'status': 'complete', 'success': true},
        {
          'status': 'complete',
          'success': true,
          'nodeAction': {'action': 'stop_node', 'stopped': false},
        },
        {
          'status': 'complete',
          'success': true,
          'nodeAction': {'action': 'none', 'stopped': true},
        },
        {
          'status': 'failed',
          'success': false,
          'nodeAction': {'action': 'stop_node', 'stopped': true},
        },
        {
          'status': 'complete',
          'success': true,
          'nodeAction': {'action': 'stop_node', 'stopped': 'true'},
        },
      ]) {
        expect(keepaliveReceiverStopAcknowledged(result), isFalse);
      }
    },
  );
  const terminal = 'P2P_SERVICE_DIAL_PEER_SUCCESS';
  test('early drop callback survives a truncated warm log tail', () {
    final observer = KeepaliveTargetConnectionObserver('target-peer');
    observer.observe('[CONN] peer:connected → target-peer'); // Before stop.
    observer.observe('[CONN] peer:disconnected → target-peer'); // Drop poll.
    observer.observe('[FLOW] KEEPALIVE_PEER_DROP'); // Later warm tail.
    expect(observer.connected, isFalse);
    expect(observer.terminalIfDisconnected(null), isNull);
    expect(observer.terminalIfDisconnected(terminal), terminal);
    expect(observer.observedCallbacks, ['connected', 'disconnected']);
  });
  test('a later reconnect overrides the retained disconnect', () {
    final observer = KeepaliveTargetConnectionObserver('target-peer');
    observer.observe('[CONN] peer:disconnected → target-peer');
    expect(observer.terminalIfDisconnected(terminal), terminal);
    observer.observe('[CONN] peer:connected → target-peer (connected)');
    observer.observe('[FLOW] cached dial success');
    expect(observer.connected, isTrue);
    expect(observer.terminalIfDisconnected(terminal), isNull);
  });
  test('wrong-peer callbacks and cached success leave unknown isolated', () {
    final observer = KeepaliveTargetConnectionObserver('target-peer');
    observer.observe('[FLOW] $terminal');
    observer.observe(
      '[CONN] peer:disconnected → target-peer-other\n'
      '[CONN] peer:disconnected → target',
    );
    expect(observer.connected, isNull);
    expect(observer.terminalIfDisconnected(terminal), isNull);
    expect(observer.observedCallbacks, isEmpty);
    observer.observe('[CONN] peer:connected → target-peer');
    observer.observe('[CONN] peer:disconnected → other-peer');
    expect(observer.connected, isTrue);
    expect(observer.terminalIfDisconnected(terminal), isNull);
  });
  test('failure log is byte bounded, private and absent from metadata', () {
    final directory = Directory.systemTemp.createTempSync('keepalive-private-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/failure.log');
    final log = '${'é' * keepalivePrivateLogLimitBytes}\nprivate-raw-tail';
    final metadata = writeKeepalivePrivateLogWindow(file, log);
    expect(metadata, {
      'captured': true,
      'bytes': keepalivePrivateLogLimitBytes,
      'limitBytes': keepalivePrivateLogLimitBytes,
      'truncated': true,
    });
    expect(file.lengthSync(), keepalivePrivateLogLimitBytes);
    expect(file.statSync().mode & 0x1ff, 0x180); // 0600 before raw writes.
    expect(
      utf8.decode(file.readAsBytesSync(), allowMalformed: true),
      endsWith('private-raw-tail'),
    );
    expect(jsonEncode(metadata), isNot(contains('private-raw-tail')));
    // A reused path fails closed without replacing retained private evidence.
    expect(writeKeepalivePrivateLogWindow(file, 'replacement'), {
      'captured': false,
    });
    expect(
      utf8.decode(file.readAsBytesSync(), allowMalformed: true),
      endsWith('private-raw-tail'),
    );
  });
  test(
    'transport diagnostics are bounded and never export target or raw details',
    () {
      const target = 'private-target-peer-material';
      final lines = <String>[
        for (var i = 0; i < 100; i++) ...[
          '[CONN] peer:${i.isEven ? 'connected' : 'disconnected'} → $target',
          '[FLOW] ${jsonEncode({
            'event': 'P2P_SERVICE_DIAL_PEER_SUCCESS',
            'ts': '2026-10-18T14:32:00Z',
            'details': {'peerId': target, 'secret': 'never-export'},
          })}',
        ],
      ];
      final value = keepaliveTransportDiagnostics(lines.join('\n'), target);
      expect(value['callbacks'], hasLength(8));
      expect(value['connected'], isFalse);
      expect(value['transportEvents'], hasLength(8));
      for (final event in (value['transportEvents'] as List).cast<Map>()) {
        expect(event, {
          'event': 'P2P_SERVICE_DIAL_PEER_SUCCESS',
          'peerMatch': 'exact',
          'observedAt': '2026-10-18T14:32:00.000Z',
        });
      }
      expect(jsonEncode(value), isNot(contains(target)));
      expect(jsonEncode(value), isNot(contains('never-export')));
    },
  );
  test(
    'diagnostics correlate only target callbacks and closed transport events',
    () {
      const target = 'target-peer-private';
      final prefix = target.substring(0, 10);
      String event(String name, String peer) =>
          '[FLOW] ${jsonEncode({
            'event': name,
            'details': {'peerId': peer},
          })}';
      final log = [
        '[CONN] peer:connected → $target (connected)',
        '[CONN] peer:disconnected → $target-other',
        event('P2P_SERVICE_WARM_PEER_DIAL', prefix),
        event('P2P_SERVICE_DIAL_PEER_SUCCESS', 'unrelated'),
        event('private-event', target),
        '[FLOW] truncated',
      ].join('\n');
      final value = keepaliveTransportDiagnostics(log, target);
      expect(value['callbacks'], ['connected']);
      expect(value['connected'], isTrue);
      expect(value['transportEvents'], [
        {'event': 'P2P_SERVICE_WARM_PEER_DIAL', 'peerMatch': 'prefix'},
      ]);
      expect(jsonEncode(value), isNot(contains(prefix)));
      expect(keepaliveTransportDiagnostics(log, ''), {
        'callbacks': [],
        'connected': null,
        'transportEvents': [],
      });
      expect(
        keepaliveTargetConnected(
          event('P2P_SERVICE_DIAL_PEER_SUCCESS', target),
          target,
        ),
        isNull,
      );
    },
  );
  test('connection readiness follows the latest exact target callback', () {
    const disconnected = '[CONN] peer:disconnected → target-peer';
    const connected = '[CONN] peer:connected → target-peer (connected)';
    expect(keepaliveTargetConnected('', 'target-peer'), isNull);
    expect(keepaliveTargetConnected(disconnected, ''), isNull);
    expect(keepaliveTargetConnected(connected, 'target-peer'), isTrue);
    expect(keepaliveTargetConnected(disconnected, 'target-peer'), isFalse);
    expect(
      keepaliveTargetConnected('$connected\n$disconnected', 'target-peer'),
      isFalse,
    );
    expect(
      keepaliveTargetConnected('$disconnected\n$connected', 'target-peer'),
      isTrue,
    );
    expect(
      keepaliveTargetConnected(
        '$connected\n[CONN] peer:disconnected → target-peer-other\n'
            '[CONN] peer:disconnected → target\n'
            '[CONN] peer:disconnected → other-peer\n'
            '[FLOW] KEEPALIVE_PEER_DROP target-peer',
        'target-peer',
      ),
      isTrue,
    );
    expect(
      keepaliveTargetConnected(
        'flutter: $disconnected\r\n'
            '[CONN] peer:disconnected → target-peer malformed',
        'target-peer',
      ),
      isFalse,
    );
    expect(
      keepaliveTargetConnected(
        '[CONN] peer:disconnected → target-peer malformed',
        'target-peer',
      ),
      isNull,
    );
  });

  const messageId = 'a1b2c3d4-1111-2222-3333-444455556666';
  final invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: keepaliveDropProfileId,
    scenarioId: keepaliveDropScenarioId,
    role: 'sender',
    runId: 'run-keepalive',
    nonce: 'nonce-keepalive',
    values: const <String, Object?>{
      'targetId': 'physical-android',
      'targetKind': 'physical',
      'buildArtifactSha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    },
  );

  test('send and recovery merge into message-correlated passing evidence', () {
    final send = _send(invocation, messageId);
    final recovery = _recovery(invocation, messageId);
    expect(validateKeepaliveCampaignInvocation(invocation), isNull);
    expect(
      validateKeepaliveDroppedSendResult(
        send,
        invocation: invocation,
        targetPeerId: 'peer-b',
      ),
      isNull,
    );
    expect(
      validateKeepaliveRecoveryResult(
        recovery,
        invocation: invocation,
        messageId: messageId,
      ),
      isNull,
    );
    final artifact = assembleKeepaliveDropArtifact(
      sendResult: send,
      recoveryResult: recovery,
      deviceIds: const <String>['physical-android', 'android-emulator'],
    );
    expect(validateKeepaliveDropArtifact(artifact).ok, isTrue);
  });

  test('wrong-message receipt and a dial in the send window fail closed', () {
    final recovery = _recovery(invocation, messageId);
    (recovery['receiptEvent']! as Map<String, Object?>)['messageIdPrefix'] =
        'deadbeef';
    expect(
      validateKeepaliveRecoveryResult(
        recovery,
        invocation: invocation,
        messageId: messageId,
      ),
      contains('another message'),
    );

    final send = _send(invocation, messageId);
    (send['sendWindowEvents']! as List<String>).add(
      'P2P_SERVICE_DIAL_PEER_BEGIN',
    );
    expect(
      validateKeepaliveDroppedSendResult(
        send,
        invocation: invocation,
        targetPeerId: 'peer-b',
      ),
      contains('direct attempt'),
    );
  });
}

Map<String, Object?> _send(
  SimsRuntimeInvocation invocation,
  String messageId,
) => <String, Object?>{
  'schema': keepaliveDroppedSendResultSchema,
  'profileId': invocation.profileId,
  'scenario': invocation.scenarioId,
  'role': invocation.role,
  'runId': invocation.runId,
  'nonce': invocation.nonce,
  'stepId': keepaliveDroppedSendStepId(invocation.runId),
  'status': 'complete',
  'success': true,
  'messageId': messageId,
  'messageIdPrefix': 'a1b2c3d4',
  'text': keepaliveRunMessageText(invocation.runId),
  'transport': 'inbox',
  'messageStatus': 'inboxed',
  'dropLatchedBeforeSend': true,
  'dropLatchedAfterSend': true,
  'connectedBeforeSend': false,
  'localBeforeSend': false,
  'sendWindowEvents': <String>[
    'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
    'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
    'SEND_DIRECT_LEG_SKIPPED_KEEPALIVE_DROP',
  ],
  'messageEvents': <Map<String, Object?>>[
    <String, Object?>{
      'event': 'CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN',
      'eventIndex': 0,
      'messageIdPrefix': 'a1b2c3d4',
    },
    <String, Object?>{
      'event': 'CHAT_MSG_SEND_CUSTODY_CONFIRMED',
      'eventIndex': 1,
      'messageIdPrefix': 'a1b2c3d4',
    },
  ],
  'custodyLatencyMs': 180,
};

Map<String, Object?> _recovery(
  SimsRuntimeInvocation invocation,
  String messageId,
) => <String, Object?>{
  'schema': keepaliveRecoveryResultSchema,
  'profileId': invocation.profileId,
  'scenario': invocation.scenarioId,
  'role': invocation.role,
  'runId': invocation.runId,
  'nonce': invocation.nonce,
  'stepId': keepaliveRecoveryStepId(invocation.runId),
  'status': 'complete',
  'success': true,
  'messageIdPrefix': keepaliveMessageIdPrefix(messageId),
  'dropLatchedAfterRecovery': false,
  'messageStatus': 'delivered',
  'events': <String>[
    'DELIVERY_RECEIPT_APPLIED',
    'P2P_SERVICE_PEER_PING_SUCCESS',
  ],
  'receiptEvent': <String, Object?>{
    'event': 'DELIVERY_RECEIPT_APPLIED',
    'eventIndex': 0,
    'messageIdPrefix': 'a1b2c3d4',
  },
  'postDropPeerPingObserved': true,
};
