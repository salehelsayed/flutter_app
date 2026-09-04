import 'dart:async';

import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';
import 'call_audio_controller.dart';

/// Canonical call and audio truth exposed together to foreground presentation.
///
/// [session] is the reducer-owned snapshot itself. Presentation must not copy,
/// reinterpret, or transition it. [audio] is the latest engine-projected audio
/// state and is the only source of truth for foreground controls.
final class ForegroundCallProjection {
  const ForegroundCallProjection({required this.session, required this.audio});

  final CallSessionSnapshot session;
  final CallAudioControlState audio;
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
