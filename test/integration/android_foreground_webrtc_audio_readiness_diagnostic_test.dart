import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_foreground_webrtc_audio_canonical_stack.dart';

void main() {
  test('reports the first exact invariant missing from a sampled snapshot', () {
    final cases = <String, CallConnectionSnapshot>{
      'iceConnectionNotReady': _snapshot(state: CallConnectionState.connecting),
      'selectedPairNotSucceeded': _snapshot(selectedPairSucceeded: false),
      'selectedPairNotNominated': _snapshot(selectedPairNominated: false),
      'dtlsNotReady': _snapshot(dtlsReady: false),
      'audioSessionInactive': _snapshot(audioSessionActive: false),
      'localAudioSenderMissing': _snapshot(localAudioSenderAttached: false),
      'localAudioTrackNotLive': _snapshot(localAudioTrackLive: false),
      'remoteAudioReceiverMissing': _snapshot(
        remoteAudioReceiverAttached: false,
      ),
      'remoteAudioTrackNotLive': _snapshot(remoteAudioTrackLive: false),
      'ready': _snapshot(),
    };

    expect(
      androidForegroundWebRtcMediaReadinessFailure(
        null,
        permissionGranted: true,
      ),
      'notCaptured',
    );
    expect(
      androidForegroundWebRtcMediaReadinessFailure(
        _snapshot(),
        permissionGranted: false,
      ),
      'permissionNotGranted',
    );
    for (final entry in cases.entries) {
      expect(
        androidForegroundWebRtcMediaReadinessFailure(
          entry.value,
          permissionGranted: true,
        ),
        entry.key,
        reason: entry.key,
      );
    }
  });
}

CallConnectionSnapshot _snapshot({
  CallConnectionState state = CallConnectionState.connected,
  bool selectedPairSucceeded = true,
  bool selectedPairNominated = true,
  bool dtlsReady = true,
  bool audioSessionActive = true,
  bool localAudioSenderAttached = true,
  bool localAudioTrackLive = true,
  bool remoteAudioReceiverAttached = true,
  bool remoteAudioTrackLive = true,
}) => CallConnectionSnapshot(
  state: state,
  transportPolicy: CallTransportPolicy.all,
  transport: CallTransportClass.direct,
  quality: CallQualityBand.good,
  localAudioCaptureTrackCount: 1,
  localVideoCaptureTrackCount: 0,
  audioReceiveTransceiverCount: 1,
  videoTransceiverCount: 0,
  selectedPairSucceeded: selectedPairSucceeded,
  selectedPairNominated: selectedPairNominated,
  selectedRelayProtocol: CallRelayProtocol.notRelay,
  dtlsReady: dtlsReady,
  audioSessionActive: audioSessionActive,
  localAudioSenderAttached: localAudioSenderAttached,
  localAudioTrackLive: localAudioTrackLive,
  remoteAudioReceiverAttached: remoteAudioReceiverAttached,
  remoteAudioTrackLive: remoteAudioTrackLive,
);
