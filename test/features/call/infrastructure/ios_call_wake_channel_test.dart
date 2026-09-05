import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/infrastructure/ios_call_wake_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Object?> nativeCall(String method) async {
    const codec = StandardMethodCodec();
    final reply = await TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          IosCallWakeChannel.channelName,
          codec.encodeMethodCall(MethodCall(method)),
          (_) {},
        );
    if (reply == null) return null;
    return codec.decodeEnvelope(reply);
  }

  test(
    'a native call wake runs the Dart drain exactly once per push',
    () async {
      var wakes = 0;
      final channel = IosCallWakeChannel(onCallWake: () async => wakes++)
        ..install();
      addTearDown(channel.dispose);

      expect(await nativeCall(IosCallWakeChannel.wakeMethod), isTrue);
      expect(await nativeCall(IosCallWakeChannel.wakeMethod), isTrue);
      expect(wakes, 2);
    },
  );

  test('a failing drain never surfaces to native', () async {
    final channel = IosCallWakeChannel(
      onCallWake: () async => throw StateError('private drain failure'),
    )..install();
    addTearDown(channel.dispose);

    expect(await nativeCall(IosCallWakeChannel.wakeMethod), isFalse);
  });

  test('unknown methods are refused', () async {
    var wakes = 0;
    final channel = IosCallWakeChannel(onCallWake: () async => wakes++)
      ..install();
    addTearDown(channel.dispose);

    // An unimplemented method answers with the "not implemented" null reply.
    expect(await nativeCall('somethingElse'), isNull);
    expect(wakes, 0);
  });
}
