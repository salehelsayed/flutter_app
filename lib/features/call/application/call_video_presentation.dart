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

  bool get isVisible => videoEnabled && wireVersion == CallWireVersion.v2;

  bool get isInitialAudioOnlyAnswer =>
      requestedMedia == CallMediaKind.video &&
      acceptedMedia == CallMediaKind.audio;

  CallVideoStatus get status {
    if (isReconnecting) return CallVideoStatus.reconnecting;
    if (switchingTo == CallMediaKind.video) {
      return CallVideoStatus.switchingToVideo;
    }
    if (switchingTo == CallMediaKind.audio) {
      return CallVideoStatus.switchingToAudio;
    }
    if (_hasIncoming) return CallVideoStatus.incomingUpgrade;
    if (_hasOutgoing) return CallVideoStatus.outgoingUpgrade;
    if (acceptedMedia == null) {
      return requestedMedia == CallMediaKind.video
          ? CallVideoStatus.videoRequested
          : CallVideoStatus.audioOnly;
    }
    return agreedMedia == CallMediaKind.video
        ? CallVideoStatus.video
        : CallVideoStatus.audioOnly;
  }

  List<CallVideoAction> get actions {
    if (!isVisible) return const [];
    final result = <CallVideoAction>[];
    if (acceptedMedia != null && agreedMedia == CallMediaKind.video) {
      if (localCamera != CallCameraState.on) {
        result.add(CallVideoAction.turnCameraOn);
      }
      if (localCamera != CallCameraState.off) {
        result.add(CallVideoAction.turnCameraOff);
      }
      result.add(CallVideoAction.switchCamera);
    } else if (_hasIncoming) {
      result.addAll([
        CallVideoAction.acceptUpgrade,
        CallVideoAction.declineUpgrade,
      ]);
    } else if (_hasOutgoing) {
      result.add(CallVideoAction.cancelUpgrade);
    } else if (acceptedMedia != null) {
      result.add(CallVideoAction.requestVideo);
    }
    if (localCamera != CallCameraState.off &&
        !result.contains(CallVideoAction.turnCameraOff)) {
      result.add(CallVideoAction.turnCameraOff);
    }
    if (_hasVideoActivity) result.add(CallVideoAction.useAudioOnly);
    return List.unmodifiable(result);
  }

  bool isAvailable(CallVideoAction action) {
    if (!isVisible) return false;
    return switch (action) {
      CallVideoAction.requestVideo =>
        _readyForStart && agreedMedia == CallMediaKind.audio && mayRequestVideo,
      CallVideoAction.acceptUpgrade =>
        _stable && agreedMedia == CallMediaKind.audio && _hasIncoming,
      CallVideoAction.declineUpgrade =>
        acceptedMedia != null &&
            agreedMedia == CallMediaKind.audio &&
            _hasIncoming &&
            !videoActionPending,
      CallVideoAction.cancelUpgrade =>
        acceptedMedia != null &&
            agreedMedia == CallMediaKind.audio &&
            _hasOutgoing &&
            !_hasIncoming &&
            !videoActionPending,
      CallVideoAction.turnCameraOn =>
        _readyForStart &&
            agreedMedia == CallMediaKind.video &&
            localCamera != CallCameraState.on &&
            mayTurnCameraOn,
      // Stopping local video is never held behind an optional negotiation.
      CallVideoAction.turnCameraOff => localCamera != CallCameraState.off,
      CallVideoAction.switchCamera =>
        _readyForStart &&
            agreedMedia == CallMediaKind.video &&
            localCamera == CallCameraState.on &&
            maySwitchCamera,
      CallVideoAction.useAudioOnly => _hasVideoActivity,
    };
  }

  CallVideoIntent? intentFor(CallVideoAction action) {
    if (!isAvailable(action)) return null;
    return CallVideoIntent(
      action,
      upgradeId: switch (action) {
        CallVideoAction.acceptUpgrade ||
        CallVideoAction.declineUpgrade => incomingUpgradeId,
        CallVideoAction.cancelUpgrade => outgoingUpgradeId,
        _ => null,
      },
    );
  }

  bool get _hasIncoming => incomingUpgradeId?.trim().isNotEmpty ?? false;
  bool get _hasOutgoing => outgoingUpgradeId?.trim().isNotEmpty ?? false;

  bool get _stable =>
      acceptedMedia != null &&
      isConnected &&
      !isReconnecting &&
      switchingTo == null &&
      !videoActionPending;

  bool get _readyForStart => _stable && !_hasIncoming && !_hasOutgoing;

  bool get _hasVideoActivity =>
      agreedMedia == CallMediaKind.video ||
      (acceptedMedia == null && requestedMedia == CallMediaKind.video) ||
      localCamera != CallCameraState.off ||
      remoteCamera != CallCameraState.off ||
      switchingTo == CallMediaKind.video ||
      _hasIncoming ||
      _hasOutgoing;
}
