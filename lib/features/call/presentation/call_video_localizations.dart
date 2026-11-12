import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/presentation/call_video_presentation.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Localized label formatters for U6's injected presentation-only API.
/// Construct from the current locale's [AppLocalizations] when binding a view.
final class CallVideoLocalizations {
  const CallVideoLocalizations(this._localizations);

  final AppLocalizations _localizations;

  String get controlsLabel => _localizations.call_video_controls_label;

  String statusLabel(CallVideoStatus status) => switch (status) {
    CallVideoStatus.videoRequested =>
      _localizations.call_video_status_video_requested,
    CallVideoStatus.audioOnly => _localizations.call_video_status_audio_only,
    CallVideoStatus.video => _localizations.call_video_status_video,
    CallVideoStatus.incomingUpgrade =>
      _localizations.call_video_status_incoming_upgrade,
    CallVideoStatus.outgoingUpgrade =>
      _localizations.call_video_status_outgoing_upgrade,
    CallVideoStatus.switchingToVideo =>
      _localizations.call_video_status_switching_to_video,
    CallVideoStatus.switchingToAudio =>
      _localizations.call_video_status_switching_to_audio,
    CallVideoStatus.reconnecting =>
      _localizations.call_video_status_reconnecting,
  };

  String localCameraLabel(CallCameraState state) => switch (state) {
    CallCameraState.on => _localizations.call_video_local_camera_on,
    CallCameraState.off => _localizations.call_video_local_camera_off,
    CallCameraState.paused => _localizations.call_video_local_camera_paused,
  };

  String remoteCameraLabel(CallCameraState state) => switch (state) {
    CallCameraState.on => _localizations.call_video_remote_camera_on,
    CallCameraState.off => _localizations.call_video_remote_camera_off,
    CallCameraState.paused => _localizations.call_video_remote_camera_paused,
  };

  String actionLabel(CallVideoAction action) => switch (action) {
    CallVideoAction.requestVideo =>
      _localizations.call_video_action_request_video,
    CallVideoAction.acceptUpgrade =>
      _localizations.call_video_action_accept_upgrade,
    CallVideoAction.declineUpgrade =>
      _localizations.call_video_action_decline_upgrade,
    CallVideoAction.cancelUpgrade =>
      _localizations.call_video_action_cancel_upgrade,
    CallVideoAction.turnCameraOn =>
      _localizations.call_video_action_turn_camera_on,
    CallVideoAction.turnCameraOff =>
      _localizations.call_video_action_turn_camera_off,
    CallVideoAction.switchCamera =>
      _localizations.call_video_action_switch_camera,
    CallVideoAction.useAudioOnly =>
      _localizations.call_video_action_use_audio_only,
  };
}
