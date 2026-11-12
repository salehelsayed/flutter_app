import 'package:flutter_app/features/call/domain/call_media.dart';

enum CallVideoStatus {
  videoRequested,
  audioOnly,
  video,
  incomingUpgrade,
  outgoingUpgrade,
  switchingToVideo,
  switchingToAudio,
  reconnecting,
}

enum CallVideoAction {
  requestVideo,
  acceptUpgrade,
  declineUpgrade,
  cancelUpgrade,
  turnCameraOn,
  turnCameraOff,
  switchCamera,
  useAudioOnly;

  String get identifier => switch (this) {
    requestVideo => 'call_video_request_video',
    acceptUpgrade => 'call_video_accept_upgrade',
    declineUpgrade => 'call_video_decline_upgrade',
    cancelUpgrade => 'call_video_cancel_upgrade',
    turnCameraOn => 'call_video_camera_on',
    turnCameraOff => 'call_video_camera_off',
    switchCamera => 'call_video_switch_camera',
    useAudioOnly => 'call_video_audio_only',
  };
}

/// A user intent, never permission, capture or an authenticated media response.
/// The binding owner must revalidate the call and this exact request identity.
final class CallVideoIntent {
  const CallVideoIntent(this.action, {this.upgradeId});

  final CallVideoAction action;
  final String? upgradeId;
}

/// Immutable display inputs supplied by the existing call/media owners.
///
/// Initial accepted media is history; [agreedMedia] is the current settled
/// agreement. Neither a request nor a camera hint changes that agreement.
/// This projection owns no permission, capture, signaling, timers or retries.
final class CallVideoPresentation {
  const CallVideoPresentation.project({
    this.videoEnabled = false,
    this.wireVersion = CallWireVersion.v1,
    this.requestedMedia = CallMediaKind.audio,
    this.acceptedMedia,
    this.agreedMedia = CallMediaKind.audio,
    this.localCamera = CallCameraState.off,
    this.remoteCamera = CallCameraState.off,
    this.isConnected = false,
    this.isReconnecting = false,
    this.switchingTo,
    this.videoActionPending = false,
    this.incomingUpgradeId,
    this.outgoingUpgradeId,
    this.mayRequestVideo = false,
    this.mayTurnCameraOn = false,
    this.maySwitchCamera = false,
  });

  final bool videoEnabled;
  final CallWireVersion wireVersion;
  final CallMediaKind requestedMedia;
  final CallMediaKind? acceptedMedia;
  final CallMediaKind agreedMedia;
  final CallCameraState localCamera;
  final CallCameraState remoteCamera;
  final bool isConnected;
  final bool isReconnecting;
  final CallMediaKind? switchingTo;
  final bool videoActionPending;
  final String? incomingUpgradeId;
  final String? outgoingUpgradeId;
  final bool mayRequestVideo;
  final bool mayTurnCameraOn;
  final bool maySwitchCamera;

  bool get isVisible => false;

  bool get isInitialAudioOnlyAnswer =>
      requestedMedia == CallMediaKind.video &&
      acceptedMedia == CallMediaKind.audio;

  CallVideoStatus get status => CallVideoStatus.audioOnly;

  List<CallVideoAction> get actions => const [];

  bool isAvailable(CallVideoAction action) => false;

  CallVideoIntent? intentFor(CallVideoAction action) => null;
}
