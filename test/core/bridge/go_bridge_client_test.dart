import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoBridgeClient client;
  MethodCall? lastCall;

  /// Default mock handler: records the call and returns a success JSON string.
  String? defaultHandler(MethodCall call) {
    lastCall = call;
    return jsonEncode({'ok': true});
  }

  setUp(() {
    client = GoBridgeClient();
    lastCall = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.mknoon/go_bridge'),
          (MethodCall call) async => defaultHandler(call),
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.mknoon/go_bridge'),
          null,
        );
    flowEventLoggingEnabled = kDebugMode;
    debugSetFlowEventSink(null);
    debugPrint = debugPrintThrottled;
  });

  // ---------------------------------------------------------------------------
  // Command routing: commands WITHOUT payload
  // ---------------------------------------------------------------------------
  group('command routing - no payload', () {
    final noPayloadCmds = <String, String>{
      'identity.generate': 'generateIdentity',
      'mlkem.keygen': 'mlKemKeygen',
      'blob:keygen': 'blobKeygen',
      'node:stop': 'stopNode',
      'node:status': 'nodeStatus',
      'relay:reconnect': 'relayReconnect',
      'group:acknowledgeRecovery': 'groupAcknowledgeRecovery',
      'group.keygen': 'generateGroupKey',
    };

    for (final entry in noPayloadCmds.entries) {
      test('${entry.key} calls ${entry.value} with no arguments', () async {
        final request = jsonEncode({
          'cmd': entry.key,
          'payload': <String, dynamic>{},
        });

        final response = await client.send(request);
        final decoded = jsonDecode(response) as Map<String, dynamic>;

        expect(decoded['ok'], isTrue);
        expect(lastCall, isNotNull);
        expect(lastCall!.method, equals(entry.value));
        expect(lastCall!.arguments, isNull);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Command routing: commands WITH payload
  // ---------------------------------------------------------------------------
  group('command routing - with payload', () {
    final payloadCmds = <String, String>{
      'identity.restore': 'restoreIdentity',
      'message.encrypt': 'encryptMessage',
      'message.decrypt': 'decryptMessage',
      'payload.sign': 'signPayload',
      'payload.verify': 'verifyPayload',
      'contactrequest.encrypt': 'encryptContactRequest',
      'contactrequest.decrypt': 'decryptContactRequest',
      'node:start': 'startNode',
      'rendezvous:register': 'rendezvousRegister',
      'rendezvous:discover': 'rendezvousDiscover',
      'relay:probe': 'relayProbe',
      'peer:dial': 'dialPeer',
      'peer:disconnect': 'disconnectPeer',
      'message:send': 'sendMessage',
      'message:confirm': 'confirmDirectMessage',
      'inbox:retrieve': 'inboxRetrieve',
      'inbox:retrieve_pending': 'inboxRetrievePending',
      'inbox:ack': 'inboxAck',
      'inbox:store': 'inboxStore',
      'inbox:register_token': 'inboxRegisterToken',
      'media:upload': 'mediaUpload',
      'media:download': 'mediaDownload',
      'media:delete': 'mediaDelete',
      'media:list': 'mediaList',
      'blob:encrypt': 'blobEncrypt',
      'blob:decrypt': 'blobDecrypt',
      'profile:upload': 'profileUpload',
      'profile:download': 'profileDownload',
      'group:create': 'groupCreate',
      'group:join': 'groupJoinTopic',
      'group:leave': 'groupLeaveTopic',
      'group:publish': 'groupPublish',
      'group:publishReaction': 'groupPublishReaction',
      'group:updateConfig': 'groupUpdateConfig',
      'group:generateNextKey': 'groupGenerateNextKey',
      'group:rotateKey': 'groupRotateKey',
      'group:updateKey': 'groupUpdateKey',
      'group:inboxStore': 'groupInboxStore',
      'group:inboxRetrieve': 'groupInboxRetrieve',
      'group:inboxRetrieveCursor': 'groupInboxRetrieveCursor',
      'group:historyRepairRange': 'groupHistoryRepairRange',
      'group.encrypt': 'groupEncryptMessage',
      'group.decrypt': 'groupDecryptMessage',
    };

    for (final entry in payloadCmds.entries) {
      test('${entry.key} calls ${entry.value} with payload JSON', () async {
        final payload = {'foo': 'bar', 'num': 42};
        final request = jsonEncode({'cmd': entry.key, 'payload': payload});

        final response = await client.send(request);
        final decoded = jsonDecode(response) as Map<String, dynamic>;

        expect(decoded['ok'], isTrue);
        expect(lastCall, isNotNull);
        expect(lastCall!.method, equals(entry.value));
        // The payload is passed as a JSON-encoded string.
        expect(lastCall!.arguments, isA<String>());
        final passedPayload =
            jsonDecode(lastCall!.arguments as String) as Map<String, dynamic>;
        expect(passedPayload['foo'], equals('bar'));
        expect(passedPayload['num'], equals(42));
      });
    }

    test('payload command with null payload sends no arguments', () async {
      // identity.restore has hasPayload=true, but if payload is null in the
      // request JSON the bridge should invoke the method without arguments.
      final request = jsonEncode({'cmd': 'identity.restore'});

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isTrue);
      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('restoreIdentity'));
      expect(lastCall!.arguments, isNull);
    });

    test(
      'history repair helper routes typed payload and parses response',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.mknoon/go_bridge'),
              (MethodCall call) async {
                lastCall = call;
                return jsonEncode({
                  'ok': true,
                  'groupId': 'group-1',
                  'gapId': 'gap-1',
                  'sourcePeerId': 'peer-source',
                  'rangeHash': 'range-hash',
                  'headMessageId': 'msg-after',
                  'messages': [
                    {
                      'from': 'peer-sender',
                      'message': '{"text":"hello"}',
                      'timestamp': '2026-05-01T12:00:00.000Z',
                    },
                  ],
                });
              },
            );

        final result = await callGroupHistoryRepairRange(
          client,
          gap: const GroupInboxHistoryGap(
            groupId: 'group-1',
            gapId: 'gap-1',
            missingAfterMessageId: 'msg-before',
            missingBeforeMessageId: 'msg-after',
            expectedRangeHash: 'range-hash',
            expectedHeadMessageId: 'msg-after',
            candidateSourcePeerIds: ['peer-source'],
          ),
          sourcePeerId: 'peer-source',
          limit: 7,
        );

        expect(lastCall!.method, 'groupHistoryRepairRange');
        final payload =
            jsonDecode(lastCall!.arguments as String) as Map<String, dynamic>;
        expect(payload['groupId'], 'group-1');
        expect(payload['gapId'], 'gap-1');
        expect(payload['sourcePeerId'], 'peer-source');
        expect(payload['limit'], 7);
        expect(result.rangeHash, 'range-hash');
        expect(result.messages, hasLength(1));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Error handling
  // ---------------------------------------------------------------------------
  group('error handling', () {
    test('unknown command returns UNKNOWN_COMMAND error', () async {
      final request = jsonEncode({
        'cmd': 'unknown.command',
        'payload': <String, dynamic>{},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('UNKNOWN_COMMAND'));
      expect(decoded['errorMessage'], contains('unknown.command'));
      // The MethodChannel should never have been called.
      expect(lastCall, isNull);
    });

    test('null response from native returns NULL_RESPONSE error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              return null;
            },
          );

      final request = jsonEncode({
        'cmd': 'identity.generate',
        'payload': <String, dynamic>{},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('NULL_RESPONSE'));
      expect(decoded['errorMessage'], equals('Native bridge returned null'));
      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('generateIdentity'));
    });

    test('PlatformException returns PLATFORM_ERROR with message', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              throw PlatformException(
                code: 'GO_ERROR',
                message: 'something went wrong in Go',
              );
            },
          );

      final request = jsonEncode({
        'cmd': 'node:start',
        'payload': {'listenAddr': '/ip4/0.0.0.0/tcp/0'},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('PLATFORM_ERROR'));
      expect(decoded['errorMessage'], equals('something went wrong in Go'));
      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('startNode'));
    });

    test(
      'ER005 PlatformException redacts secrets in response and flow logs',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.mknoon/go_bridge'),
              (MethodCall call) async {
                lastCall = call;
                throw PlatformException(
                  code: 'GO_ERROR',
                  message:
                      'dial failed privateKeyHex=deadbeef '
                      'ciphertext=raw-ciphertext-blob '
                      '/ip4/10.0.0.1/tcp/4001/p2p/12D3KooWRelayPeer',
                );
              },
            );

        final response = await client.send(
          jsonEncode({
            'cmd': 'node:start',
            'payload': {
              'privateKeyHex': 'deadbeef',
              'relayAddresses': [
                '/ip4/10.0.0.1/tcp/4001/p2p/12D3KooWRelayPeer',
              ],
            },
          }),
        );

        final decoded = jsonDecode(response) as Map<String, dynamic>;
        final encodedResponse = jsonEncode(decoded);
        final encodedFlow = jsonEncode(flowEvents);

        expect(decoded['ok'], isFalse);
        expect(decoded['errorCode'], equals('PLATFORM_ERROR'));
        for (final payload in [encodedResponse, encodedFlow]) {
          expect(payload, isNot(contains('deadbeef')));
          expect(payload, isNot(contains('raw-ciphertext-blob')));
          expect(payload, isNot(contains('/ip4/10.0.0.1')));
          expect(payload, contains('[redacted]'));
          expect(payload, contains('[redacted:multiaddr]'));
        }
      },
    );

    test(
      'ER005 ok false bridge responses redact native error messages',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.mknoon/go_bridge'),
              (MethodCall call) async {
                lastCall = call;
                return jsonEncode({
                  'ok': false,
                  'errorCode': 'GROUP_ERROR',
                  'errorMessage':
                      'group decrypt failed secretKey=mlkem-secret '
                      'nonce=nonce-secret /dns/relay.example/tcp/4001/p2p/peer',
                });
              },
            );

        final response = await client.send(
          jsonEncode({
            'cmd': 'group.decrypt',
            'payload': {'ciphertext': 'raw-ciphertext-blob'},
          }),
        );

        final decoded = jsonDecode(response) as Map<String, dynamic>;
        final encodedResponse = jsonEncode(decoded);

        expect(decoded['ok'], isFalse);
        expect(decoded['errorCode'], equals('GROUP_ERROR'));
        expect(encodedResponse, isNot(contains('mlkem-secret')));
        expect(encodedResponse, isNot(contains('nonce-secret')));
        expect(encodedResponse, isNot(contains('/dns/relay.example')));
        expect(encodedResponse, contains('[redacted]'));
        expect(encodedResponse, contains('[redacted:multiaddr]'));
      },
    );

    test('PlatformException with null message uses fallback text', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              throw PlatformException(code: 'GO_ERROR');
            },
          );

      final request = jsonEncode({
        'cmd': 'node:status',
        'payload': <String, dynamic>{},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;

      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('PLATFORM_ERROR'));
      expect(decoded['errorMessage'], equals('Platform channel error'));
    });

    test(
      'MissingPluginException returns MISSING_PLUGIN with rebuild guidance',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.mknoon/go_bridge'),
              (MethodCall call) async {
                lastCall = call;
                throw MissingPluginException('No implementation found');
              },
            );

        final request = jsonEncode({
          'cmd': 'blob:keygen',
          'payload': <String, dynamic>{},
        });

        final response = await client.send(request);
        final decoded = jsonDecode(response) as Map<String, dynamic>;

        expect(decoded['ok'], isFalse);
        expect(decoded['errorCode'], equals('MISSING_PLUGIN'));
        expect(decoded['errorMessage'], contains('blobKeygen'));
        expect(decoded['errorMessage'], contains('Rebuild the app'));
        expect(lastCall, isNotNull);
        expect(lastCall!.method, equals('blobKeygen'));
      },
    );
  });

  group('push event routing', () {
    test('timeout:fired push event is forwarded with the raw event name', () {
      flowEventLoggingEnabled = true;
      final flowEvents = <Map<String, dynamic>>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.startsWith('[FLOW] ')) {
          flowEvents.add(
            jsonDecode(message.substring('[FLOW] '.length))
                as Map<String, dynamic>,
          );
        }
      };

      client.debugHandleEventForTest(
        jsonEncode({
          'event': 'timeout:fired',
          'data': {
            'timeoutName': 'DirectConfirmTimeout',
            'configuredMs': 2000,
            'actualMs': 2013,
          },
        }),
      );

      final timeoutEvents = flowEvents
          .where((event) => event['event'] == 'timeout:fired')
          .toList(growable: false);
      expect(timeoutEvents, hasLength(1));
      expect(
        timeoutEvents.single['details'],
        containsPair('timeoutName', 'DirectConfirmTimeout'),
      );
    });

    test('group publish debug push event keeps the raw flow event name', () {
      flowEventLoggingEnabled = true;
      final flowEvents = <Map<String, dynamic>>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null && message.startsWith('[FLOW] ')) {
          flowEvents.add(
            jsonDecode(message.substring('[FLOW] '.length))
                as Map<String, dynamic>,
          );
        }
      };

      client.debugHandleEventForTest(
        jsonEncode({
          'event': 'group:publish_debug',
          'data': {'encryptMs': 3, 'signMs': 1, 'topicPeers': 2},
        }),
      );

      final rawEvents = flowEvents
          .where((event) => event['event'] == 'group:publish_debug')
          .toList(growable: false);
      final aliasEvents = flowEvents
          .where((event) => event['event'] == 'GROUP_PUBLISH_DEBUG')
          .toList(growable: false);

      expect(rawEvents, hasLength(1));
      expect(aliasEvents, hasLength(1));
      expect(rawEvents.single['details'], containsPair('topicPeers', 2));
    });

    test('relay:state push event invokes relay-state callback', () {
      Map<String, dynamic>? received;
      client.onRelayStateChanged = (data) {
        received = data;
      };

      client.debugHandleEventForTest(
        jsonEncode({
          'event': 'relay:state',
          'data': {
            'relayState': 'online',
            'healthyRelayCount': 1,
            'watchdogRestartCount': 2,
            'needsGroupRecovery': true,
          },
        }),
      );

      expect(received, isNotNull);
      expect(received!['relayState'], equals('online'));
      expect(received!['healthyRelayCount'], equals(1));
      expect(received!['watchdogRestartCount'], equals(2));
      expect(received!['needsGroupRecovery'], isTrue);
    });

    test(
      'media:upload_progress push event forwards to upload stream',
      () async {
        final eventFuture = mediaUploadProgressStream.first.timeout(
          const Duration(seconds: 1),
        );

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'media:upload_progress',
            'data': {
              'id': 'blob-1',
              'sentBytes': 5,
              'totalBytes': 10,
              'toPeerId': 'peer-1',
            },
          }),
        );

        final received = await eventFuture;
        expect(received['id'], 'blob-1');
        expect(received['sentBytes'], 5);
        expect(received['totalBytes'], 10);
        expect(received['toPeerId'], 'peer-1');
      },
    );

    test(
      'group decryption failure push event reaches diagnostics stream without invoking group message callback',
      () async {
        var groupMessageCalls = 0;
        client.onGroupMessageReceived = (_) {
          groupMessageCalls++;
        };

        final eventFuture = groupDiagnosticEventStream.first.timeout(
          const Duration(seconds: 1),
        );

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group:decryption_failed',
            'data': {
              'groupId': 'group-1',
              'senderId': 'peer-2',
              'keyEpoch': 3,
              'localKeyEpoch': 4,
              'error': 'cipher: message authentication failed',
            },
          }),
        );

        final received = await eventFuture;
        expect(received['event'], 'group:decryption_failed');
        expect(received['groupId'], 'group-1');
        expect(received['senderId'], 'peer-2');
        expect(received['keyEpoch'], 3);
        expect(received['localKeyEpoch'], 4);
        expect(received['error'], contains('failed'));
        expect(groupMessageCalls, 0);
      },
    );

    test(
      'ER005 group diagnostic stream redacts sensitive payload fields',
      () async {
        final eventFuture = groupDiagnosticEventStream.first.timeout(
          const Duration(seconds: 1),
        );

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group:decryption_failed',
            'data': {
              'groupHash': 'safe-group-hash',
              'ciphertext': 'raw-ciphertext-blob',
              'nonce': 'nonce-secret',
              'peerId': '12D3KooWLongSensitivePeerIdentifier',
              'errorMessage':
                  'failed secretKey=mlkem-secret '
                  '/ip4/10.0.0.1/tcp/4001/p2p/12D3KooWRelayPeer',
            },
          }),
        );

        final received = await eventFuture;
        final encoded = jsonEncode(received);

        expect(received['event'], 'group:decryption_failed');
        expect(received['groupHash'], 'safe-group-hash');
        expect(encoded, isNot(contains('raw-ciphertext-blob')));
        expect(encoded, isNot(contains('nonce-secret')));
        expect(encoded, isNot(contains('12D3KooWLongSensitivePeerIdentifier')));
        expect(encoded, isNot(contains('mlkem-secret')));
        expect(encoded, isNot(contains('/ip4/10.0.0.1')));
        expect(encoded, contains('[redacted]'));
        expect(encoded, contains('[redacted:multiaddr]'));
      },
    );

    test(
      'group payload parse failure push event reaches diagnostics stream without invoking group message callback',
      () async {
        var groupMessageCalls = 0;
        client.onGroupMessageReceived = (_) {
          groupMessageCalls++;
        };

        final eventFuture = groupDiagnosticEventStream.first.timeout(
          const Duration(seconds: 1),
        );

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group:payload_parse_failed',
            'data': {
              'groupId': 'group-parse',
              'senderId': 'peer-3',
              'envelopeType': 'group_message',
            },
          }),
        );

        final received = await eventFuture;
        expect(received['event'], 'group:payload_parse_failed');
        expect(received['groupId'], 'group-parse');
        expect(received['senderId'], 'peer-3');
        expect(received['envelopeType'], 'group_message');
        expect(groupMessageCalls, 0);
      },
    );

    test(
      'group validation reject push event reaches diagnostics stream without invoking group message callback',
      () async {
        var groupMessageCalls = 0;
        client.onGroupMessageReceived = (_) {
          groupMessageCalls++;
        };

        final eventFuture = groupDiagnosticEventStream.first.timeout(
          const Duration(seconds: 1),
        );

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group:validation_rejected',
            'data': {
              'reason': 'bad_signature_or_epoch',
              'groupHash': '123456789abc',
              'senderHash': 'abcdef123456',
              'transportPeerHash': '456789abcdef',
              'localPeerHash': 'fedcba987654',
              'envelopeType': 'group_message',
              'keyEpoch': 2,
            },
          }),
        );

        final received = await eventFuture;
        expect(received['event'], 'group:validation_rejected');
        expect(received['reason'], 'bad_signature_or_epoch');
        expect(received['groupHash'], '123456789abc');
        expect(received['senderHash'], 'abcdef123456');
        expect(received['transportPeerHash'], '456789abcdef');
        expect(received['localPeerHash'], 'fedcba987654');
        expect(received['envelopeType'], 'group_message');
        expect(received['keyEpoch'], 2);
        expect(received.containsKey('groupId'), isFalse);
        expect(received.containsKey('senderId'), isFalse);
        expect(groupMessageCalls, 0);
      },
    );

    test(
      'group dispatcher overflow push event reaches diagnostics stream and flow logs without invoking group message callback',
      () async {
        var groupMessageCalls = 0;
        client.onGroupMessageReceived = (_) {
          groupMessageCalls++;
        };

        flowEventLoggingEnabled = true;
        final flowLogs = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) {
            flowLogs.add(message);
          }
        };

        final eventFuture = groupDiagnosticEventStream.first.timeout(
          const Duration(seconds: 1),
        );

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group:dispatcher_overflow',
            'data': {
              'state': 'overflow',
              'queueDepth': 1024,
              'statusCount': 1,
              'maxQueueSize': 1024,
              'droppedCount': 7,
              'coalescedCount': 3,
              'deliveredCount': 99,
              'lastEvent': 'group_message:received',
            },
          }),
        );

        final received = await eventFuture;
        expect(received['event'], 'group:dispatcher_overflow');
        expect(received['state'], 'overflow');
        expect(received['queueDepth'], 1024);
        expect(received['maxQueueSize'], 1024);
        expect(received['droppedCount'], 7);
        expect(received['lastEvent'], 'group_message:received');
        expect(
          flowLogs.any(
            (line) =>
                line.startsWith('[FLOW] ') &&
                line.contains('GROUP_DISPATCHER_OVERFLOW'),
          ),
          isTrue,
        );
        expect(groupMessageCalls, 0);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Total command coverage sanity check
  // ---------------------------------------------------------------------------
  test('all 51 commands are covered', () async {
    // Exhaustive list of every command in _cmdMap.
    final allCmds = [
      // Identity
      'identity.generate',
      'identity.restore',
      // Crypto
      'mlkem.keygen',
      'blob:keygen',
      'blob:encrypt',
      'blob:decrypt',
      'message.encrypt',
      'message.decrypt',
      'payload.sign',
      'payload.verify',
      'contactrequest.encrypt',
      'contactrequest.decrypt',
      // Node
      'node:start',
      'node:stop',
      'node:status',
      // Rendezvous
      'rendezvous:register',
      'rendezvous:discover',
      // Relay
      'relay:reconnect',
      'relay:probe',
      // Peer
      'peer:dial',
      'peer:disconnect',
      // Messaging
      'message:send',
      'message:confirm',
      // Inbox
      'inbox:store',
      'inbox:retrieve',
      'inbox:retrieve_pending',
      'inbox:ack',
      'inbox:register_token',
      // Media
      'media:upload',
      'media:download',
      'media:delete',
      'media:list',
      // Profile
      'profile:upload',
      'profile:download',
      // Groups
      'group:create',
      'group:join',
      'group:leave',
      'group:publish',
      'group:publishReaction',
      'group:updateConfig',
      'group:generateNextKey',
      'group:rotateKey',
      'group:updateKey',
      'group:inboxStore',
      'group:inboxRetrieve',
      'group:inboxRetrieveCursor',
      'group:historyRepairRange',
      'group:acknowledgeRecovery',
      'group.keygen',
      'group.encrypt',
      'group.decrypt',
    ];

    expect(allCmds, hasLength(51));

    for (final cmd in allCmds) {
      final request = jsonEncode({
        'cmd': cmd,
        'payload': {'key': 'value'},
      });

      final response = await client.send(request);
      final decoded = jsonDecode(response) as Map<String, dynamic>;
      // Every known command should route successfully (not UNKNOWN_COMMAND).
      expect(decoded['ok'], isTrue, reason: '$cmd should be a known command');
    }
  });
}
