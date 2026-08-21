import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Runs a self-healing startup backfill so that its failure can never abort the
/// deferred runtime start.
///
/// The group projection backfills are maintenance work: they re-run on every
/// launch, and a re-run over an already-populated projection is a near-zero-write
/// no-op. Nothing user-visible depends on them completing on THIS launch.
///
/// The deferred runtime start, by contrast, is what `StartupRouter._doStartP2P`
/// awaits before it calls `startP2PNode`. Letting a backfill error escape into
/// that await means the P2P node is never started at all, so the connection
/// badge renders "Offline" (`NodeState.badgeReadinessState` returns `offline`
/// only for `!isStarted`) until the app is relaunched.
///
/// That is exactly what happened on a fresh install: `loadIdentity()` clears the
/// group notification projection owner when there is no identity row, so the
/// sender-authority mirror threw `group notification projection owner is
/// unavailable` and bricked node start (device-reproduced 2026-08-21).
///
/// Failures are reported and skipped. This deliberately does NOT weaken the
/// `propagateError: true` contracts on the projection's authority
/// retire/replace paths — those still propagate to their own callers during
/// real group mutations. Only this startup backfill call site is non-fatal.
Future<void> runBestEffortStartupBackfill(
  String step,
  Future<void> Function() backfill,
) async {
  try {
    await backfill();
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RUNTIME_STARTUP_BACKFILL_SKIPPED',
      details: {
        'step': step,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      },
    );
  }
}
