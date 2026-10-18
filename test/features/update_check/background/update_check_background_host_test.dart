import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/features/update_check/application/update_check_service.dart';
import 'package:flutter_app/features/update_check/application/update_check_switch.dart';
import 'package:flutter_app/features/update_check/background/update_check_background_host.dart';
import 'package:flutter_app/features/update_check/background/update_check_background_runner.dart';
import 'package:flutter_app/features/update_check/background/update_check_notifier.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_check_notify_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/update_check_test_keys.dart';

// SE-41 T4a: the main-engine host. AC1 (kill switch -> nothing scheduled),
// AC5 (the trigger runs before any bootstrap), AC7 (iOS tap opens the
// built-in store URL through the injected launcher).

const _channel = MethodChannel(updateCheckBackgroundChannelName);

UpdateCheckSwitch _switch({
  String mode = 'on',
  bool debug = false,
  bool e2e = false,
  String sims = '',
}) => UpdateCheckSwitch(
  mode: mode,
  isDebugBuild: debug,
  e2eTestMode: e2e,
  simsBuildProfileId: sims,
);

class _NoPoster implements UpdateNotificationPoster {
  @override
  Future<bool> post({
    required UpdateNotifyKind kind,
    required String title,
    required String body,
  }) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> nativeCalls;

  setUp(() {
    nativeCalls = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      nativeCalls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  Future<Object?> callFromNative(String method, [Object? arguments]) async {
    final reply = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      updateCheckBackgroundChannelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      reply.complete,
    );
    final data = await reply.future;
    return data == null
        ? null
        : const StandardMethodCodec().decodeEnvelope(data);
  }

  group('kill switch (AC1)', () {
    for (final (name, updateSwitch) in [
      ('E2E_TEST_MODE', _switch(e2e: true)),
      ('SIMS_BUILD_PROFILE_ID', _switch(sims: 'ios.simulator.app')),
      ('debug default', _switch(mode: '', debug: true)),
      ('MKNOON_UPDATE_CHECK=off', _switch(mode: 'off')),
    ]) {
      test(
        '$name: configure tells native code to cancel, never schedule',
        () async {
          await UpdateCheckBackgroundHost(
            updateSwitch: updateSwitch,
          ).configure();
          expect(nativeCalls.single.method, 'configure');
          expect(nativeCalls.single.arguments, {'enabled': false});
        },
      );
    }

    test('on: configure schedules', () async {
      await UpdateCheckBackgroundHost(updateSwitch: _switch()).configure();
      expect(nativeCalls.single.arguments, {'enabled': true});
    });

    test(
      'fixture enables checks while cancelling uncontrolled native jobs',
      () async {
        const fixture = UpdateCheckSwitch(
          mode: 'on',
          isDebugBuild: true,
          e2eTestMode: true,
          simsBuildProfileId: 'android.e2e.production_call_local',
          testProfileOptIn: true,
        );
        expect(fixture.enabled, isTrue);
        await UpdateCheckBackgroundHost(updateSwitch: fixture).configure();
        expect(nativeCalls.single.method, 'configure');
        expect(nativeCalls.single.arguments, {'enabled': false});
      },
    );
  });

  test(
    'run answers before any bootstrap and passes the call state (AC5)',
    () async {
      final temp = await TempStateStore.create();
      addTearDown(temp.dispose);
      final fetcher = FakeVersionFileFetcher([
        signedEnvelope(payloadBytes(ios: section(120, 115))),
      ]);
      final calls = <bool>[];
      final bootstrap = Completer<void>();
      UpdateCheckBackgroundHost(
        updateSwitch: _switch(),
        runnerFactory: (inCall) {
          calls.add(inCall);
          return UpdateCheckBackgroundRunner(
            service: UpdateCheckService(
              updateSwitch: _switch(),
              verifier: testVerifier(),
              fetcher: fetcher,
              store: temp.store,
              installedBuildNumber: () async => '110',
              platform: UpdatePlatform.ios,
            ),
            store: temp.store,
            poster: _NoPoster(),
            isForeground: () async => false,
            isInCall: () async => inCall,
          );
        },
      ).install();

      final reply = await callFromNative('run', {
        'reason': 'ios_bg_app_refresh',
        'budgetMs': 5000,
        'inCall': true,
      });
      expect(reply, {'outcome': 'inCall', 'enabled': true, 'checked': true});
      expect(calls, [true]);
      expect(bootstrap.isCompleted, isFalse);
    },
  );

  test('a check-now push over the channel always checks (T4b G1)', () async {
    final temp = await TempStateStore.create();
    addTearDown(temp.dispose);
    final envelope = signedEnvelope(payloadBytes(ios: section(110, 100)));
    final fetcher = FakeVersionFileFetcher([envelope, envelope]);
    UpdateCheckBackgroundHost(
      updateSwitch: _switch(),
      runnerFactory: (inCall) => UpdateCheckBackgroundRunner(
        service: UpdateCheckService(
          updateSwitch: _switch(),
          verifier: testVerifier(),
          fetcher: fetcher,
          store: temp.store,
          installedBuildNumber: () async => '110',
          platform: UpdatePlatform.ios,
        ),
        store: temp.store,
        poster: _NoPoster(),
        isForeground: () async => false,
        isInCall: () async => inCall,
      ),
    ).install();

    Future<Object?> run(String reason) => callFromNative('run', {
      'reason': reason,
      'budgetMs': 5000,
      'inCall': false,
    });
    expect((await run('ios_bg_app_refresh') as Map)['checked'], isTrue);
    expect((await run('ios_push') as Map)['checked'], isTrue);
    expect((await run('ios_bg_app_refresh') as Map)['checked'], isFalse);
    expect(fetcher.calls, 2);
  });

  test('openStore opens only the built-in TestFlight link (AC7)', () async {
    final opened = <Uri>[];
    UpdateCheckBackgroundHost(
      updateSwitch: _switch(),
      launcher: (url) async {
        opened.add(url);
        return true;
      },
      platform: UpdatePlatform.ios,
    ).install();

    expect(
      await callFromNative('openStore', {'url': 'https://evil.example'}),
      true,
    );
    expect(opened, [Uri.parse('https://testflight.apple.com/join/nUVjrEYS')]);
  });
}
