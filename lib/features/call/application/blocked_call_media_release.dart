import 'dart:async';

import '../domain/call_id.dart';
import 'call_cleanup_coordinator.dart';

/// Retries a terminal cleanup when its call media is finally released.
///
/// The `call_media` cleanup step is bounded, so a media close that is still
/// waiting (for example on an open microphone prompt) reports the terminal as
/// blocked and nothing reruns it. When that same close completes later, this
/// fires [onReleased] once per blocked episode, so the retained terminal is
/// released right away instead of refusing the next call.
///
/// The close and its report can arrive in either order: a close that
/// completes after the step's deadline but before the final report is
/// remembered until that report says whether the call is blocked on media.
final class BlockedCallMediaRelease {
  BlockedCallMediaRelease({required this.onReleased});

  final Future<void> Function(CallId callId) onReleased;

  /// Per call, the one signal still waiting for its counterpart.
  final Map<CallId, _Pending> _pending = <CallId, _Pending>{};

  /// Arms the call when [report] is blocked on its media close, or fires at
  /// once when that close already completed. Any other report for the call
  /// clears both.
  void observe(CallCleanupReport report) {
    final callId = report.callId;
    if (callId == null) return;
    final blockedOnMedia =
        !report.terminalAckReady &&
        report.failedStepNames.contains(callMediaCleanupStep);
    if (!blockedOnMedia) {
      _pending.remove(callId);
      return;
    }
    if (_pending.remove(callId) == _Pending.closed) {
      // Never inside the report call stack, which runs in the cleanup queue.
      unawaited(Future<void>.microtask(() => _release(callId)));
    } else {
      _pending[callId] = _Pending.blockedReport;
    }
  }

  /// Returns [close] unchanged, firing [onReleased] once if it completes while
  /// the call is armed. A completion before the report is remembered.
  Future<void> track(CallId callId, Future<void> close) {
    unawaited(
      close.then<void>((_) {
        if (_pending.remove(callId) == _Pending.blockedReport) {
          return _release(callId);
        }
        _pending[callId] = _Pending.closed;
      }, onError: (Object _) {}),
    );
    return close;
  }

  Future<void> _release(CallId callId) async {
    try {
      await onReleased(callId);
    } catch (_) {
      // The retained terminal stays bounded by the adapter's release window;
      // a failed early retry must not surface into cleanup.
    }
  }
}

/// Which half of the pair arrived first for a call: its blocked report, or
/// its successful media close.
enum _Pending { blockedReport, closed }

/// Name of the cleanup step that releases a call's media.
const callMediaCleanupStep = 'call_media';
