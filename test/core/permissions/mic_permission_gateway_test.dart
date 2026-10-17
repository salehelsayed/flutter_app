import 'package:flutter/services.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('flutter.baseflow.com/permissions/methods');
const _microphone = 7;
const _denied = 0;
const _granted = 1;
const _permanentlyDenied = 4;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const gateway = PermissionHandlerMicGateway();
  var osStatus = _denied;
  var osRequestResult = _denied;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'checkPermissionStatus':
              return call.arguments == _microphone ? osStatus : _denied;
            case 'requestPermissions':
              return <int, int>{_microphone: osRequestResult};
          }
          throw MissingPluginException(call.method);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  // The gateway remembers the last request result for the whole process, so
  // each test sets its starting state with a request first.

  test('granted', () async {
    osRequestResult = _granted;
    expect(await gateway.request(), MicPermissionStatus.granted);

    osStatus = _granted;
    expect(await gateway.status(), MicPermissionStatus.granted);
  });

  test('denied but the OS can still ask', () async {
    osRequestResult = _denied;
    expect(await gateway.request(), MicPermissionStatus.denied);

    osStatus = _denied;
    expect(await gateway.status(), MicPermissionStatus.denied);
  });

  test(
    'permanently denied stays permanent while Android status says denied',
    () async {
      osRequestResult = _permanentlyDenied;
      expect(await gateway.request(), MicPermissionStatus.permanentlyDenied);

      osStatus = _denied;
      expect(await gateway.status(), MicPermissionStatus.permanentlyDenied);
    },
  );

  test('returned from Settings with the mic turned on', () async {
    osRequestResult = _permanentlyDenied;
    expect(await gateway.request(), MicPermissionStatus.permanentlyDenied);

    osStatus = _granted;
    expect(await gateway.status(), MicPermissionStatus.granted);
    osRequestResult = _granted;
    expect(await gateway.request(), MicPermissionStatus.granted);

    osStatus = _denied;
    expect(await gateway.status(), MicPermissionStatus.denied);
    osRequestResult = _denied;
    expect(await gateway.request(), MicPermissionStatus.denied);
    expect(await gateway.status(), MicPermissionStatus.denied);
  });
}
