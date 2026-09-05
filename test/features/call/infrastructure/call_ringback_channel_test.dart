import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/infrastructure/call_ringback_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final callA = CallId.parse('11111111-1111-4111-8111-111111111111');

  test(
    'start and stop cross the channel with the versioned call handle',
    () async {
      final calls = <MethodCall>[];
      final port = MethodChannelCallRingbackPort(
        invokeMethod: (method, arguments) async {
          calls.add(MethodCall(method, arguments));
          return method == MethodChannelCallRingbackPort.startMethod;
        },
      );

      expect(await port.start(callA), isTrue);
      expect(await port.stop(callA), isFalse);
      expect(calls.map((call) => call.method), ['start', 'stop']);
      for (final call in calls) {
        expect(call.arguments, {'version': 1, 'callHandle': callA.value});
      }
    },
  );

  test('the production channel name and methods are pinned', () {
    expect(MethodChannelCallRingbackPort.channelName, 'mknoon/call_ringback');
    expect(MethodChannelCallRingbackPort.startMethod, 'start');
    expect(MethodChannelCallRingbackPort.stopMethod, 'stop');
    expect(MethodChannelCallRingbackPort.protocolVersion, 1);
  });

  test('a platform without a native tone player answers false', () async {
    final port = MethodChannelCallRingbackPort(
      invokeMethod: (_, _) async => throw MissingPluginException(),
    );

    expect(await port.start(callA), isFalse);
    expect(await port.stop(callA), isFalse);
  });

  test('a null native answer counts as refused', () async {
    final port = MethodChannelCallRingbackPort(
      invokeMethod: (_, _) async => null,
    );

    expect(await port.start(callA), isFalse);
  });

  test('a native failure surfaces for the coordinator to report', () async {
    final port = MethodChannelCallRingbackPort(
      invokeMethod: (_, _) async => throw PlatformException(code: 'bad_args'),
    );

    await expectLater(port.start(callA), throwsA(isA<PlatformException>()));
  });

  test('the default port talks to the real method channel', () async {
    const channel = MethodChannel(MethodChannelCallRingbackPort.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final seen = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(await MethodChannelCallRingbackPort().start(callA), isTrue);
    expect(seen.single.method, 'start');
    expect(seen.single.arguments, {'version': 1, 'callHandle': callA.value});
  });
}
