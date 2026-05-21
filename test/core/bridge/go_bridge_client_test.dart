import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/push_diagnostics_logger.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoBridgeClient client;
  MethodCall? lastCall;
  const goBridgeEventChannelName = 'com.mknoon/go_bridge_events';
  const goBridgeEventCodec = StandardMethodCodec();

  /// Default mock handler: records the call and returns a success JSON string.
  String? defaultHandler(MethodCall call) {
    lastCall = call;
    return jsonEncode({'ok': true});
  }

  void installMockGoBridgeEventChannel({List<String>? calls}) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMessageHandler(goBridgeEventChannelName, (message) async {
      final call = goBridgeEventCodec.decodeMethodCall(message!);
      expect(call.method, anyOf('listen', 'cancel'));
      calls?.add(call.method);
      return goBridgeEventCodec.encodeSuccessEnvelope(null);
    });

    addTearDown(() async {
      client.dispose();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMessageHandler(goBridgeEventChannelName, null);
    });
  }

  Future<void> sendMockGoBridgeEvent(String eventJson) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      goBridgeEventChannelName,
      goBridgeEventCodec.encodeSuccessEnvelope(eventJson),
      (_) {},
    );
  }

  Future<void> sendMockGoBridgeEventError(String message) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      goBridgeEventChannelName,
      goBridgeEventCodec.encodeErrorEnvelope(
        code: 'DE019_EVENT_STREAM_ERROR',
        message: message,
      ),
      (_) {},
    );
  }

  Future<void> closeMockGoBridgeEventChannel() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      goBridgeEventChannelName,
      null,
      (_) {},
    );
  }

  Future<void> waitForCondition(
    bool Function() condition, {
    required String description,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for $description');
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
      'BB-007 callGroupJoinWithConfig forwards exact full config payload to groupJoinTopic',
      () async {
        final groupConfig = <String, dynamic>{
          'name': 'BB-007 Exact Invite Group',
          'groupType': 'chat',
          'description': 'Full-config MethodChannel round-trip proof',
          'createdBy': '12D3KooWBB007Admin',
          'createdAt': '2026-05-10T20:00:00.000Z',
          'stateHash': 'bb007-state-hash',
          'members': [
            {
              'peerId': '12D3KooWBB007Admin',
              'username': 'Admin',
              'role': 'admin',
              'publicKey': 'bb007AdminPubKey64',
              'mlKemPublicKey': 'bb007AdminMlKemPub64',
              'devices': [
                {
                  'deviceId': 'admin-phone',
                  'deviceSigningPublicKey': 'bb007AdminDevicePub64',
                  'mlKemPublicKey': 'bb007AdminDeviceMlKem64',
                },
              ],
            },
            {
              'peerId': '12D3KooWBB007Invitee',
              'username': 'Invitee',
              'role': 'writer',
              'publicKey': 'bb007InviteePubKey64',
              'mlKemPublicKey': 'bb007InviteeMlKemPub64',
              'devices': [
                {
                  'deviceId': 'invitee-phone',
                  'deviceSigningPublicKey': 'bb007InviteeDevicePub64',
                  'mlKemPublicKey': 'bb007InviteeDeviceMlKem64',
                },
              ],
            },
          ],
        };

        await callGroupJoinWithConfig(
          client,
          groupId: 'grp-bb007-method-channel',
          groupConfig: groupConfig,
          groupKey: 'bb007FullGroupKey==',
          keyEpoch: 7,
        );

        expect(lastCall, isNotNull);
        expect(lastCall!.method, 'groupJoinTopic');
        expect(lastCall!.arguments, isA<String>());

        final payload =
            jsonDecode(lastCall!.arguments as String) as Map<String, dynamic>;
        expect(payload['groupId'], 'grp-bb007-method-channel');
        expect(payload['groupConfig'], equals(groupConfig));
        expect(payload['groupKey'], 'bb007FullGroupKey==');
        expect(payload['keyEpoch'], 7);
        expect(payload, isNot(contains('topicName')));
      },
    );

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

    test(
      'IR-011 history repair helper normalizes request identity and surfaces invalid input',
      () async {
        final requests = <Map<String, dynamic>>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.mknoon/go_bridge'),
              (MethodCall call) async {
                lastCall = call;
                final payload =
                    jsonDecode(call.arguments as String)
                        as Map<String, dynamic>;
                requests.add(payload);
                final missingField = switch (payload) {
                  {'groupId': ''} => 'groupId',
                  {'gapId': ''} => 'gapId',
                  {'sourcePeerId': ''} => 'sourcePeerId',
                  _ => null,
                };
                if (missingField != null) {
                  return jsonEncode({
                    'ok': false,
                    'errorCode': 'INVALID_INPUT',
                    'errorMessage': 'missing $missingField',
                  });
                }
                return jsonEncode({
                  'ok': true,
                  'groupId': payload['groupId'],
                  'gapId': payload['gapId'],
                  'sourcePeerId': payload['sourcePeerId'],
                  'rangeHash': payload['expectedRangeHash'],
                  'headMessageId': payload['expectedHeadMessageId'],
                  'messages': [
                    {
                      'from': 'peer-source',
                      'message': '{"messageId":"ir011-repaired"}',
                      'timestamp': '2026-05-01T12:00:00.000Z',
                    },
                  ],
                });
              },
            );

        final result = await callGroupHistoryRepairRange(
          client,
          gap: GroupInboxHistoryGap.fromMap({
            'groupId': ' group-1 ',
            'gapId': ' gap-1 ',
            'missingAfterMessageId': ' msg-before ',
            'missingBeforeMessageId': ' msg-after ',
            'expectedRangeHash': ' range-hash ',
            'expectedHeadMessageId': ' msg-after ',
            'candidateSourcePeerIds': [' peer-source '],
          }),
          sourcePeerId: 'peer-source',
          limit: 7,
        );

        expect(lastCall!.method, 'groupHistoryRepairRange');
        expect(requests.last['groupId'], 'group-1');
        expect(requests.last['gapId'], 'gap-1');
        expect(requests.last['sourcePeerId'], 'peer-source');
        expect(requests.last['missingAfterMessageId'], 'msg-before');
        expect(requests.last['missingBeforeMessageId'], 'msg-after');
        expect(requests.last['expectedRangeHash'], 'range-hash');
        expect(requests.last['expectedHeadMessageId'], 'msg-after');
        expect(requests.last['limit'], 7);
        expect(result.groupId, 'group-1');
        expect(result.gapId, 'gap-1');
        expect(result.sourcePeerId, 'peer-source');
        expect(result.rangeHash, 'range-hash');
        expect(result.messages, hasLength(1));

        Future<void> expectInvalidInput({
          required GroupInboxHistoryGap gap,
          required String sourcePeerId,
        }) async {
          await expectLater(
            callGroupHistoryRepairRange(
              client,
              gap: gap,
              sourcePeerId: sourcePeerId,
              limit: 7,
            ),
            throwsA(
              isA<BridgeCommandException>().having(
                (error) => error.errorCode,
                'errorCode',
                'INVALID_INPUT',
              ),
            ),
          );
        }

        await expectInvalidInput(
          gap: const GroupInboxHistoryGap(
            groupId: '',
            gapId: 'gap-1',
            missingAfterMessageId: 'msg-before',
            missingBeforeMessageId: 'msg-after',
            expectedRangeHash: 'range-hash',
            expectedHeadMessageId: 'msg-after',
            candidateSourcePeerIds: ['peer-source'],
          ),
          sourcePeerId: 'peer-source',
        );
        await expectInvalidInput(
          gap: const GroupInboxHistoryGap(
            groupId: 'group-1',
            gapId: '',
            missingAfterMessageId: 'msg-before',
            missingBeforeMessageId: 'msg-after',
            expectedRangeHash: 'range-hash',
            expectedHeadMessageId: 'msg-after',
            candidateSourcePeerIds: ['peer-source'],
          ),
          sourcePeerId: 'peer-source',
        );
        await expectInvalidInput(
          gap: const GroupInboxHistoryGap(
            groupId: 'group-1',
            gapId: 'gap-1',
            missingAfterMessageId: 'msg-before',
            missingBeforeMessageId: 'msg-after',
            expectedRangeHash: 'range-hash',
            expectedHeadMessageId: 'msg-after',
            candidateSourcePeerIds: ['peer-source'],
          ),
          sourcePeerId: '',
        );

        expect(requests.map((payload) => payload['groupId']).toList(), [
          'group-1',
          '',
          'group-1',
          'group-1',
        ]);
        expect(requests.map((payload) => payload['gapId']).toList(), [
          'gap-1',
          'gap-1',
          '',
          'gap-1',
        ]);
        expect(requests.map((payload) => payload['sourcePeerId']).toList(), [
          'peer-source',
          'peer-source',
          'peer-source',
          '',
        ]);
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

    test(
      'SV-013 group bridge failure flow logs redact keys plaintext and invite content',
      () async {
        const groupKeySecret = 'sv013-group-key-secret';
        const secretKeySecret = 'sv013-secret-key-secret';
        const plaintextSecret = 'SV013-PLAINTEXT-MESSAGE';
        const inviteSecret = 'SV013-DECRYPTED-INVITE-CONTENT';
        const ciphertextSecret = 'sv013-ciphertext-secret';
        const nonceSecret = 'sv013-nonce-secret';
        const multiaddrSecret =
            '/ip4/10.99.0.1/tcp/4001/p2p/12D3KooWSV013Relay';
        const sensitiveError =
            'failure groupKey=$groupKeySecret '
            'secretKey=$secretKeySecret '
            'plaintext=$plaintextSecret '
            'decryptedInviteContent=$inviteSecret '
            'ciphertext=$ciphertextSecret '
            'nonce=$nonceSecret '
            '$multiaddrSecret';
        const forbidden = [
          groupKeySecret,
          secretKeySecret,
          plaintextSecret,
          inviteSecret,
          ciphertextSecret,
          nonceSecret,
          multiaddrSecret,
        ];

        flowEventLoggingEnabled = true;
        final flowEvents = <Map<String, dynamic>>[];
        final flowLogs = <String>[];
        debugSetFlowEventSink(flowEvents.add);
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) {
            flowLogs.add(message);
          }
        };

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.mknoon/go_bridge'),
              (MethodCall call) async {
                lastCall = call;
                throw PlatformException(
                  code: 'GROUP_ERROR',
                  message: sensitiveError,
                );
              },
            );

        final cases =
            <({String cmd, String method, Map<String, dynamic> payload})>[
              (
                cmd: 'group:create',
                method: 'groupCreate',
                payload: {
                  'name': 'SV013 Create',
                  'groupType': 'chat',
                  'creatorPeerId': 'peer-alice',
                  'creatorPublicKey': 'alice-public',
                },
              ),
              (
                cmd: 'group:join',
                method: 'groupJoinTopic',
                payload: {
                  'groupId': 'group-sv013-join',
                  'groupConfig': {'members': <Map<String, dynamic>>[]},
                  'groupKey': groupKeySecret,
                  'keyEpoch': 1,
                },
              ),
              (
                cmd: 'group:updateKey',
                method: 'groupUpdateKey',
                payload: {
                  'groupId': 'group-sv013-update-key',
                  'groupKey': groupKeySecret,
                  'keyEpoch': 2,
                },
              ),
              (
                cmd: 'group.decrypt',
                method: 'groupDecryptMessage',
                payload: {
                  'groupKey': groupKeySecret,
                  'ciphertext': ciphertextSecret,
                  'nonce': nonceSecret,
                },
              ),
              (
                cmd: 'group:inboxStore',
                method: 'groupInboxStore',
                payload: {
                  'groupId': 'group-sv013-inbox',
                  'message': 'plaintext=$plaintextSecret',
                  'recipientPeerIds': ['peer-bob'],
                },
              ),
              (
                cmd: 'media:upload',
                method: 'mediaUpload',
                payload: {
                  'id': 'media-sv013',
                  'to': 'group-sv013-media',
                  'path': '/tmp/sv013-media',
                  'plaintextMessage': plaintextSecret,
                },
              ),
            ];

        for (final entry in cases) {
          final response = await client.send(
            jsonEncode({'cmd': entry.cmd, 'payload': entry.payload}),
          );
          final decoded = jsonDecode(response) as Map<String, dynamic>;
          final encodedResponse = jsonEncode(decoded);

          expect(decoded['ok'], isFalse, reason: entry.cmd);
          expect(decoded['errorCode'], 'PLATFORM_ERROR', reason: entry.cmd);
          expect(lastCall!.method, entry.method, reason: entry.cmd);
          for (final fragment in forbidden) {
            expect(
              encodedResponse,
              isNot(contains(fragment)),
              reason: '${entry.cmd} response leaked $fragment',
            );
          }
          expect(encodedResponse, contains('[redacted]'), reason: entry.cmd);
          expect(
            encodedResponse,
            contains('[redacted:multiaddr]'),
            reason: entry.cmd,
          );
        }

        final encodedDiagnostics =
            '${jsonEncode(flowEvents)}\n${flowLogs.join('\n')}';
        for (final fragment in forbidden) {
          expect(
            encodedDiagnostics,
            isNot(contains(fragment)),
            reason: 'flow diagnostics leaked $fragment',
          );
        }
        expect(encodedDiagnostics, contains('[redacted]'));
        expect(encodedDiagnostics, contains('[redacted:multiaddr]'));
        expect(
          flowEvents
              .where((event) => event['event'] == 'GO_BRIDGE_PLATFORM_ERROR')
              .length,
          cases.length,
        );
      },
    );

    test('SV-013 push diagnostics redact group failure details', () {
      const groupKeySecret = 'sv013-push-group-key-secret';
      const secretKeySecret = 'sv013-push-secret-key-secret';
      const plaintextSecret = 'SV013-PUSH-PLAINTEXT-MESSAGE';
      const inviteSecret = 'SV013-PUSH-DECRYPTED-INVITE-CONTENT';
      const ciphertextSecret = 'sv013-push-ciphertext-secret';
      const nonceSecret = 'sv013-push-nonce-secret';
      const multiaddrSecret =
          '/ip4/10.99.0.2/tcp/4001/p2p/12D3KooWSV013PushRelay';
      const forbidden = [
        groupKeySecret,
        secretKeySecret,
        plaintextSecret,
        inviteSecret,
        ciphertextSecret,
        nonceSecret,
        multiaddrSecret,
      ];
      final printed = <String>[];

      runZoned(
        () {
          logPushDiagnostic(
            'sv013_group_failure',
            details: {
              'groupKey': groupKeySecret,
              'secretKey': secretKeySecret,
              'plaintext': plaintextSecret,
              'decryptedInviteContent': inviteSecret,
              'nested': {
                'ciphertext': ciphertextSecret,
                'nonce': nonceSecret,
                'errorMessage':
                    'groupKey=$groupKeySecret '
                    'secretKey=$secretKeySecret '
                    'plaintext=$plaintextSecret '
                    'decryptedInviteContent=$inviteSecret '
                    '$multiaddrSecret',
              },
            },
          );
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            printed.add(line);
          },
        ),
      );

      final encoded = printed.join('\n');
      expect(encoded, contains('[PUSH_DIAG] sv013_group_failure'));
      for (final fragment in forbidden) {
        expect(
          encoded,
          isNot(contains(fragment)),
          reason: 'push diagnostic leaked $fragment',
        );
      }
      expect(encoded, contains('[redacted]'));
      expect(encoded, contains('[redacted:multiaddr]'));
    });

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

  group('BB-014 private group helper command map', () {
    const helperCommandMethods = <String, String>{
      'group:create': 'groupCreate',
      'group:join': 'groupJoinTopic',
      'group:acknowledgeRecovery': 'groupAcknowledgeRecovery',
      'group:leave': 'groupLeaveTopic',
      'group:publish': 'groupPublish',
      'group:publishReaction': 'groupPublishReaction',
      'group:updateConfig': 'groupUpdateConfig',
      'group:generateNextKey': 'groupGenerateNextKey',
      'group:updateKey': 'groupUpdateKey',
      'group:inboxStore': 'groupInboxStore',
      'group:inboxRetrieve': 'groupInboxRetrieve',
      'group:inboxRetrieveCursor': 'groupInboxRetrieveCursor',
      'group:historyRepairRange': 'groupHistoryRepairRange',
      'group.keygen': 'generateGroupKey',
      'group.encrypt': 'groupEncryptMessage',
      'group.decrypt': 'groupDecryptMessage',
    };
    const noPayloadHelperCommands = <String>{
      'group:acknowledgeRecovery',
      'group.keygen',
    };

    test(
      'BB-014 helper private-group commands route through GoBridge map',
      () async {
        for (final entry in helperCommandMethods.entries) {
          lastCall = null;
          final payload = {
            'bb014Command': entry.key,
            'sentinel': 'routes-through-method-channel',
          };
          final response = await client.send(
            jsonEncode({'cmd': entry.key, 'payload': payload}),
          );
          final decoded = jsonDecode(response) as Map<String, dynamic>;

          expect(decoded['ok'], isTrue, reason: entry.key);
          expect(decoded['errorCode'], isNot('UNKNOWN_COMMAND'));
          expect(lastCall, isNotNull, reason: entry.key);
          expect(lastCall!.method, entry.value, reason: entry.key);

          if (noPayloadHelperCommands.contains(entry.key)) {
            expect(lastCall!.arguments, isNull, reason: entry.key);
          } else {
            expect(lastCall!.arguments, isA<String>(), reason: entry.key);
            final passedPayload =
                jsonDecode(lastCall!.arguments as String)
                    as Map<String, dynamic>;
            expect(passedPayload, equals(payload), reason: entry.key);
          }
        }
      },
    );

    test(
      'BB-014 missing native private-group helper commands return MISSING_PLUGIN',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.mknoon/go_bridge'),
              (MethodCall call) async {
                lastCall = call;
                throw MissingPluginException(
                  'No implementation found for ${call.method}',
                );
              },
            );

        for (final entry in helperCommandMethods.entries) {
          lastCall = null;
          final response = await client.send(
            jsonEncode({
              'cmd': entry.key,
              'payload': {'bb014Command': entry.key},
            }),
          );
          final decoded = jsonDecode(response) as Map<String, dynamic>;

          expect(decoded['ok'], isFalse, reason: entry.key);
          expect(decoded['errorCode'], 'MISSING_PLUGIN', reason: entry.key);
          expect(decoded['errorCode'], isNot('UNKNOWN_COMMAND'));
          expect(decoded['errorMessage'], contains(entry.key));
          expect(decoded['errorMessage'], contains(entry.value));
          expect(decoded['errorMessage'], contains('Rebuild the app'));
          expect(lastCall, isNotNull, reason: entry.key);
          expect(lastCall!.method, entry.value, reason: entry.key);
        }
      },
    );
  });

  group('BB-015 private group native response failures', () {
    const privateGroupCommandMethods = <String, String>{
      'group:create': 'groupCreate',
      'group:join': 'groupJoinTopic',
      'group:acknowledgeRecovery': 'groupAcknowledgeRecovery',
      'group:leave': 'groupLeaveTopic',
      'group:publish': 'groupPublish',
      'group:publishReaction': 'groupPublishReaction',
      'group:updateConfig': 'groupUpdateConfig',
      'group:generateNextKey': 'groupGenerateNextKey',
      'group:updateKey': 'groupUpdateKey',
      'group:inboxStore': 'groupInboxStore',
      'group:inboxRetrieve': 'groupInboxRetrieve',
      'group:inboxRetrieveCursor': 'groupInboxRetrieveCursor',
      'group:historyRepairRange': 'groupHistoryRepairRange',
      'group.keygen': 'generateGroupKey',
      'group.encrypt': 'groupEncryptMessage',
      'group.decrypt': 'groupDecryptMessage',
    };

    Future<void> exerciseNativeFailure({
      required String label,
      required String expectedErrorCode,
      required Future<String?> Function(MethodCall call) handler,
    }) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              return handler(call);
            },
          );

      for (final entry in privateGroupCommandMethods.entries) {
        lastCall = null;
        final response = await client.send(
          jsonEncode({
            'cmd': entry.key,
            'payload': {
              'groupId': 'bb015-group',
              'groupKey': 'bb015-request-secret',
            },
          }),
        );
        final decoded = jsonDecode(response) as Map<String, dynamic>;

        expect(decoded['ok'], isFalse, reason: '$label ${entry.key}');
        expect(
          decoded['errorCode'],
          expectedErrorCode,
          reason: '$label ${entry.key}',
        );
        expect(lastCall, isNotNull, reason: '$label ${entry.key}');
        expect(lastCall!.method, entry.value, reason: '$label ${entry.key}');

        final encoded = jsonEncode(decoded);
        expect(encoded, isNot(contains('bb015-request-secret')));
        expect(encoded, isNot(contains('bb015-native-secret')));
        expect(encoded, isNot(contains('/ip4/10.15.0.1')));
        expect(encoded, isNot(contains('not-json')));
      }
    }

    test(
      'BB-015 private group native response failures are structured and sanitized',
      () async {
        await exerciseNativeFailure(
          label: 'null',
          expectedErrorCode: 'NULL_RESPONSE',
          handler: (call) async => null,
        );
        await exerciseNativeFailure(
          label: 'missing-plugin',
          expectedErrorCode: 'MISSING_PLUGIN',
          handler: (call) async {
            throw MissingPluginException(
              'No implementation found for ${call.method}',
            );
          },
        );
        await exerciseNativeFailure(
          label: 'platform',
          expectedErrorCode: 'PLATFORM_ERROR',
          handler: (call) async {
            throw PlatformException(
              code: 'GROUP_ERROR',
              message:
                  'group failed groupKey=bb015-native-secret '
                  '/ip4/10.15.0.1/tcp/4001/p2p/12D3KooWBB015',
            );
          },
        );
        await exerciseNativeFailure(
          label: 'malformed',
          expectedErrorCode: 'MALFORMED_RESPONSE',
          handler: (call) async =>
              'not-json groupKey=bb015-native-secret /ip4/10.15.0.1',
        );
        await exerciseNativeFailure(
          label: 'ok-false',
          expectedErrorCode: 'GROUP_ERROR',
          handler: (call) async => jsonEncode({
            'ok': false,
            'errorCode': 'GROUP_ERROR',
            'errorMessage':
                'native rejected groupKey=bb015-native-secret '
                '/ip4/10.15.0.1/tcp/4001/p2p/12D3KooWBB015',
          }),
        );
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
      'DE-009 group message callback survives reinitialize and receives event once',
      () async {
        installMockGoBridgeEventChannel();
        final received = <Map<String, dynamic>>[];
        client.onGroupMessageReceived = received.add;

        await client.initialize();
        await client.reinitialize();

        expect(client.isInitialized, isTrue);

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group_message:received',
            'data': {
              'groupId': 'group-de009',
              'messageId': 'message-de009',
              'senderId': 'peer-de009',
              'keyEpoch': 1,
              'payload': {'text': 'after reinitialize'},
            },
          }),
        );

        expect(received, hasLength(1));
        expect(received.single['groupId'], 'group-de009');
        expect(received.single['messageId'], 'message-de009');
        expect(received.single['senderId'], 'peer-de009');
        expect(received.single['keyEpoch'], 1);
        expect(
          received.single['payload'],
          containsPair('text', 'after reinitialize'),
        );
      },
    );

    test(
      'DE-018 unknown group event is ignored without blocking known callbacks',
      () {
        final debugLogs = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) {
            debugLogs.add(message);
          }
        };

        final receivedMessages = <Map<String, dynamic>>[];
        final receivedReactions = <Map<String, dynamic>>[];
        client.onGroupMessageReceived = receivedMessages.add;
        client.onGroupReactionReceived = receivedReactions.add;

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group:future_protocol_probe',
            'data': {
              'groupId': 'group-de018',
              'messageId': 'unknown-de018',
              'protocolVersion': 99,
            },
          }),
        );

        expect(receivedMessages, isEmpty);
        expect(receivedReactions, isEmpty);
        expect(
          debugLogs,
          contains(
            '[GoBridgeClient] Unknown push event: group:future_protocol_probe',
          ),
        );

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group_message:received',
            'data': {
              'groupId': 'group-de018',
              'messageId': 'message-de018',
              'senderId': 'peer-de018',
              'keyEpoch': 1,
              'payload': {'text': 'known message after unknown event'},
            },
          }),
        );
        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group_reaction:received',
            'data': {
              'groupId': 'group-de018',
              'messageId': 'message-de018',
              'reactionId': 'reaction-de018',
              'reactorPeerId': 'peer-de018-reactor',
              'emoji': 'ok',
            },
          }),
        );

        expect(receivedMessages, hasLength(1));
        expect(receivedMessages.single['groupId'], 'group-de018');
        expect(receivedMessages.single['messageId'], 'message-de018');
        expect(
          receivedMessages.single['payload'],
          containsPair('text', 'known message after unknown event'),
        );
        expect(receivedReactions, hasLength(1));
        expect(receivedReactions.single['groupId'], 'group-de018');
        expect(receivedReactions.single['messageId'], 'message-de018');
        expect(receivedReactions.single['reactionId'], 'reaction-de018');
      },
    );

    test(
      'DE-019 EventChannel error emits diagnostics, recovers, and preserves group callback',
      () async {
        final eventChannelCalls = <String>[];
        final flowEvents = <Map<String, dynamic>>[];
        installMockGoBridgeEventChannel(calls: eventChannelCalls);
        debugSetFlowEventSink(flowEvents.add);

        final received = Completer<Map<String, dynamic>>();
        client.onGroupMessageReceived = (payload) {
          if (!received.isCompleted) {
            received.complete(payload);
          }
        };

        await client.initialize();
        expect(client.isInitialized, isTrue);
        expect(
          eventChannelCalls.where((call) => call == 'listen'),
          hasLength(1),
        );

        await sendMockGoBridgeEventError('event stream down secretKey=hidden');
        await waitForCondition(
          () => eventChannelCalls.where((call) => call == 'listen').length >= 2,
          description: 'EventChannel error recovery listen',
        );

        expect(client.isInitialized, isTrue);
        expect(eventChannelCalls, contains('cancel'));
        expect(
          flowEvents.map((event) => event['event']),
          containsAllInOrder([
            'GO_BRIDGE_EVENT_STREAM_ERROR',
            'GO_BRIDGE_EVENT_STREAM_RECOVERY_REQUESTED',
            'GO_BRIDGE_REINIT_START',
            'GO_BRIDGE_INIT_SUCCESS',
            'GO_BRIDGE_EVENT_STREAM_RECOVERY_SUCCESS',
          ]),
        );
        final errorEvent = flowEvents.firstWhere(
          (event) => event['event'] == 'GO_BRIDGE_EVENT_STREAM_ERROR',
        );
        expect(jsonEncode(errorEvent), isNot(contains('secretKey=hidden')));

        await sendMockGoBridgeEvent(
          jsonEncode({
            'event': 'group_message:received',
            'data': {
              'groupId': 'group-de019-error',
              'messageId': 'message-de019-error',
              'senderId': 'peer-de019',
              'keyEpoch': 1,
              'payload': {'text': 'after error recovery'},
            },
          }),
        );

        final payload = await received.future.timeout(
          const Duration(seconds: 1),
        );
        expect(payload['groupId'], 'group-de019-error');
        expect(payload['messageId'], 'message-de019-error');
        expect(
          payload['payload'],
          containsPair('text', 'after error recovery'),
        );
      },
    );

    test(
      'DE-019 EventChannel done emits diagnostics, recovers, and preserves group callback',
      () async {
        final eventChannelCalls = <String>[];
        final flowEvents = <Map<String, dynamic>>[];
        installMockGoBridgeEventChannel(calls: eventChannelCalls);
        debugSetFlowEventSink(flowEvents.add);

        final received = Completer<Map<String, dynamic>>();
        client.onGroupMessageReceived = (payload) {
          if (!received.isCompleted) {
            received.complete(payload);
          }
        };

        await client.initialize();
        expect(client.isInitialized, isTrue);
        expect(
          eventChannelCalls.where((call) => call == 'listen'),
          hasLength(1),
        );

        await closeMockGoBridgeEventChannel();
        await waitForCondition(
          () => eventChannelCalls.where((call) => call == 'listen').length >= 2,
          description: 'EventChannel done recovery listen',
        );

        expect(client.isInitialized, isTrue);
        expect(eventChannelCalls, contains('cancel'));
        expect(
          flowEvents.map((event) => event['event']),
          containsAllInOrder([
            'GO_BRIDGE_EVENT_STREAM_DONE',
            'GO_BRIDGE_EVENT_STREAM_RECOVERY_REQUESTED',
            'GO_BRIDGE_REINIT_START',
            'GO_BRIDGE_INIT_SUCCESS',
            'GO_BRIDGE_EVENT_STREAM_RECOVERY_SUCCESS',
          ]),
        );

        await sendMockGoBridgeEvent(
          jsonEncode({
            'event': 'group_message:received',
            'data': {
              'groupId': 'group-de019-done',
              'messageId': 'message-de019-done',
              'senderId': 'peer-de019',
              'keyEpoch': 1,
              'payload': {'text': 'after done recovery'},
            },
          }),
        );

        final payload = await received.future.timeout(
          const Duration(seconds: 1),
        );
        expect(payload['groupId'], 'group-de019-done');
        expect(payload['messageId'], 'message-de019-done');
        expect(payload['payload'], containsPair('text', 'after done recovery'));
      },
    );

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
      'PL-008 bridge routes group messages while media progress events arrive',
      () async {
        final progressEvents = <Map<String, dynamic>>[];
        final progressSub = mediaUploadProgressStream.listen(
          progressEvents.add,
        );
        addTearDown(progressSub.cancel);

        final groupEvents = <Map<String, dynamic>>[];
        client.onGroupMessageReceived = groupEvents.add;

        for (var i = 0; i < 20; i++) {
          client.debugHandleEventForTest(
            jsonEncode({
              'event': 'media:upload_progress',
              'data': {
                'id': 'pl008-upload',
                'sentBytes': i * 512,
                'totalBytes': 20 * 512,
                'toPeerId': 'peer-pl008',
              },
            }),
          );

          if (i == 4 || i == 11 || i == 17) {
            final sequence = groupEvents.length;
            client.debugHandleEventForTest(
              jsonEncode({
                'event': 'group_message:received',
                'data': {
                  'groupId': 'group-pl008',
                  'messageId': 'pl008-message-$sequence',
                  'senderId': 'peer-pl008-sender',
                  'keyEpoch': 1,
                  'payload': {'text': 'message during progress $sequence'},
                },
              }),
            );
          }
        }

        expect(progressEvents, hasLength(20));
        expect(progressEvents.last['id'], 'pl008-upload');
        expect(progressEvents.last['sentBytes'], 19 * 512);
        expect(groupEvents, hasLength(3));
        expect(groupEvents.map((event) => event['messageId']).toList(), [
          'pl008-message-0',
          'pl008-message-1',
          'pl008-message-2',
        ]);
        expect(groupEvents.map((event) => event['payload']['text']).toList(), [
          'message during progress 0',
          'message during progress 1',
          'message during progress 2',
        ]);
      },
    );

    test(
      'GO-004 group decryption failure diagnostic reaches repair stream without message callback',
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
              'plaintext': 'GO-004 plaintext must not leak',
              'groupKey': 'GO-004 group key must not leak',
              'ciphertext': 'GO-004 ciphertext must not leak',
              'nonce': 'GO-004 nonce must not leak',
            },
          }),
        );

        final received = await eventFuture;
        final encoded = jsonEncode(received);
        expect(received['event'], 'group:decryption_failed');
        expect(received['groupId'], 'group-1');
        expect(received['senderId'], 'peer-2');
        expect(received['keyEpoch'], 3);
        expect(received['localKeyEpoch'], 4);
        expect(received['error'], contains('failed'));
        expect(encoded, isNot(contains('GO-004 plaintext must not leak')));
        expect(encoded, isNot(contains('GO-004 group key must not leak')));
        expect(encoded, isNot(contains('GO-004 ciphertext must not leak')));
        expect(encoded, isNot(contains('GO-004 nonce must not leak')));
        expect(encoded, contains('[redacted]'));
        expect(groupMessageCalls, 0);
      },
    );

    test(
      'GO-004 group diagnostic stream redacts sensitive payload fields',
      () async {
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
        expect(received['groupId'], 'group-1');
        expect(received['senderId'], 'peer-2');
        expect(received['keyEpoch'], 3);
        expect(received['localKeyEpoch'], 4);
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
      'GO-008 group message raw flow logs metadata only without plaintext or sensitive payloads',
      () {
        const protectedText = 'GO-008 protected plaintext must not hit logs';
        const mediaKey = 'GO-008 media key must not hit logs';
        const mediaNonce = 'GO-008 media nonce must not hit logs';
        const rawCiphertext = 'GO-008 raw ciphertext must not hit logs';
        const rawGroupKey = 'GO-008 group key must not hit logs';
        final flowEvents = <Map<String, dynamic>>[];
        flowEventLoggingEnabled = true;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null && message.startsWith('[FLOW] ')) {
            flowEvents.add(
              jsonDecode(message.substring('[FLOW] '.length))
                  as Map<String, dynamic>,
            );
          }
        };

        Map<String, dynamic>? delivered;
        client.onGroupMessageReceived = (data) {
          delivered = data;
        };

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group_message:received',
            'data': {
              'groupId': 'group-go008',
              'senderId': 'peer-go008',
              'senderDeviceId': 'device-go008',
              'transportPeerId': 'transport-go008',
              'messageId': 'msg-go008',
              'keyEpoch': 8,
              'text': protectedText,
              'ciphertext': rawCiphertext,
              'groupKey': rawGroupKey,
              'media': [
                {
                  'id': 'blob-go008',
                  'encryptionKeyBase64': mediaKey,
                  'encryptionNonce': mediaNonce,
                },
              ],
              'decryptMs': 3,
              'deliveryMs': 4,
            },
          }),
        );

        expect(delivered, isNotNull);
        expect(delivered!['text'], protectedText);

        final rawFlow = flowEvents.firstWhere(
          (event) => event['event'] == 'group_message:received',
        );
        expect(rawFlow['details']['messageId'], 'msg-go008');
        expect(rawFlow['details']['textLength'], protectedText.length);
        expect(rawFlow['details']['mediaCount'], 1);
        expect(rawFlow['details'].containsKey('text'), isFalse);
        expect(rawFlow['details'].containsKey('media'), isFalse);

        final encodedFlow = jsonEncode(flowEvents);
        for (final fragment in [
          protectedText,
          mediaKey,
          mediaNonce,
          rawCiphertext,
          rawGroupKey,
        ]) {
          expect(encodedFlow, isNot(contains(fragment)));
        }
      },
    );

    test(
      'GO-008 diagnostic flow logs redact JSON-encoded sensitive payload strings',
      () async {
        const protectedText = 'GO-008 diagnostic plaintext must not hit logs';
        const rawCiphertext = 'GO-008 diagnostic ciphertext must not hit logs';
        const rawNonce = 'GO-008 diagnostic nonce must not hit logs';
        const rawGroupKey = 'GO-008 diagnostic group key must not hit logs';
        const mediaKey = 'GO-008 diagnostic media key must not hit logs';
        final flowEvents = <Map<String, dynamic>>[];
        flowEventLoggingEnabled = true;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null && message.startsWith('[FLOW] ')) {
            flowEvents.add(
              jsonDecode(message.substring('[FLOW] '.length))
                  as Map<String, dynamic>,
            );
          }
        };
        final eventFuture = groupDiagnosticEventStream.first.timeout(
          const Duration(seconds: 1),
        );

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group:decryption_failed',
            'data': {
              'groupId': 'group-go008',
              'senderId': 'peer-go008',
              'keyEpoch': 8,
              'error':
                  'decrypt failed {"text":"$protectedText","ciphertext":"$rawCiphertext","nonce":"$rawNonce","groupKey":"$rawGroupKey","encryptionKeyBase64":"$mediaKey"}',
              'plaintext': protectedText,
              'ciphertext': rawCiphertext,
              'nonce': rawNonce,
              'groupKey': rawGroupKey,
            },
          }),
        );

        final diagnostic = await eventFuture;
        final encodedDiagnostic = jsonEncode(diagnostic);
        final encodedFlow = jsonEncode(flowEvents);
        for (final payload in [encodedDiagnostic, encodedFlow]) {
          for (final fragment in [
            protectedText,
            rawCiphertext,
            rawNonce,
            rawGroupKey,
            mediaKey,
          ]) {
            expect(payload, isNot(contains(fragment)));
          }
          expect(payload, contains('[redacted]'));
        }
      },
    );

    test(
      'DE-015 payload parse diagnostic does not poison later group message callback',
      () async {
        var groupMessageCalls = 0;
        Map<String, dynamic>? validMessage;
        client.onGroupMessageReceived = (payload) {
          groupMessageCalls++;
          validMessage = payload;
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

        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group_message:received',
            'data': {
              'groupId': 'group-parse',
              'senderId': 'peer-3',
              'messageId': 'de015-valid-after-parse-failure',
              'keyEpoch': 1,
              'text': 'DE-015 valid after parse failure',
            },
          }),
        );

        expect(groupMessageCalls, 1);
        expect(validMessage?['groupId'], 'group-parse');
        expect(validMessage?['messageId'], 'de015-valid-after-parse-failure');
        expect(validMessage?['text'], 'DE-015 valid after parse failure');
      },
    );

    test(
      'DE-016 validation reject diagnostic reaches safe logs without group message callback',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
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

        final validationFlow = flowEvents.where(
          (event) => event['event'] == 'GROUP_VALIDATION_REJECTED',
        );
        expect(validationFlow, hasLength(1));
        final details =
            validationFlow.single['details'] as Map<String, dynamic>;
        expect(details['reason'], 'bad_signature_or_epoch');
        expect(details['groupHash'], '123456789abc');
        expect(details['senderHash'], 'abcdef123456');
        expect(details['transportPeerHash'], '456789abcdef');
        expect(details['localPeerHash'], 'fedcba987654');
        expect(details['envelopeType'], 'group_message');
        expect(details['keyEpoch'], 2);
        expect(details.containsKey('groupId'), isFalse);
        expect(details.containsKey('senderId'), isFalse);
      },
    );

    test(
      'GO-003 group publish validation feedback reaches diagnostics stream without invoking group message callback',
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
            'event': 'group:publish_validation_rejected',
            'data': {
              'groupId': 'group-go003',
              'messageId': 'msg-go003',
              'reason': 'non_member',
              'envelopeType': 'group_message',
              'keyEpoch': 4,
              'recipientPeerId': '12D3KooWLongSensitivePeerIdentifier',
            },
          }),
        );

        final received = await eventFuture;
        expect(received['event'], 'group:publish_validation_rejected');
        expect(received['groupId'], 'group-go003');
        expect(received['messageId'], 'msg-go003');
        expect(received['reason'], 'non_member');
        expect(received['envelopeType'], 'group_message');
        expect(received['keyEpoch'], 4);
        expect(received['recipientPeerId'], '[redacted]');
        expect(groupMessageCalls, 0);
      },
    );

    test(
      'DE-020 large group payload does not starve later group callback',
      () async {
        final received = <Map<String, dynamic>>[];
        client.onGroupMessageReceived = received.add;

        final largeText = 'L' * maxMessageLength;
        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group_message:received',
            'data': {
              'groupId': 'group-de020',
              'senderId': 'peer-de020',
              'messageId': 'de020-large',
              'keyEpoch': 1,
              'text': largeText,
            },
          }),
        );
        client.debugHandleEventForTest(
          jsonEncode({
            'event': 'group_message:received',
            'data': {
              'groupId': 'group-de020',
              'senderId': 'peer-de020',
              'messageId': 'de020-normal',
              'keyEpoch': 1,
              'text': 'DE-020 normal follow-up',
            },
          }),
        );

        expect(received, hasLength(2));
        expect(received[0]['messageId'], 'de020-large');
        expect((received[0]['text'] as String).length, maxMessageLength);
        expect(received[1]['messageId'], 'de020-normal');
        expect(received[1]['text'], 'DE-020 normal follow-up');
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
