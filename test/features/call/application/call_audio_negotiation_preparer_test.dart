import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_audio_negotiation_preparer.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 8, 30, 12);
final _callId = CallId.parse('77777777-7777-4777-8777-777777777777');
const _configuration = CallConnectionConfiguration(
  transportPolicy: CallTransportPolicy.all,
  receiveAudio: true,
  receiveVideo: false,
  captureAudio: true,
  captureVideo: false,
);

CallSessionSnapshot _snapshot({DateTime? acceptedAt}) =>
    CallSessionSnapshot.active(
      callId: _callId,
      contactPeerId: 'contact',
      direction: CallDirection.outgoing,
      state: CallState.accepted,
      callerAccountPeerId: 'local',
      callerDeviceId: 'local-device',
      startedAt: _now,
      observedAt: _now,
      acceptedAt: acceptedAt,
    );

CallAudioStartResult _result(CallAudioStartStatus status) =>
    CallAudioStartResult(status: status, state: CallAudioControlState.idle);

void main() {
  test(
    'forwards only reducer-proven local acceptance to audio start',
    () async {
      bool? observedAcceptance;
      final preparer = CallAudioNegotiationPreparer(
        startAudio: ({required locallyAccepted, required configuration}) async {
          observedAcceptance = locallyAccepted;
          expect(configuration.transportPolicy, _configuration.transportPolicy);
          expect(configuration.captureAudio, isTrue);
          expect(configuration.captureVideo, isFalse);
          return _result(CallAudioStartStatus.started);
        },
      );

      await preparer.prepareLocallyAcceptedMedia(
        snapshot: _snapshot(acceptedAt: _now),
        configuration: _configuration,
      );

      expect(observedAcceptance, isTrue);
    },
  );

  test('permission refusal maps to fixed negotiation failure', () async {
    final preparer = CallAudioNegotiationPreparer(
      startAudio: ({required locallyAccepted, required configuration}) async =>
          _result(CallAudioStartStatus.permissionDenied),
    );

    await expectLater(
      () => preparer.prepareLocallyAcceptedMedia(
        snapshot: _snapshot(acceptedAt: _now),
        configuration: _configuration,
      ),
      throwsA(
        isA<CallNegotiationPortException>().having(
          (error) => error.code,
          'code',
          CallNegotiationPortErrorCode.permissionDenied,
        ),
      ),
    );
  });

  test('reports one fixed audio start status before mapping failure', () async {
    final observed = <CallAudioStartStatus>[];
    final preparer = CallAudioNegotiationPreparer(
      startAudio: ({required locallyAccepted, required configuration}) async =>
          _result(CallAudioStartStatus.engineFailed),
      onStartResult: observed.add,
    );

    await expectLater(
      () => preparer.prepareLocallyAcceptedMedia(
        snapshot: _snapshot(acceptedAt: _now),
        configuration: _configuration,
      ),
      throwsA(
        isA<CallNegotiationPortException>().having(
          (error) => error.code,
          'code',
          CallNegotiationPortErrorCode.mediaUnavailable,
        ),
      ),
    );

    expect(observed, <CallAudioStartStatus>[CallAudioStartStatus.engineFailed]);
  });

  test('missing reducer acceptance never reaches microphone adapter', () async {
    var starts = 0;
    final preparer = CallAudioNegotiationPreparer(
      startAudio: ({required locallyAccepted, required configuration}) async {
        starts++;
        return _result(CallAudioStartStatus.started);
      },
    );

    await expectLater(
      () => preparer.prepareLocallyAcceptedMedia(
        snapshot: _snapshot(),
        configuration: _configuration,
      ),
      throwsA(isA<CallNegotiationPortException>()),
    );
    expect(starts, 0);
  });

  test('fresh TURN is installed before normal-mode gathering', () async {
    final turn = CallIceServer(
      urls: const <String>['turn:relay.invalid:3478?transport=udp'],
      username: 'ephemeral-user',
      credential: 'ephemeral-password',
      expiresAt: _now.add(const Duration(minutes: 5)),
    );
    CallConnectionConfiguration? startedWith;
    final preparer = CallAudioNegotiationPreparer(
      startAudio: ({required locallyAccepted, required configuration}) async {
        startedWith = configuration;
        return _result(CallAudioStartStatus.started);
      },
      readInitialIceServers: (_) async => <CallIceServer>[turn],
      clock: () => _now,
      requireTurnServer: true,
    );

    await preparer.prepareLocallyAcceptedMedia(
      snapshot: _snapshot(acceptedAt: _now),
      configuration: _configuration,
    );

    expect(startedWith?.transportPolicy, CallTransportPolicy.all);
    expect(startedWith?.iceServers, <CallIceServer>[turn]);
  });

  test('always-relay fails closed before capture without fresh TURN', () async {
    var starts = 0;
    final preparer = CallAudioNegotiationPreparer(
      startAudio: ({required locallyAccepted, required configuration}) async {
        starts++;
        return _result(CallAudioStartStatus.started);
      },
      readInitialIceServers: (_) async => const <CallIceServer>[],
      clock: () => _now,
    );

    await expectLater(
      () => preparer.prepareLocallyAcceptedMedia(
        snapshot: _snapshot(acceptedAt: _now),
        configuration: const CallConnectionConfiguration(
          transportPolicy: CallTransportPolicy.relayOnly,
          receiveAudio: true,
          receiveVideo: false,
          captureAudio: true,
          captureVideo: false,
        ),
      ),
      throwsA(
        isA<CallNegotiationPortException>().having(
          (error) => error.code,
          'code',
          CallNegotiationPortErrorCode.iceServersUnavailable,
        ),
      ),
    );
    expect(starts, 0);
  });
}
