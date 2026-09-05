import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_lifecycle_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_ringback_channel.dart';
import 'package:flutter_app/features/call/infrastructure/ios_call_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ringback rides each platform's native call lifecycle bridge: the Swift and
/// Kotlin bridges own the tone players and already resolve the Dart call
/// handle. A port on any other channel reaches no native code at all (device
/// finding 2026-09-05: `start refused`, no native `ringback=` line).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final callA = CallId.parse('11111111-1111-4111-8111-111111111111');
  final callB = CallId.parse('22222222-2222-4222-8222-222222222222');
  // The native side knows a call by the handle the signaling context
  // registered with it, never by the Dart call id (device finding
  // 2026-09-05 15:09Z: the raw id answered bad_args → `start failed`).
  const handleA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  String? resolve(CallId callId) => callId == callA ? handleA : null;

  test(
    'start and stop cross the bridge with the versioned call handle',
    () async {
      final calls = <MethodCall>[];
      final port = MethodChannelCallRingbackPort.ios(
        resolveCallHandle: resolve,

        invokeMethod: (method, arguments) async {
          calls.add(MethodCall(method, arguments));
          return method == MethodChannelCallRingbackPort.startMethod;
        },
      );

      expect(await port.start(callA), isTrue);
      expect(await port.stop(callA), isFalse);
      expect(calls.map((call) => call.method), [
        'startRingback',
        'stopRingback',
      ]);
      for (final call in calls) {
        expect(call.arguments, {'version': 1, 'callHandle': handleA});
      }
    },
  );

  test("the port rides each platform's native lifecycle bridge", () {
    expect(
      MethodChannelCallRingbackPort.ios(resolveCallHandle: resolve).channelName,
      IosCallLifecycleAdapter.methodChannelName,
    );
    expect(
      MethodChannelCallRingbackPort.android(
        resolveCallHandle: resolve,
      ).channelName,
      AndroidCallLifecycleAdapter.methodChannelName,
    );
    expect(MethodChannelCallRingbackPort.startMethod, 'startRingback');
    expect(MethodChannelCallRingbackPort.stopMethod, 'stopRingback');
    expect(MethodChannelCallRingbackPort.protocolVersion, 1);
  });

  test('both native bridges serve those channels and handle the methods', () {
    final swift = File(
      'ios/Runner/MknoonCallNativeBridge.swift',
    ).readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallNativeBridge.kt',
    ).readAsStringSync();

    expect(
      swift,
      contains(
        'static let methodChannelName = '
        '"${IosCallLifecycleAdapter.methodChannelName}"',
      ),
    );
    expect(
      kotlin,
      contains(
        'const val METHOD_CHANNEL = '
        '"${AndroidCallLifecycleAdapter.methodChannelName}"',
      ),
    );
    for (final method in <String>[
      MethodChannelCallRingbackPort.startMethod,
      MethodChannelCallRingbackPort.stopMethod,
    ]) {
      expect(
        swift,
        contains('case "$method":'),
        reason: 'Swift bridge $method',
      );
      expect(kotlin, contains('"$method" ->'), reason: 'Kotlin bridge $method');
    }
  });

  test('the native side is asked by the registered call handle only', () async {
    final calls = <MethodCall>[];
    final port = MethodChannelCallRingbackPort.android(
      resolveCallHandle: resolve,
      invokeMethod: (method, arguments) async {
        calls.add(MethodCall(method, arguments));
        return true;
      },
    );

    expect(await port.start(callA), isTrue);
    expect((calls.single.arguments as Map)['callHandle'], handleA);
    expect(calls.single.arguments, isNot(containsValue(callA.value)));
  });

  test(
    'a call without a native handle is refused without a native call',
    () async {
      var invocations = 0;
      final port = MethodChannelCallRingbackPort.ios(
        resolveCallHandle: resolve,
        invokeMethod: (_, _) async {
          invocations++;
          return true;
        },
      );

      expect(await port.start(callB), isFalse);
      expect(await port.stop(callB), isFalse);
      expect(invocations, 0);
    },
  );

  test('a platform without a native tone player answers false', () async {
    final port = MethodChannelCallRingbackPort.android(
      resolveCallHandle: resolve,
      invokeMethod: (_, _) async => throw MissingPluginException(),
    );

    expect(await port.start(callA), isFalse);
    expect(await port.stop(callA), isFalse);
  });

  test('a null native answer counts as refused', () async {
    final port = MethodChannelCallRingbackPort.ios(
      resolveCallHandle: resolve,
      invokeMethod: (_, _) async => null,
    );

    expect(await port.start(callA), isFalse);
  });

  test('a native failure surfaces for the coordinator to report', () async {
    final port = MethodChannelCallRingbackPort.ios(
      resolveCallHandle: resolve,
      invokeMethod: (_, _) async => throw PlatformException(code: 'bad_args'),
    );

    await expectLater(port.start(callA), throwsA(isA<PlatformException>()));
  });

  test('the default port talks to the real lifecycle method channel', () async {
    const channel = MethodChannel(IosCallLifecycleAdapter.methodChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final seen = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(
      await MethodChannelCallRingbackPort.ios(
        resolveCallHandle: resolve,
      ).start(callA),
      isTrue,
    );
    expect(seen.single.method, 'startRingback');
    expect(seen.single.arguments, {'version': 1, 'callHandle': handleA});
  });
}
