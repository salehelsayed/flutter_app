import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/infrastructure/bridge_call_ice_server_provider.dart';
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
  for (final policy in CallTransportPolicy.values) {
    test('credential timeout permits media only under all policy: $policy', () {
      fakeAsync((time) {
        final pending = Completer<Map<String, dynamic>>();
        final provider = BridgeCallIceServerProvider(
          bridge: _Bridge(),
          fetch: (_) => pending.future,
          clock: () => _now.add(time.elapsed),
        );
        final starts = <CallConnectionConfiguration>[];
        Object? failure;
        final preparer = CallAudioNegotiationPreparer(
          isCurrentCall: (id) => id == _callId,
          startAudio:
              ({required locallyAccepted, required configuration}) async {
                starts.add(configuration);
                return _result(CallAudioStartStatus.started);
              },
          readInitialIceServers: provider.read,
          clock: () => _now.add(time.elapsed),
        );
        unawaited(
          preparer
              .prepareLocallyAcceptedMedia(
                snapshot: _snapshot(acceptedAt: _now),
                configuration: CallConnectionConfiguration(
                  transportPolicy: policy,
                  receiveAudio: true,
                  receiveVideo: false,
                  captureAudio: true,
                  captureVideo: false,
                ),
              )
              .catchError((Object error) {
                failure = error;
              }),
        );
        time.flushMicrotasks();
        time.elapse(const Duration(seconds: 5));
        time.flushMicrotasks();
        if (policy == CallTransportPolicy.all) {
          expect(failure, isNull);
          expect(starts, hasLength(1));
          expect(starts.single.transportPolicy, policy);
        } else {
          expect(failure, isA<CallNegotiationPortException>());
          expect(starts, isEmpty);
        }
        pending.complete({
          'ok': false,
          'errorCode': 'TURN_CREDENTIALS_UNAVAILABLE',
        });
        time.flushMicrotasks();
        expect(starts, hasLength(policy == CallTransportPolicy.all ? 1 : 0));
      });
    });
  }

  test('normal mode does not swallow a rejected credential reader', () async {
    var starts = 0;
    final preparer = CallAudioNegotiationPreparer(
      isCurrentCall: (id) => id == _callId,
      startAudio: ({required locallyAccepted, required configuration}) async {
        starts++;
        return _result(CallAudioStartStatus.started);
      },
      readInitialIceServers: (_) async =>
          throw const CallNegotiationPortException(
            CallNegotiationPortErrorCode.iceServersUnavailable,
          ),
    );
    await expectLater(
      preparer.prepareLocallyAcceptedMedia(
        snapshot: _snapshot(acceptedAt: _now),
        configuration: _configuration,
      ),
      throwsA(isA<CallNegotiationPortException>()),
    );
    expect(starts, 0);
  });

  test(
    'forwards only reducer-proven local acceptance to audio start',
    () async {
      bool? observedAcceptance;
      final preparer = CallAudioNegotiationPreparer(
        isCurrentCall: (id) => id == _callId,
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
      isCurrentCall: (id) => id == _callId,
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
      isCurrentCall: (id) => id == _callId,
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
      isCurrentCall: (id) => id == _callId,
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
      isCurrentCall: (id) => id == _callId,
      startAudio: ({required locallyAccepted, required configuration}) async {
        startedWith = configuration;
        return _result(CallAudioStartStatus.started);
      },
      readInitialIceServers: (_) async => <CallIceServer>[turn],
      clock: () => _now,
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
      isCurrentCall: (id) => id == _callId,
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

final class _Bridge implements Bridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
