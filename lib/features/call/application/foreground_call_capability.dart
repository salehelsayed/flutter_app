import 'dart:async';

import '../domain/call_id.dart';
import '../domain/call_audio_output_device.dart';
import '../domain/call_engine.dart' show CallVideoView;
import '../domain/call_media.dart' show CallMediaKind;
import '../domain/call_session_snapshot.dart';
import '../presentation/call_video_presentation.dart';
import 'call_audio_controller.dart';

/// Optional immutable video view issued by the canonical call/media owner.
///
/// [generation] is that owner's lifecycle token, independent of transport
/// reconnect counters. Presentation only returns it with a user intent.
final class ForegroundCallVideoProjection {
  const ForegroundCallVideoProjection({
    required this.generation,
    required this.presentation,
    this.localView,
    this.remoteView,
  });

  final int generation;
  final CallVideoPresentation presentation;

  /// Current opaque texture metadata, published by the canonical media owner.
  /// Null means no current view; presentation never owns a native renderer.
  final CallVideoView? localView;
  final CallVideoView? remoteView;
}

/// Canonical call and audio truth exposed together to foreground presentation.
///
/// [session] is the reducer-owned snapshot itself. Presentation must not copy,
/// reinterpret, or transition it. [audio] is the latest engine-projected audio
/// state and is the only source of truth for foreground controls.
final class ForegroundCallProjection {
  const ForegroundCallProjection({
    required this.session,
    required this.audio,
    this.video,
  });

  final CallSessionSnapshot session;
  final CallAudioControlState audio;
  final ForegroundCallVideoProjection? video;
}

/// Detail-free outcome for every foreground call command.
enum ForegroundCallActionStatus { applied, unavailable, failed }

/// Fixed-shape, redacted command result exposed to presentation.
final class ForegroundCallActionResult {
  const ForegroundCallActionResult(this.status);

  static const applied = ForegroundCallActionResult(
    ForegroundCallActionStatus.applied,
  );
  static const unavailable = ForegroundCallActionResult(
    ForegroundCallActionStatus.unavailable,
  );
  static const failed = ForegroundCallActionResult(
    ForegroundCallActionStatus.failed,
  );

  final ForegroundCallActionStatus status;

  @override
  String toString() => 'ForegroundCallActionResult(status: ${status.name})';
}

/// Stable presentation boundary for the one process-owned foreground call.
///
/// A null projection means there is no foreground call surface. Every command
/// is scoped to the call that the user can currently see, so a stale action can
/// be refused behind this boundary without exposing signaling details.
abstract interface class ForegroundCallCapability {
  ForegroundCallProjection? get current;

  Stream<ForegroundCallProjection?> get changes;

  Future<ForegroundCallActionResult> answer(CallId callId);

  Future<ForegroundCallActionResult> decline(CallId callId);

  Future<ForegroundCallActionResult> cancel(CallId callId);

  Future<ForegroundCallActionResult> end(CallId callId);

  Future<ForegroundCallActionResult> setMuted(CallId callId, bool muted);

  /// Enables the speaker route, or selects the system-default route when
  /// [enabled] is false.
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId callId,
    bool enabled,
  );
}

/// Optional video commands; the canonical owner revalidates every binding.
///
/// A view's intent is neither camera permission nor a media state transition.
/// The owner checks the active call, generation, current action availability
/// and exact upgrade identity before applying any effect.
abstract interface class ForegroundCallVideoCapability {
  Future<ForegroundCallActionResult> applyVideoIntent(
    CallId callId, {
    required int generation,
    required CallVideoIntent intent,
  });
}

/// Optional explicit incoming-media choice, separate from ordinary audio Answer.
///
/// The root revalidates the incoming offer, call and generation, then owns
/// permission and media effects. This choice alone never grants camera capture.
/// Existing/native [ForegroundCallCapability.answer] remains audio-only.
abstract interface class ForegroundCallMediaAnswerCapability {
  Future<ForegroundCallActionResult> answerWithMedia(
    CallId callId, {
    required int generation,
    required CallMediaKind acceptedMedia,
  });
}

/// Optional transient inventory; the canonical call/audio owners do the work.
abstract interface class ForegroundCallAudioPickerCapability {
  Future<List<CallAudioOutputDevice>> outputDevices(CallId callId);
  Future<ForegroundCallActionResult> selectOutputDevice(
    CallId callId,
    String id,
  );
}
