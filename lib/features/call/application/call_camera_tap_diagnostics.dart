import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import 'call_video_presentation.dart';

enum CallCameraTapOutcome { accepted, pending, refused }

enum CallCameraTapReason {
  notReady,
  actionPending,
  staleOwner,
  ownerUnavailable,
  ownerChanged,
  permissionDenied,
  nativeLeaseRefused,
  captureRejected,
  actionStarted,
  completed,
  failed,
}

/// Pending describes existing camera work, never a queued capture or consent.
/// Only fixed enum values are emitted; diagnostics cannot change the action.
void reportCallCameraTap(
  CallVideoAction action,
  CallCameraTapOutcome outcome,
  CallCameraTapReason reason,
) {
  if (!kDebugMode ||
      !const {
        CallVideoAction.turnCameraOn,
        CallVideoAction.turnCameraOff,
        CallVideoAction.switchCamera,
      }.contains(action)) {
    return;
  }
  try {
    emitFlowEvent(
      layer: 'CALL_VIDEO',
      event: 'CALL_CAMERA_TAP',
      details: {
        'action': action.name,
        'outcome': outcome.name,
        'reason': reason.name,
      },
    );
  } catch (_) {
    // A logging observer must never grant, revoke or interrupt consent.
  }
}
