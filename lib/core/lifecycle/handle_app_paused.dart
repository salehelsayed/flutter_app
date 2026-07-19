import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/outbound_envelope_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';

/// Group sends younger than this may still be owned by an active background
/// upload/send task, so pause recovery leaves them alone.
const Duration kPausedGroupSendingRecoveryThreshold = Duration(minutes: 2);

// ── FDC-06: bounded pause-flush (ships ENABLED — productionized from the
//    FDC-S4 Option-A prototype) ───────────────────────────────────────────
// Spike that proved it feasible on a real device: the FDC-S4 iOS pause-flush
// feasibility spike (Network-Transport-libp2p / fast-direct-connection).
//
// On pause/hidden the "no network on pause" rule is NARROWED — not deleted —
// to: "no *unbounded* network and no *connection-holding*; a single bounded,
// bg-assertion-protected, inbox-store-only deposit of the newest in-flight
// sends is permitted." A deposited row is persisted as durable custody
// ('inboxed'/transport:'inbox', see handleAppPaused) — NOT left 'sending', so
// resume neither re-fails nor re-sends it.
//
// SHIP DECISION (FDC-06 NR-3 — "Ship ON, keep kill-switch"): ships ENABLED in
// a normal build. A dart-define kill-switch disables it WITHOUT a code change
// if a device regression appears:
//   --dart-define=FDC_PAUSE_FLUSH_DISABLE=1     (accepts 1/true/yes/on)
// The legacy measurement opt-out --dart-define=FDC_PAUSE_FLUSH=off
// (0/false/no/off) is also honoured. Device closure proof (T8) is still owed
// on a 2nd iOS major + an N>=3 burst (plan 170) — deferred, not waived.
//
// Any truthy/falsy spelling is accepted so the runbook is forgiving;
// bool.fromEnvironment alone only honours the exact strings 'true'/'false'.
const String _fdcPauseFlushRaw = String.fromEnvironment('FDC_PAUSE_FLUSH');
const String _fdcPauseFlushDisableRaw = String.fromEnvironment(
  'FDC_PAUSE_FLUSH_DISABLE',
);

/// Explicit opt-IN spelling for FDC_PAUSE_FLUSH (also arms the FDC-S4
/// grant-probe below — the device runbook's existing flag).
const bool _kFdcPauseFlushExplicitOn =
    _fdcPauseFlushRaw == '1' ||
    _fdcPauseFlushRaw == 'true' ||
    _fdcPauseFlushRaw == 'yes' ||
    _fdcPauseFlushRaw == 'on';

/// Explicit opt-OUT spelling for FDC_PAUSE_FLUSH (measurement runbook).
const bool _kFdcPauseFlushExplicitOff =
    _fdcPauseFlushRaw == '0' ||
    _fdcPauseFlushRaw == 'false' ||
    _fdcPauseFlushRaw == 'no' ||
    _fdcPauseFlushRaw == 'off';

/// Kill-switch: --dart-define=FDC_PAUSE_FLUSH_DISABLE=1 (1/true/yes/on).
const bool _kFdcPauseFlushKillSwitch =
    _fdcPauseFlushDisableRaw == '1' ||
    _fdcPauseFlushDisableRaw == 'true' ||
    _fdcPauseFlushDisableRaw == 'yes' ||
    _fdcPauseFlushDisableRaw == 'on';

/// FDC-06: the bounded pause-flush ships ON by default; either kill-switch
/// (`FDC_PAUSE_FLUSH_DISABLE=1` or `FDC_PAUSE_FLUSH=off`) turns it off.
const bool kFdcPauseFlushEnabled =
    !_kFdcPauseFlushKillSwitch && !_kFdcPauseFlushExplicitOff;

/// FDC-S4 grant-probe gate (measurement builds ONLY — default OFF). The probe
/// takes + releases a ~1.5s background assertion on every pause, so it must
/// NEVER fire in a normal production build (decoupled from the ship flag in
/// FDC-06). Kept until T8 closes on a 2nd iOS major (the device RESULTS parser
/// greps APP_LIFECYCLE_PAUSE_GRANT_PROBE). Arm it with the device runbook's
/// existing --dart-define=FDC_PAUSE_FLUSH=1.
const bool kFdcPauseGrantProbeEnabled = _kFdcPauseFlushExplicitOn;

/// Max in-flight `sending` rows the pause-flush deposits (newest-first). Rows
/// beyond the cap keep today's `sending → failed` + resume-retry behaviour.
/// Planned-against default; confirm from the device 95th-percentile of
/// `getSendingOutgoingMessages().length` at pause (spike Exit Gate 2).
const int kPauseFlushCap = 5;

/// Per-message inbox-store budget (reuses `storeInInbox`'s `timeoutMs`).
const Duration kPauseFlushPerMessageBudget = Duration(seconds: 3);

/// Overall flush ceiling — the loop stops here even if rows remain, leaving
/// slack under the measured ~25–30s `beginBackgroundTask` grant for the OS to
/// persist + the expiration handler to fire. Protects against a hung
/// `storeInInbox` on a degraded network.
const Duration kPauseFlushOverallCeiling = Duration(seconds: 8);

/// Required measured `backgroundTimeRemaining` grant (Decision Criterion 1):
/// the OS must routinely grant at least this much after `bgBegin` for the
/// ceiling above to be safe. Device-confirmed, not assumed (spike Method 1).
const int kPauseFlushRequiredGrantMs = 25000;

/// FDC-S4 measurement scaffolding (flag-gated; measurement builds only — NOT
/// part of the shipping flush, FDC-06 drops it). On every pause it takes and
/// immediately releases a background assertion so the native
/// `BG_TASK_GRANTED backgroundTimeRemainingSec` log (GoBridge.swift) reports the
/// REAL per-device/per-OS grant during the background transition — without
/// needing any in-flight sends, account, or peer. This is the cheapest way to
/// satisfy spike Method step 1 / Decision Criterion 1 (grant >= ~25s on >=2 iOS
/// versions): just launch + background. No-op off iOS (callBgBegin -> null).
Future<void> probePauseBackgroundGrant(Bridge bridge) async {
  // Two reads, both on the Flutter [FLOW] channel (which streams during real
  // suspension; native os_log buffers):
  //
  // (1) IMMEDIATE — read right at didEnterBackground. This is the value the
  //     flush itself would see at its assertion point; empirically the DBL_MAX
  //     "indeterminate-large" sentinel (iOS hasn't armed the countdown yet).
  final immediateSec = await callBgGrantProbe(bridge);
  emitFlowEvent(
    layer: 'FL',
    event: 'APP_LIFECYCLE_PAUSE_GRANT_PROBE',
    details: {
      'phase': 'immediate',
      'taskGranted': immediateSec != null,
      'grantSec': ?immediateSec,
    },
  );

  // (2) DELAYED — hold an assertion so the process keeps running ~1.5s into the
  //     background (the same mechanism the interactive send path relies on), by
  //     which point iOS has armed the FINITE countdown, then read it. This is
  //     the precise grant the spike's Decision Criterion 1 wants.
  final taskId = await callBgBegin(bridge);
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final delayedSec = await callBgTimeRemaining(bridge);
  emitFlowEvent(
    layer: 'FL',
    event: 'APP_LIFECYCLE_PAUSE_GRANT_PROBE',
    details: {
      'phase': 'delayed',
      'delayedMs': 1500,
      'taskGranted': taskId != null,
      'grantSec': ?delayedSec,
    },
  );
  await callBgEnd(bridge, taskId);
}

/// Result of the pause handler.
class AppPausedResult {
  final int transitionedCount;
  final int groupTransitionedCount;

  /// FDC-S4: number of in-flight `sending` rows whose wire envelope was
  /// ACCEPTED by the durable inbox during the bounded pause-flush. These rows
  /// are left in custody (NOT counted in [transitionedCount]). Always 0 when
  /// the pause-flush is disabled.
  final int flushDepositedCount;

  const AppPausedResult({
    required this.transitionedCount,
    required this.groupTransitionedCount,
    this.flushDepositedCount = 0,
  });
}

/// Handles app pause lifecycle cleanup.
///
/// Transitions in-flight 'sending' messages to 'failed' so they can be
/// retried on resume. By default does LOCAL DB work only — no network calls,
/// no P2PService interaction.
///
/// FDC-S4: the "no network on pause" rule is NARROWED (not deleted) when the
/// pause-flush is enabled ([enablePauseFlush] + [p2pService]/[bridge] provided):
/// a single bounded, background-assertion-protected, inbox-store-only deposit of
/// the newest in-flight sends is permitted — no *unbounded* network and no
/// *connection-holding*. A row whose deposit is accepted is left in custody and
/// is NOT marked failed. OFF by default → the legacy local-DB-only path is
/// byte-for-byte unchanged. FDC-06 owns finalizing this.
///
/// Returns [AppPausedResult] with the count of transitioned (and, when the
/// flush ran, deposited) messages. Catches all errors so callers never see
/// exceptions.
Future<AppPausedResult> handleAppPaused({
  required MessageRepository messageRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  GroupMessageRepository? groupMsgRepo,
  // ── FDC-S4 pause-flush (Option A prototype) ──
  // Inert unless [enablePauseFlush] is true AND both network deps are provided.
  // When inert, every line below behaves exactly as the legacy local-DB-only
  // handler (no `callBgBegin`, no `storeInInbox`, all rows marked `failed`).
  bool enablePauseFlush = false,
  P2PService? p2pService,
  Bridge? bridge,
  int flushCap = kPauseFlushCap,
  Duration perMessageBudget = kPauseFlushPerMessageBudget,
  Duration overallCeiling = kPauseFlushOverallCeiling,
  // Test seam: virtual clock (ms) for deterministic ceiling tests; defaults to
  // the wall clock in production.
  int Function()? nowMs,
}) async {
  if (kDebugMode) {
    debugPrint('[PAUSE] ====== APP PAUSE BEGIN ======');
  }

  emitFlowEvent(layer: 'FL', event: 'APP_LIFECYCLE_PAUSE_BEGIN', details: {});

  try {
    // Step 1: Find all in-flight sending messages
    final allSendingMessages = await messageRepo.getSendingOutgoingMessages();
    final pendingUploadMessageIds = mediaAttachmentRepo == null
        ? const <String>{}
        : await _loadDirectPendingUploadMessageIds(
            mediaAttachmentRepo,
            allSendingMessages.map((message) => message.id).toList(),
          );
    final sendingMessages = allSendingMessages
        .where((message) => !pendingUploadMessageIds.contains(message.id))
        .toList(growable: false);
    var transitionedCount = 0;
    var flushDepositedCount = 0;

    if (sendingMessages.isEmpty) {
      if (kDebugMode) {
        debugPrint('[PAUSE] No sending messages found — nothing to transition');
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_PAUSE_NO_SENDING_MESSAGES',
        details: {},
      );
    } else {
      if (kDebugMode) {
        debugPrint('[PAUSE] Found ${sendingMessages.length} sending messages');
      }

      // FDC-S4 (Option A prototype): under a background assertion, deposit the
      // newest in-flight sends into the durable inbox BEFORE marking them
      // failed. Inert (returns no ids) unless explicitly enabled, so the legacy
      // mark-failed-all behaviour below is unchanged by default. A row whose
      // deposit is ACCEPTED is left in custody and skipped in the loop below.
      final flushOutcome = await _pauseFlushInFlightSends(
        messages: sendingMessages,
        enable: enablePauseFlush,
        p2pService: p2pService,
        bridge: bridge,
        cap: flushCap,
        perMessageBudget: perMessageBudget,
        overallCeiling: overallCeiling,
        nowMs: nowMs ?? _wallClockMs,
      );
      flushDepositedCount = flushOutcome.depositedIds.length;

      // Step 2: Transition each NON-deposited sending message to failed.
      for (final msg in sendingMessages) {
        if (flushOutcome.depositedIds.contains(msg.id)) {
          // FDC-06 (NR-1): an ACCEPTED deposit is durable custody — persist it
          // as 'inboxed'/transport:'inbox' (mirror
          // retry_unacked_messages_use_case.dart:98) so it is NOT left
          // 'sending'. Resume's recoverStuckSendingMessages + retry_failed then
          // leave it alone (no re-fail, no re-send), and a double `_onPaused`
          // (hidden+paused) re-deposits nothing — the row has left the
          // `status='sending'` query.
          try {
            await messageRepo.saveMessage(
              normalizeOutgoingDeleteTombstoneVisibility(
                msg.copyWith(status: 'inboxed', transport: 'inbox'),
              ),
            );
          } catch (e) {
            // Non-fatal: the deposit already landed in relay custody. A failed
            // local status write leaves the row 'sending' (resume re-fails +
            // retries; the relay dedups by messageId). Do not abort the batch.
            emitFlowEvent(
              layer: 'FL',
              event: 'APP_LIFECYCLE_PAUSE_FLUSH_CUSTODY_ERROR',
              details: {'id': _shortId(msg.id), 'error': e.toString()},
            );
          }
          // Deposited to the durable inbox under custody — must NOT be marked
          // failed: it is in fact in flight to the recipient via the relay.
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_PAUSE_FLUSH_IN_CUSTODY',
            details: {'id': _shortId(msg.id)},
          );
          continue;
        }
        try {
          final updated = await messageRepo.conditionalTransitionStatus(
            msg.id,
            fromStatus: 'sending',
            toStatus: 'failed',
          );
          if (updated > 0) transitionedCount++;
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_PAUSE_TRANSITION',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
              'hasWireEnvelope': msg.wireEnvelope != null,
            },
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_PAUSE_TRANSITION_ERROR',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
              'error': e.toString(),
            },
          );
          // Continue to next message — do not abort batch on single failure.
        }
      }
    }

    var groupTransitionedCount = 0;
    if (groupMsgRepo != null) {
      try {
        groupTransitionedCount = await groupMsgRepo.recoverStuckSendingMessages(
          olderThan: kPausedGroupSendingRecoveryThreshold,
        );
        if (kDebugMode) {
          debugPrint(
            '[PAUSE] Group stale sending recovery complete '
            'recovered=$groupTransitionedCount',
          );
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'APP_LIFECYCLE_PAUSE_GROUP_TRANSITION',
          details: {
            'transitionedCount': groupTransitionedCount,
            'olderThanSeconds': kPausedGroupSendingRecoveryThreshold.inSeconds,
          },
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PAUSE] Group stale sending recovery ERROR: $e');
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'APP_LIFECYCLE_PAUSE_GROUP_TRANSITION_ERROR',
          details: {'error': e.toString()},
        );
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[PAUSE] ====== APP PAUSE COMPLETE ====== '
        'transitioned=$transitionedCount '
        'groupTransitioned=$groupTransitionedCount',
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_PAUSE_COMPLETE',
      details: {
        'transitionedCount': transitionedCount,
        'groupTransitionedCount': groupTransitionedCount,
      },
    );

    return AppPausedResult(
      transitionedCount: transitionedCount,
      groupTransitionedCount: groupTransitionedCount,
      flushDepositedCount: flushDepositedCount,
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[PAUSE] ====== APP PAUSE ERROR ====== $e');
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_PAUSE_ERROR',
      details: {'error': e.toString()},
    );
    return const AppPausedResult(
      transitionedCount: 0,
      groupTransitionedCount: 0,
    );
  }
}

/// Loads exact direct-lane attachment ownership for every supplied parent.
///
/// This is deliberately independent from the 50-row retry page. Chunks stay
/// below SQLite's bind-variable ceiling while covering arbitrarily large
/// pause batches (including the 51-parent regression boundary).
Future<Set<String>> _loadDirectPendingUploadMessageIds(
  MediaAttachmentRepository repository,
  List<String> messageIds,
) async {
  const batchSize = 400;
  final pending = <String>{};
  for (var start = 0; start < messageIds.length; start += batchSize) {
    final end = start + batchSize < messageIds.length
        ? start + batchSize
        : messageIds.length;
    final attachments = await repository.getAttachmentsForMessages(
      messageIds.sublist(start, end),
      owner: MediaOwnerLane.direct,
    );
    for (final entry in attachments.entries) {
      if (entry.value.any(
        (attachment) => attachment.downloadStatus == 'upload_pending',
      )) {
        pending.add(entry.key);
      }
    }
  }
  return pending;
}

/// Outcome of the FDC-S4 pause-flush: the message ids whose wire envelope was
/// ACCEPTED by the durable inbox, and which are therefore in custody (left
/// untouched, NOT marked failed by [handleAppPaused]).
class _PauseFlushOutcome {
  final Set<String> depositedIds;
  const _PauseFlushOutcome(this.depositedIds);
  static const empty = _PauseFlushOutcome(<String>{});
}

String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

/// FDC-S4 Option-A prototype: a bounded, store-and-exit inbox flush of the
/// in-flight `sending` rows on the iOS pause transition.
///
/// 1. Acquires the EXISTING `beginBackgroundTask` assertion (`callBgBegin`) —
///    the proven, production send-path mechanism — BEFORE any network await.
/// 2. Deposits the newest-first rows (each already carries `wireEnvelope`) into
///    the durable relay inbox via `storeInInbox`, bounded by a per-message
///    budget AND an overall ceiling (the loop stops at the ceiling even if rows
///    remain). No dial, no live race, no held connection. The relay dedupes by
///    messageId, so a deposit that races the original live send is harmless.
/// 3. Releases the assertion in a `finally` (`callBgEnd`), so an overrun can
///    only hit the benign native `BG_TASK_EXPIRED` path, never app termination.
///
/// Returns the ids that were accepted (in custody). Inert — returns
/// [_PauseFlushOutcome.empty] WITHOUT touching the bridge or network — unless
/// [enable] is true and both [p2pService] and [bridge] are provided, so the
/// caller's legacy mark-failed-all path is unchanged when the flush is off.
///
/// Scope: 1:1 sends only (the proposal's P0 "send one then close" case). Group
/// in-flight sends keep their separate staleness-recovery path; FDC-06 decides
/// whether to extend the flush to the group store path.
Future<_PauseFlushOutcome> _pauseFlushInFlightSends({
  required List<ConversationMessage> messages,
  required bool enable,
  required P2PService? p2pService,
  required Bridge? bridge,
  required int cap,
  required Duration perMessageBudget,
  required Duration overallCeiling,
  required int Function() nowMs,
}) async {
  if (!enable || p2pService == null || bridge == null) {
    return _PauseFlushOutcome.empty;
  }

  // Newest-first, only rows that carry a serialized, non-legacy envelope to
  // deposit. A legacy-unsafe envelope (a stale pre-format-change wire format a
  // `sending` row may still carry after an app update) is skipped here —
  // mirroring retry_unacked_messages_use_case:77 — and falls through to the
  // caller's mark-failed path, since the relay would reject/mis-handle it.
  final candidates =
      messages
          .where(
            (m) =>
                (m.wireEnvelope?.isNotEmpty ?? false) &&
                !isUnsafeLegacyOutboundEnvelope(m.wireEnvelope!),
          )
          .toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final capped = candidates.take(cap).toList(growable: false);

  if (capped.isEmpty) {
    // Nothing depositable — let the caller mark every row failed as before,
    // and never touch the bridge.
    return _PauseFlushOutcome.empty;
  }

  // Acquire the iOS background assertion BEFORE any network await. On Android
  // callBgBegin returns null (no native handler) and the flush simply runs
  // without an assertion — Android does not hard-suspend on pause the way iOS
  // does, so a short store-and-exit typically completes.
  final taskId = await callBgBegin(bridge);

  emitFlowEvent(
    layer: 'FL',
    event: 'APP_LIFECYCLE_PAUSE_FLUSH_BEGIN',
    details: {
      'taskGranted': taskId != null,
      'sendingCount': messages.length,
      'candidateCount': candidates.length,
      'cap': cap,
      'flushing': capped.length,
    },
  );

  final deposited = <String>{};
  final ceilingMs = overallCeiling.inMilliseconds;
  final perMsgMs = perMessageBudget.inMilliseconds;
  final startMs = nowMs();
  var expired = false;

  try {
    for (final msg in capped) {
      final elapsed = nowMs() - startMs;
      if (elapsed >= ceilingMs) {
        // Overall ceiling hit — stop even though rows remain. The remaining
        // rows fall through to today's `sending → failed` + resume retry.
        expired = true;
        break;
      }
      // Per-message budget, clamped so a single deposit can never push past the
      // overall ceiling.
      final remaining = ceilingMs - elapsed;
      final budget = perMsgMs < remaining ? perMsgMs : remaining;

      final before = nowMs();
      var ok = false;
      Object? error;
      try {
        ok = await p2pService.storeInInbox(
          msg.contactPeerId,
          msg.wireEnvelope!,
          timeoutMs: budget,
        );
      } catch (e) {
        error = e;
      }
      if (ok) deposited.add(msg.id);

      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_PAUSE_FLUSH_DEPOSIT',
        details: {
          'id': _shortId(msg.id),
          'ok': ok,
          'ms': nowMs() - before,
          if (error != null) 'error': error.toString(),
        },
      );
    }
  } finally {
    // Always release the assertion, even if a deposit threw mid-loop.
    await callBgEnd(bridge, taskId);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'APP_LIFECYCLE_PAUSE_FLUSH_COMPLETE',
    details: {
      'taskGranted': taskId != null,
      'deposited': deposited.length,
      'skipped': capped.length - deposited.length,
      'cappedOut': candidates.length - capped.length,
      'totalMs': nowMs() - startMs,
      'expired': expired,
    },
  );

  return _PauseFlushOutcome(deposited);
}
