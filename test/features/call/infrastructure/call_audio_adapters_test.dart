import 'dart:async';

import 'package:audio_session/audio_session.dart' as audio;
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/call_foreground_audio_session_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_microphone_permission_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_audio_route_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallMicrophonePermissionAdapter', () {
    test(
      'forwards the existing gateway result without another prompt',
      () async {
        final gateway = _FakeMicPermissionGateway(
          MicPermissionStatus.permanentlyDenied,
        );
        final adapter = CallMicrophonePermissionAdapter(gateway: gateway);

        final result = await adapter.request();

        expect(result, MicPermissionStatus.permanentlyDenied);
        expect(gateway.requestCalls, 1);
        expect(gateway.openSettingsCalls, 0);
      },
    );
  });

  group('CallForegroundAudioSessionAdapter', () {
    test('uses foreground voice-call audio policy without speaker default', () {
      final configuration =
          CallForegroundAudioSessionAdapter.audioSessionConfiguration;

      expect(
        configuration.avAudioSessionCategory,
        audio.AVAudioSessionCategory.playAndRecord,
      );
      expect(
        configuration.avAudioSessionMode,
        audio.AVAudioSessionMode.voiceChat,
      );
      expect(
        configuration.avAudioSessionCategoryOptions?.contains(
          audio.AVAudioSessionCategoryOptions.allowBluetooth,
        ),
        isTrue,
      );
      expect(
        configuration.avAudioSessionCategoryOptions?.contains(
          audio.AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        ),
        isTrue,
      );
      expect(
        configuration.avAudioSessionCategoryOptions?.contains(
          audio.AVAudioSessionCategoryOptions.defaultToSpeaker,
        ),
        isFalse,
      );
      expect(
        configuration.androidAudioAttributes?.contentType,
        audio.AndroidAudioContentType.speech,
      );
      expect(
        configuration.androidAudioAttributes?.usage,
        audio.AndroidAudioUsage.voiceCommunication,
      );
      expect(
        configuration.androidAudioFocusGainType,
        audio.AndroidAudioFocusGainType.gain,
      );
      expect(configuration.androidWillPauseWhenDucked, isTrue);
    });

    test('configures then activates exactly once', () async {
      final platform = _FakeAudioSessionPlatform();
      final adapter = platform.createAdapter();

      await Future.wait(<Future<void>>[adapter.activate(), adapter.activate()]);

      expect(platform.calls, <String>['configure', 'active:true']);
      expect(adapter.ownsSession, isTrue);
    });

    test(
      'rejected activation is stable and does not claim ownership',
      () async {
        final platform = _FakeAudioSessionPlatform()
          ..activationAccepted = false;
        final adapter = platform.createAdapter();

        await expectLater(
          adapter.activate(),
          throwsA(
            isA<CallForegroundAudioSessionException>().having(
              (error) => error.code,
              'code',
              CallForegroundAudioSessionErrorCode.activationRejected,
            ),
          ),
        );

        expect(adapter.ownsSession, isFalse);
        await adapter.deactivate();
        expect(platform.deactivationCalls, 1);
      },
    );

    test(
      'surfaces coarse interruption begin and end while ownership remains',
      () async {
        final platform = _FakeAudioSessionPlatform();
        final adapter = platform.createAdapter();
        final interruptions = <CallAudioSessionInterruption>[];
        final subscription = adapter.interruptions.listen(interruptions.add);
        await adapter.activate();

        platform.emit(CallAudioSessionPlatformInterruption.begin);
        platform.emit(CallAudioSessionPlatformInterruption.end);

        expect(interruptions.map((event) => event.isBeginning), <bool>[
          true,
          false,
        ]);
        expect(adapter.ownsSession, isTrue);
        await subscription.cancel();
        await adapter.deactivate();
      },
    );

    test('permanent loss revokes recovery ownership before end', () async {
      final platform = _FakeAudioSessionPlatform();
      final adapter = platform.createAdapter();
      final interruptions = <CallAudioSessionInterruption>[];
      final subscription = adapter.interruptions.listen(interruptions.add);
      await adapter.activate();

      platform.emit(CallAudioSessionPlatformInterruption.begin);
      platform.emit(CallAudioSessionPlatformInterruption.ownershipLost);

      expect(interruptions.map((event) => event.isBeginning), <bool>[
        true,
        false,
      ]);
      expect(adapter.ownsSession, isFalse);
      await subscription.cancel();
      await adapter.deactivate();
    });

    test(
      'deactivation is idempotent and stops forwarding interruptions',
      () async {
        final platform = _FakeAudioSessionPlatform();
        final adapter = platform.createAdapter();
        final interruptions = <CallAudioSessionInterruption>[];
        adapter.interruptions.listen(interruptions.add);
        await adapter.activate();

        await Future.wait(<Future<void>>[
          adapter.deactivate(),
          adapter.deactivate(),
        ]);
        platform.emit(CallAudioSessionPlatformInterruption.begin);

        expect(platform.deactivationCalls, 1);
        expect(adapter.ownsSession, isFalse);
        expect(interruptions, isEmpty);
      },
    );

    test('restores prior policy before releasing focus exactly once', () async {
      final platform = _FakeAudioSessionPlatform();
      final adapter = platform.createAdapter();
      await adapter.activate();

      await Future.wait(<Future<void>>[
        adapter.deactivate(),
        adapter.deactivate(),
      ]);

      expect(platform.calls, <String>[
        'configure',
        'active:true',
        'restore',
        'active:false',
      ]);
    });

    test('uses the audio_session end result to decide recovery ownership', () {
      expect(
        CallForegroundAudioSessionAdapter.mapAudioSessionInterruption(
          audio.AudioInterruptionEvent(
            true,
            audio.AudioInterruptionType.unknown,
          ),
        ),
        CallAudioSessionPlatformInterruption.begin,
      );
      expect(
        CallForegroundAudioSessionAdapter.mapAudioSessionInterruption(
          audio.AudioInterruptionEvent(
            false,
            audio.AudioInterruptionType.unknown,
          ),
        ),
        CallAudioSessionPlatformInterruption.ownershipLost,
      );
      expect(
        CallForegroundAudioSessionAdapter.mapAudioSessionInterruption(
          audio.AudioInterruptionEvent(
            false,
            audio.AudioInterruptionType.pause,
          ),
        ),
        CallAudioSessionPlatformInterruption.end,
      );
    });
  });

  group('CallAudioRouteAdapter', () {
    test('enumeration timeout degrades to deterministic safe routes', () async {
      final neverCompletes = Completer<List<CallAudioOutputRoute>>();
      final adapter = CallAudioRouteAdapter(
        enumerateOutputs: () => neverCompletes.future,
        selectOutput: (_) async {},
        setSpeakerphone: (_) async {},
        enumerationTimeout: const Duration(milliseconds: 5),
      );

      final routes = await adapter.supportedOutputRoutes().timeout(
        const Duration(milliseconds: 100),
      );

      expect(routes, <CallAudioOutputRoute>[
        CallAudioOutputRoute.systemDefault,
        CallAudioOutputRoute.speaker,
      ]);
    });

    test('enumeration timeout does not invent a speaker operation', () async {
      final neverCompletes = Completer<List<CallAudioOutputRoute>>();
      final adapter = CallAudioRouteAdapter(
        enumerateOutputs: () => neverCompletes.future,
        selectOutput: (_) async {},
        setSpeakerphone: null,
        enumerationTimeout: const Duration(milliseconds: 5),
      );

      expect(await adapter.supportedOutputRoutes(), <CallAudioOutputRoute>[
        CallAudioOutputRoute.systemDefault,
      ]);
    });

    test('timeout fallback speaker keeps normal selection semantics', () async {
      final neverCompletes = Completer<List<CallAudioOutputRoute>>();
      final speakerValues = <bool>[];
      final adapter = CallAudioRouteAdapter(
        enumerateOutputs: () => neverCompletes.future,
        selectOutput: (_) async => fail('speaker must use its coarse setter'),
        setSpeakerphone: (enabled) async => speakerValues.add(enabled),
        enumerationTimeout: const Duration(milliseconds: 5),
      );

      await adapter.selectOutputRoute(CallAudioOutputRoute.speaker);

      expect(speakerValues, <bool>[true]);
      expect(adapter.selectedRoute, CallAudioOutputRoute.speaker);
    });

    test('non-timeout enumeration failure keeps its stable mapping', () async {
      final adapter = CallAudioRouteAdapter(
        enumerateOutputs: () async => throw StateError('platform detail'),
        selectOutput: (_) async {},
        setSpeakerphone: (_) async {},
        enumerationTimeout: const Duration(milliseconds: 5),
      );

      await expectLater(
        adapter.supportedOutputRoutes(),
        throwsA(
          isA<CallAudioRouteException>().having(
            (error) => error.code,
            'code',
            CallAudioRouteErrorCode.enumerationFailed,
          ),
        ),
      );
    });
  });
}

final class _FakeMicPermissionGateway implements MicPermissionGateway {
  _FakeMicPermissionGateway(this.status);

  final MicPermissionStatus status;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<MicPermissionStatus> request() async {
    requestCalls++;
    return status;
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalls++;
    return true;
  }
}

final class _FakeAudioSessionPlatform {
  final StreamController<CallAudioSessionPlatformInterruption> events =
      StreamController<CallAudioSessionPlatformInterruption>.broadcast(
        sync: true,
      );
  final List<String> calls = <String>[];
  bool activationAccepted = true;
  int deactivationCalls = 0;

  CallForegroundAudioSessionAdapter createAdapter() =>
      CallForegroundAudioSessionAdapter(
        configure: () async => calls.add('configure'),
        restore: () async => calls.add('restore'),
        setActive: (active) async {
          calls.add('active:$active');
          if (!active) deactivationCalls++;
          return active ? activationAccepted : true;
        },
        platformInterruptions: events.stream,
      );

  void emit(CallAudioSessionPlatformInterruption event) => events.add(event);
}
