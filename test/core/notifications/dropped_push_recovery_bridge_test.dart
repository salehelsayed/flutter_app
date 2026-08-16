import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DroppedPushRecoveryBridge.channelName);
  late DroppedPushRecoveryBridge bridge;

  setUp(() {
    bridge = DroppedPushRecoveryBridge(channel: channel);
  });

  tearDown(() {
    bridge.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'pendingGeneration reads a positive native generation without consuming',
    () async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            return 42;
          });

      expect(await bridge.pendingGeneration(), 42);
      expect(await bridge.pendingGeneration(), 42);
      expect(methods, <String>['pendingGeneration', 'pendingGeneration']);
    },
  );

  test(
    'account-bound authority reads and acknowledges the exact marker',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'currentBinding' => ' install-a/account-a ',
              'pendingRecovery' => <String, Object?>{
                'generation': 41,
                'binding': 'install-a/account-a',
              },
              'acknowledgeRecovery' => true,
              _ => null,
            };
          });

      expect(await bridge.currentBinding(), 'install-a/account-a');
      final marker = await bridge.pendingRecovery();
      expect(marker?.generation, 41);
      expect(marker?.binding, 'install-a/account-a');
      expect(await bridge.acknowledgeRecovery(marker!), isTrue);
      expect(calls.last.method, 'acknowledgeRecovery');
      expect(calls.last.arguments, <String, Object?>{
        'generation': 41,
        'binding': 'install-a/account-a',
      });
    },
  );

  test(
    'atomic recovery authority parses one typed snapshot and ACK carries its revision',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'recoveryAuthority' => <String, Object?>{
                'currentBinding': 'v1:${'a' * 64}',
                'recoveryWorkEnabled': true,
                'pendingGeneration': 91,
                'pendingBinding': 'v1:${'a' * 64}',
                'authorityRevision': 17,
                'authorityMutationInProgress': false,
              },
              'headlessAcknowledgeRecovery' => true,
              _ => null,
            };
          });

      final authority = await bridge.recoveryAuthority();

      expect(authority, isNotNull);
      expect(authority?.currentBinding, 'v1:${'a' * 64}');
      expect(authority?.recoveryWorkEnabled, isTrue);
      expect(authority?.pendingMarker?.generation, 91);
      expect(authority?.pendingMarker?.binding, 'v1:${'a' * 64}');
      expect(authority?.authorityRevision, 17);
      expect(authority?.authorityMutationInProgress, isFalse);
      expect(
        await bridge.acknowledgeHeadlessRecovery(
          authority!.pendingMarker!,
          authorityRevision: authority.authorityRevision,
        ),
        isTrue,
      );
      expect(calls.last.method, 'headlessAcknowledgeRecovery');
      expect(calls.last.arguments, <String, Object?>{
        'generation': 91,
        'binding': 'v1:${'a' * 64}',
        'authorityRevision': 17,
      });

      final callCount = calls.length;
      expect(
        await bridge.acknowledgeHeadlessRecovery(
          authority.pendingMarker!,
          authorityRevision: -1,
        ),
        isFalse,
      );
      expect(calls, hasLength(callCount));
    },
  );

  test(
    'atomic recovery authority rejects every malformed fence shape',
    () async {
      final valid = <String, Object?>{
        'currentBinding': 'v1:${'b' * 64}',
        'recoveryWorkEnabled': true,
        'pendingGeneration': 3,
        'pendingBinding': 'v1:${'b' * 64}',
        'authorityRevision': 8,
        'authorityMutationInProgress': false,
      };
      Object? response;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => response);

      final malformed = <Object?>[
        <String, Object?>{...valid}..remove('authorityRevision'),
        <String, Object?>{...valid, 'authorityRevision': 8.0},
        <String, Object?>{...valid, 'authorityRevision': -1},
        <String, Object?>{
          ...valid,
          'authorityMutationInProgress': true,
          'recoveryWorkEnabled': true,
        },
        <String, Object?>{...valid, 'pendingBinding': null},
        <String, Object?>{...valid, 'pendingGeneration': null},
        <String, Object?>{...valid, 'currentBinding': ' padded '},
      ];

      for (final value in malformed) {
        response = value;
        expect(await bridge.recoveryAuthority(), isNull, reason: '$value');
      }
    },
  );

  test(
    'binding publication carries the one-shot stale mutation recovery flag',
    () async {
      MethodCall? received;
      final binding = 'v1:${'c' * 64}';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return <String, Object?>{
              'changed': true,
              'committed': true,
              'currentBinding': binding,
              'recoveryWorkEnabled': true,
            };
          });

      final publication = await bridge.setCurrentBinding(
        binding,
        activateRecoveryWork: true,
        recoverStaleAuthorityMutations: true,
      );

      expect(
        publication.exactlyMatches(binding: binding, recoveryWorkEnabled: true),
        isTrue,
      );
      expect(received?.method, 'setCurrentBinding');
      expect(received?.arguments, <String, Object?>{
        'binding': binding,
        'activateRecoveryWork': true,
        'recoverStaleAuthorityMutations': true,
      });
    },
  );

  test(
    'malformed account-bound marker is never accepted or acknowledged',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => <String, Object?>{
              'generation': 0,
              'binding': 'install-a/account-a',
            },
          );

      expect(await bridge.pendingRecovery(), isNull);
      expect(
        await bridge.acknowledgeRecovery(
          const DroppedPushRecoveryMarker(generation: 7, binding: '   '),
        ),
        isFalse,
      );
    },
  );

  test(
    'zero, malformed, and missing plugin pending results degrade to null',
    () async {
      var response = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => response);
      expect(await bridge.pendingGeneration(), isNull);

      response = -1;
      expect(await bridge.pendingGeneration(), isNull);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 1.5);
      expect(await bridge.pendingGeneration(), isNull);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'not-an-int');
      expect(await bridge.pendingGeneration(), isNull);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await bridge.pendingGeneration(), isNull);
    },
  );

  test('native pending read failure propagates for fail-closed ownership', () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'pending_read_failed'),
        );

    expect(
      bridge.pendingGeneration(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'pending_read_failed',
        ),
      ),
    );
  });

  test('acknowledgeGeneration sends the exact generation map', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return true;
        });

    expect(await bridge.acknowledgeGeneration(77), isTrue);
    expect(received?.method, 'acknowledgeGeneration');
    expect(received?.arguments, <String, Object?>{'generation': 77});
  });

  test(
    'native recoveryPending callback accelerates without consuming state',
    () async {
      final generations = <int?>[];
      bridge.register((generation) async {
        generations.add(generation);
      });

      await _sendNativeMethodCall(
        channel,
        const MethodCall('recoveryPending', <String, Object?>{
          'generation': 91,
        }),
      );

      expect(generations, <int?>[91]);
    },
  );

  test('unknown native callback is not routed as recovery work', () async {
    var routed = false;
    bridge.register((_) async {
      routed = true;
    });

    await _sendNativeMethodCall(channel, const MethodCall('unknown'));

    expect(routed, isFalse);
  });
}

Future<void> _sendNativeMethodCall(MethodChannel channel, MethodCall call) {
  final completer = Completer<void>();
  final encoded = const StandardMethodCodec().encodeMethodCall(call);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, encoded, (reply) {
        if (reply == null) {
          completer.complete();
          return;
        }
        try {
          const StandardMethodCodec().decodeEnvelope(reply);
          completer.complete();
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      });
  return completer.future;
}
