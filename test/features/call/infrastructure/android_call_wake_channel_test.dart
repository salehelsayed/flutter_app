import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_wake_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const native = MethodChannel(AndroidCallWakeChannel.channelName);

  Future<Object?> signal([Object? arguments]) async {
    const codec = StandardMethodCodec();
    final reply = await messenger.handlePlatformMessage(
      AndroidCallWakeChannel.channelName,
      codec.encodeMethodCall(
        MethodCall(AndroidCallWakeChannel.wakeMethod, arguments),
      ),
      (_) {},
    );
    return reply == null ? null : codec.decodeEnvelope(reply);
  }

  tearDown(() => messenger.setMockMethodCallHandler(native, null));

  test(
    'ready handshake installs the drain before native replays a queued wake',
    () async {
      var drains = 0;
      messenger.setMockMethodCallHandler(native, (call) async {
        expect(call.method, 'ready');
        expect(call.arguments, isNull);
        expect(await signal(), isTrue);
        return null;
      });
      final channel = AndroidCallWakeChannel(onCallWake: () async => drains++);
      addTearDown(channel.dispose);
      await channel.install();
      expect(drains, 1);
      expect(await signal(), isTrue);
      expect(drains, 2);
    },
  );

  test('payload arguments never become incoming call authority', () async {
    var drains = 0;
    final channel = AndroidCallWakeChannel(onCallWake: () async => drains++);
    addTearDown(channel.dispose);
    await channel.install();
    expect(
      await signal({'callId': 'untrusted', 'displayName': 'untrusted'}),
      isFalse,
    );
    expect(drains, 0);
    expect(await signal(), isTrue);
    expect(drains, 1);
  });

  test('drain errors are contained and disposal stops callbacks', () async {
    final channel = AndroidCallWakeChannel(
      onCallWake: () async => throw StateError('private failure'),
    );
    await channel.install();
    expect(await signal(), isFalse);
    channel.dispose();
    expect(await signal(), isNull);
  });
}
