import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

CallVideoPresentation projection({
  CallMediaKind requested = CallMediaKind.video,
  CallMediaKind? accepted = CallMediaKind.video,
  CallMediaKind agreed = CallMediaKind.video,
  CallCameraState local = CallCameraState.off,
  CallCameraState remote = CallCameraState.off,
  bool reconnecting = false,
  bool busy = false,
  CallMediaKind? switchingTo,
  String? incoming,
  String? outgoing,
}) => CallVideoPresentation.project(
  videoEnabled: true,
  wireVersion: CallWireVersion.v2,
  requestedMedia: requested,
  acceptedMedia: accepted,
  agreedMedia: agreed,
  localCamera: local,
  remoteCamera: remote,
  isConnected: true,
  isReconnecting: reconnecting,
  switchingTo: switchingTo,
  videoActionPending: busy,
  incomingUpgradeId: incoming,
  outgoingUpgradeId: outgoing,
  mayRequestVideo: true,
  mayTurnCameraOn: true,
  maySwitchCamera: true,
);

void main() {
  test('U6 causal default gate keeps all video actions unavailable', () {
    const view = CallVideoPresentation.project(
      wireVersion: CallWireVersion.v2,
      requestedMedia: CallMediaKind.video,
      acceptedMedia: CallMediaKind.video,
      agreedMedia: CallMediaKind.video,
      isConnected: true,
      mayRequestVideo: true,
      mayTurnCameraOn: true,
      maySwitchCamera: true,
    );
    expect(view.isVisible, isFalse);
    expect(view.actions, isEmpty);
    for (final action in CallVideoAction.values) {
      expect(view.isAvailable(action), isFalse);
      expect(view.intentFor(action), isNull);
    }
  });

  test('U6 causal request availability requires an explicit click', () {
    final view = projection(
      requested: CallMediaKind.audio,
      accepted: CallMediaKind.audio,
      agreed: CallMediaKind.audio,
    );
    expect(view.isVisible, isTrue);
    expect(view.status, CallVideoStatus.audioOnly);
    expect(view.isAvailable(CallVideoAction.requestVideo), isTrue);
    expect(
      view.intentFor(CallVideoAction.requestVideo)!.action,
      CallVideoAction.requestVideo,
    );
    expect(view.isAvailable(CallVideoAction.turnCameraOn), isFalse);
    expect(view.acceptedMedia, CallMediaKind.audio);
    expect(view.agreedMedia, CallMediaKind.audio);
    expect(view.localCamera, CallCameraState.off);
  });

  test('v1 cannot expose video even with video hints and owner flags', () {
    const view = CallVideoPresentation.project(
      videoEnabled: true,
      requestedMedia: CallMediaKind.video,
      acceptedMedia: CallMediaKind.video,
      agreedMedia: CallMediaKind.video,
      localCamera: CallCameraState.on,
      isConnected: true,
      mayTurnCameraOn: true,
    );
    expect(view.isVisible, isFalse);
    expect(view.actions, isEmpty);
    expect(view.intentFor(CallVideoAction.turnCameraOff), isNull);
  });

  test('owner availability flags default closed independently of v2', () {
    const view = CallVideoPresentation.project(
      videoEnabled: true,
      wireVersion: CallWireVersion.v2,
      acceptedMedia: CallMediaKind.audio,
      isConnected: true,
    );
    expect(view.isVisible, isTrue);
    expect(view.isAvailable(CallVideoAction.requestVideo), isFalse);
    expect(view.isAvailable(CallVideoAction.turnCameraOn), isFalse);
    expect(view.isAvailable(CallVideoAction.switchCamera), isFalse);
  });

  test('unanswered video request is not a video agreement', () {
    final view = projection(accepted: null, agreed: CallMediaKind.audio);
    expect(view.status, CallVideoStatus.videoRequested);
    expect(view.acceptedMedia, isNull);
    expect(view.isAvailable(CallVideoAction.turnCameraOn), isFalse);
    expect(view.isAvailable(CallVideoAction.requestVideo), isFalse);
    expect(view.isAvailable(CallVideoAction.useAudioOnly), isTrue);
  });

  test('video requested but answered audio stays distinct from camera off', () {
    final audio = projection(
      accepted: CallMediaKind.audio,
      agreed: CallMediaKind.audio,
    );
    final cameraOff = projection();
    expect(audio.isInitialAudioOnlyAnswer, isTrue);
    expect(audio.status, CallVideoStatus.audioOnly);
    expect(audio.isAvailable(CallVideoAction.turnCameraOn), isFalse);
    expect(cameraOff.isInitialAudioOnlyAnswer, isFalse);
    expect(cameraOff.status, CallVideoStatus.video);
    expect(cameraOff.localCamera, CallCameraState.off);
    expect(cameraOff.isAvailable(CallVideoAction.turnCameraOn), isTrue);
  });

  test('later agreed video does not rewrite the initial audio agreement', () {
    final view = projection(
      requested: CallMediaKind.audio,
      accepted: CallMediaKind.audio,
    );
    expect(view.requestedMedia, CallMediaKind.audio);
    expect(view.acceptedMedia, CallMediaKind.audio);
    expect(view.agreedMedia, CallMediaKind.video);
    expect(view.status, CallVideoStatus.video);
  });

  test('local and remote camera facts remain independent', () {
    for (final local in CallCameraState.values) {
      for (final remote in CallCameraState.values) {
        final view = projection(local: local, remote: remote);
        expect(view.localCamera, local);
        expect(view.remoteCamera, remote);
        expect(view.status, CallVideoStatus.video);
        expect(
          view.isAvailable(CallVideoAction.switchCamera),
          local == CallCameraState.on,
        );
      }
    }
  });

  test('outgoing request waits and cannot turn a camera on', () {
    final view = projection(
      accepted: CallMediaKind.audio,
      agreed: CallMediaKind.audio,
      outgoing: 'outgoing-current',
    );
    expect(view.status, CallVideoStatus.outgoingUpgrade);
    expect(view.isAvailable(CallVideoAction.requestVideo), isFalse);
    expect(view.isAvailable(CallVideoAction.turnCameraOn), isFalse);
    expect(
      view.intentFor(CallVideoAction.cancelUpgrade)!.upgradeId,
      'outgoing-current',
    );
    expect(view.isAvailable(CallVideoAction.useAudioOnly), isTrue);
  });

  test('winning incoming request needs its own explicit decision', () {
    final view = projection(
      accepted: CallMediaKind.audio,
      agreed: CallMediaKind.audio,
      incoming: 'incoming-current',
      outgoing: 'abandoned-outgoing',
    );
    expect(view.status, CallVideoStatus.incomingUpgrade);
    for (final action in [
      CallVideoAction.acceptUpgrade,
      CallVideoAction.declineUpgrade,
    ]) {
      expect(view.isAvailable(action), isTrue);
      expect(view.intentFor(action)!.upgradeId, 'incoming-current');
    }
    expect(view.isAvailable(CallVideoAction.cancelUpgrade), isFalse);
    expect(view.isAvailable(CallVideoAction.turnCameraOn), isFalse);
    expect(view.agreedMedia, CallMediaKind.audio);
  });

  test('sending a decision disables repeats but retains safe audio intent', () {
    final view = projection(
      accepted: CallMediaKind.audio,
      agreed: CallMediaKind.audio,
      incoming: 'incoming-current',
      busy: true,
    );
    expect(view.status, CallVideoStatus.incomingUpgrade);
    expect(view.isAvailable(CallVideoAction.acceptUpgrade), isFalse);
    expect(view.isAvailable(CallVideoAction.declineUpgrade), isFalse);
    expect(view.isAvailable(CallVideoAction.requestVideo), isFalse);
    expect(view.isAvailable(CallVideoAction.useAudioOnly), isTrue);
  });

  test('reconnect blocks unsafe work without delaying camera off or audio', () {
    final view = projection(local: CallCameraState.on, reconnecting: true);
    expect(view.status, CallVideoStatus.reconnecting);
    expect(view.isAvailable(CallVideoAction.switchCamera), isFalse);
    expect(view.isAvailable(CallVideoAction.turnCameraOn), isFalse);
    expect(view.isAvailable(CallVideoAction.turnCameraOff), isTrue);
    expect(view.isAvailable(CallVideoAction.useAudioOnly), isTrue);
  });

  for (final target in CallMediaKind.values) {
    test('switching to ${target.name} retains immediate safe controls', () {
      final view = projection(
        local: CallCameraState.paused,
        switchingTo: target,
        busy: true,
      );
      expect(
        view.status,
        target == CallMediaKind.video
            ? CallVideoStatus.switchingToVideo
            : CallVideoStatus.switchingToAudio,
      );
      expect(view.isAvailable(CallVideoAction.turnCameraOn), isFalse);
      expect(view.isAvailable(CallVideoAction.switchCamera), isFalse);
      expect(view.isAvailable(CallVideoAction.turnCameraOff), isTrue);
      expect(view.isAvailable(CallVideoAction.useAudioOnly), isTrue);
    });
  }

  test('blank request handles cannot expose a consent decision', () {
    final view = projection(
      accepted: CallMediaKind.audio,
      agreed: CallMediaKind.audio,
      incoming: '  ',
      outgoing: '',
    );
    expect(view.status, CallVideoStatus.audioOnly);
    expect(view.intentFor(CallVideoAction.acceptUpgrade), isNull);
    expect(view.intentFor(CallVideoAction.declineUpgrade), isNull);
    expect(view.intentFor(CallVideoAction.cancelUpgrade), isNull);
  });

  test('projected action collection cannot change action availability', () {
    final view = projection();
    expect(view.actions, contains(CallVideoAction.turnCameraOn));
    expect(() => view.actions.clear(), throwsUnsupportedError);
    expect(view.isAvailable(CallVideoAction.turnCameraOn), isTrue);
  });
}
