import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/legacy_push_transport_repair.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/legacy_group_secret_storage_scrub.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/core/notifications/headless_missed_call_notification.dart';
import 'package:flutter_app/features/push/application/notification_preview_copy.dart';
import 'package:flutter_app/features/call/application/missed_call_notifier.dart';
import 'package:flutter_app/features/call/application/headless_terminal_call_record.dart';
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/application/headless_call_decline_reply.dart';
import 'package:flutter_app/features/call/application/headless_call_ringing_reply.dart';
import 'package:flutter_app/features/call/application/incoming_call_pre_presentation_admission.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/infrastructure/bridge_call_direct_transport.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/headless_call_admission_entrypoint.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_endpoint_resolution.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/call/presentation/locked_call_projection.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path_provider/path_provider.dart';

// Fixed-shape, debug-only timing markers for cold Android call admission.
// Never include call handles, peer IDs, account bindings, or exception text.
Future<T> _traceHeadlessAdmissionStep<T>(
  String step,
  Future<T> Function() action,
) async {
  final timer = Stopwatch()..start();
  void record(String phase) {
    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_HEADLESS_ADMISSION_STEP',
        details: <String, Object?>{
          'step': step,
          'phase': phase,
          'elapsedMs': timer.elapsedMilliseconds,
        },
      );
    } catch (_) {
      // Diagnostics cannot change admission or cleanup behavior.
    }
  }

  record('begin');
  try {
    final result = await action();
    record('end');
    return result;
  } catch (_) {
    record('error');
    rethrow;
  }
}

final class HeadlessAuthenticatedMailboxEvent {
  const HeadlessAuthenticatedMailboxEvent({
    required this.event,
    required void Function() rollbackReplay,
    this.signal,
  }) : _rollbackReplay = rollbackReplay;

  final CallSignalType event;

  /// The decoded signal when the authenticator hands it over: the decline
  /// reply builds the caller's `reject` from the invite.
  final CallSignal? signal;
  final void Function() _rollbackReplay;

  void rollbackReplay() => _rollbackReplay();

  @override
  String toString() => 'HeadlessAuthenticatedMailboxEvent(redacted)';
}

typedef AuthenticateHeadlessMailboxEvent =
    Future<HeadlessAuthenticatedMailboxEvent> Function({
      required HeadlessCallAdmissionInvocation invocation,
      required CallMailboxEvent event,
    });

/// Sends the caller one `reject` for [invite] under [callHandle], the mailbox
/// handle the invite row was retrieved with (the caller keys its context by
/// it, not by the call id). Resolves true once the reject reached custody
/// (direct acceptance or mailbox store); never throws.
typedef HeadlessDeclineReplySender =
    Future<bool> Function(CallSignal invite, String callHandle);

typedef HeadlessRingingReplySender =
    Future<bool> Function(CallSignal invite, String callHandle);

/// 406: writes the local terminal call-history row for a call that ended with
/// no coordinator to project it.
///
/// A killed-app call never reaches `CallCoordinator`, so without this the chat
/// shows nothing at all for it — the row the conversation renders simply never
/// exists. [invite] is absent when the invite row was acknowledged by an
/// earlier run and only the terminal row remains.
typedef HeadlessCallHistoryRecorder =
    Future<void> Function({
      required CallSignal terminal,
      required CallEndReason reason,
      CallSignal? invite,
    });

/// Evaluates one exact-handle mailbox page without dispatching coordinator
/// events, acknowledging custody, or starting media. All provisional replay
/// reservations are rolled back so the foreground canonical owner can
/// authenticate and consume the same rows after native presentation.
final class MailboxProductionHeadlessCallAdmissionSession
    implements
        ProductionHeadlessCallAdmissionSession,
        HeadlessCallAdmissionDiagnosticSource,
        HeadlessCallAdmissionDisplaySource {
  MailboxProductionHeadlessCallAdmissionSession({
    required CallMailboxClient mailboxClient,
    required AuthenticateHeadlessMailboxEvent authenticateEvent,
    required Future<HeadlessCallAdmissionCleanup> Function() closeResources,
    HeadlessDeclineReplySender? declineReplySender,
    HeadlessRingingReplySender? ringingReplySender,
    HeadlessCallHistoryRecorder? historyRecorder,
    Future<HeadlessIncomingCallDisplay?> Function(CallSignal invite)?
    resolveDisplay,
    Duration displayTimeout = const Duration(seconds: 1),
  }) : _mailboxClient = mailboxClient,
       _authenticateEvent = authenticateEvent,
       _closeResources = closeResources,
       _declineReplySender = declineReplySender,
       _ringingReplySender = ringingReplySender,
       _historyRecorder = historyRecorder,
       _resolveDisplay = resolveDisplay,
       _displayTimeout = displayTimeout;

  final CallMailboxClient _mailboxClient;
  final AuthenticateHeadlessMailboxEvent _authenticateEvent;
  final HeadlessDeclineReplySender? _declineReplySender;
  final HeadlessRingingReplySender? _ringingReplySender;
  final HeadlessCallHistoryRecorder? _historyRecorder;
  final Future<HeadlessCallAdmissionCleanup> Function() _closeResources;
  final Future<HeadlessIncomingCallDisplay?> Function(CallSignal invite)?
  _resolveDisplay;
  final Duration _displayTimeout;
  @override
  HeadlessIncomingCallDisplay? get display => _display;
  HeadlessIncomingCallDisplay? _display;
  Future<HeadlessCallAdmissionDisposition>? _evaluation;
  Future<HeadlessCallAdmissionCleanup>? _cleanup;

  @override
  String? get diagnosticCause => _diagnosticCause;
  String? _diagnosticCause;

  @override
  Future<HeadlessCallAdmissionDisposition> evaluate(
    HeadlessCallAdmissionInvocation invocation,
  ) => _evaluation ??= switch (invocation.mode) {
    HeadlessCallAdmissionMode.admission => _evaluateOnce(invocation),
    HeadlessCallAdmissionMode.declineReply => _declineReplyOnce(invocation),
    HeadlessCallAdmissionMode.ringingReply => _ringingReplyOnce(invocation),
  };

  /// A second, short headless run begins only after native presentation was
  /// committed. It reauthenticates the still-unacked invite and checks that
  /// the exact native call is still ringing before sending the caller's reply.
  /// Foreground adoption retains custody of the invite and its own sequence.
  Future<HeadlessCallAdmissionDisposition> _ringingReplyOnce(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    CallMailboxRetrieveResult page;
    try {
      page = await _mailboxClient.retrieve(
        callHandle: invocation.callId,
        limit: BridgeCallMailboxClient.maxRetrieveEvents,
      );
    } catch (_) {
      return HeadlessCallAdmissionDisposition.deferred;
    }
    if (page.hasMore || page.events.isEmpty) {
      return HeadlessCallAdmissionDisposition.deferred;
    }
    final reservations = <HeadlessAuthenticatedMailboxEvent>[];
    CallSignal? invite;
    var terminal = false;
    try {
      for (final event in page.events) {
        final authenticated = await _authenticateEvent(
          invocation: HeadlessCallAdmissionInvocation(
            nonce: invocation.nonce,
            callId: invocation.callId,
            wakeHandle: invocation.wakeHandle,
            expiresAtMs: event.expiresAtMs,
            mode: invocation.mode,
          ),
          event: event,
        );
        reservations.add(authenticated);
        if (authenticated.event == CallSignalType.reject ||
            authenticated.event == CallSignalType.terminate) {
          terminal = true;
        } else if (authenticated.event == CallSignalType.invite) {
          if (invite != null) return HeadlessCallAdmissionDisposition.deferred;
          invite = authenticated.signal;
        } else {
          return HeadlessCallAdmissionDisposition.deferred;
        }
      }
      final sender = _ringingReplySender;
      if (terminal || invite == null || sender == null) {
        return HeadlessCallAdmissionDisposition.deferred;
      }
      return await sender(invite, invocation.callId)
          ? HeadlessCallAdmissionDisposition.terminal
          : HeadlessCallAdmissionDisposition.deferred;
    } catch (_) {
      return HeadlessCallAdmissionDisposition.deferred;
    } finally {
      for (final reservation in reservations.reversed) {
        reservation.rollbackReplay();
      }
    }
  }

  Future<HeadlessCallAdmissionDisposition> _evaluateOnce(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    late final CallMailboxRetrieveResult page;
    try {
      page = await _traceHeadlessAdmissionStep(
        'mailbox_retrieve',
        () => _mailboxClient.retrieve(
          callHandle: invocation.callId,
          limit: BridgeCallMailboxClient.maxRetrieveEvents,
        ),
      );
    } catch (_) {
      _diagnosticCause = 'transport_failed';
      return HeadlessCallAdmissionDisposition.deferred;
    }
    if (page.hasMore) {
      _diagnosticCause = 'unavailable';
      return HeadlessCallAdmissionDisposition.deferred;
    }
    if (page.events.isEmpty) {
      return HeadlessCallAdmissionDisposition.emptyOrAlreadyAcked;
    }
    // A page may hold rows from several wakes: this admission presents
    // without acknowledging, so the caller's terminate is stored behind the
    // still-unacked invite and arrives with its own wake. The wake binds only
    // the row it was issued for (equal expiry); every other row of the call
    // is authenticated against its own expiry, so a terminate can end the
    // ringing call and a stale wake can never re-ring an older invite.
    final reservations = <HeadlessAuthenticatedMailboxEvent>[];
    final authenticatedMessageIds = <String>[];
    var terminal = false;
    CallSignal? terminalSignal;
    CallSignal? inviteSignal;
    var boundInvites = 0;
    var companionInvites = 0;
    var deferredRows = false;
    var rejectedRows = false;
    try {
      for (final event in page.events) {
        final bound = event.expiresAtMs == invocation.expiresAtMs;
        final rowInvocation = bound
            ? invocation
            : HeadlessCallAdmissionInvocation(
                nonce: invocation.nonce,
                callId: invocation.callId,
                wakeHandle: invocation.wakeHandle,
                expiresAtMs: event.expiresAtMs,
              );
        HeadlessAuthenticatedMailboxEvent authenticated;
        try {
          authenticated = await _authenticateEvent(
            invocation: rowInvocation,
            event: event,
          );
        } on IncomingCallPrePresentationAdmissionException catch (error) {
          switch (error.code) {
            case IncomingCallPrePresentationAdmissionFailureCode.deferred:
              deferredRows = true;
            case IncomingCallPrePresentationAdmissionFailureCode.duplicate:
            case IncomingCallPrePresentationAdmissionFailureCode
                .permanentReject:
              rejectedRows = true;
          }
          continue;
        }
        reservations.add(authenticated);
        authenticatedMessageIds.add(event.messageId);
        switch (authenticated.event) {
          case CallSignalType.reject:
          case CallSignalType.terminate:
            terminal = true;
            terminalSignal ??= authenticated.signal;
          case CallSignalType.invite:
            inviteSignal ??= authenticated.signal;
            if (bound) {
              boundInvites++;
            } else {
              companionInvites++;
            }
          default:
            rejectedRows = true;
        }
      }
      if (terminal) {
        // The caller ended this call: no foreground owner is left to adopt
        // it, and its unacknowledged rows would hold one of the recipient's
        // two pending-call slots at the relay until they expire (device
        // 2026-09-05 17:15Z: the next call to the locked Pixel was refused
        // with CALL_RECIPIENT_CAPACITY, "Couldn't start voice call").
        await _acknowledgeEndedCall(invocation.callId, authenticatedMessageIds);
        // 406: no foreground owner will ever project this call, so the row has
        // to be written here or the chat shows nothing for it.
        await _recordHistory(terminal: terminalSignal, invite: inviteSignal);
        return HeadlessCallAdmissionDisposition.terminal;
      }
      // An unjudged row may be the terminate; never ring past it.
      if (deferredRows) {
        _diagnosticCause = 'authority_unreachable';
        return HeadlessCallAdmissionDisposition.deferred;
      }
      if (boundInvites == 1 && companionInvites == 0) {
        // All rows have now been authenticated and a companion terminal ruled
        // out. The display projection cannot affect admission/replay custody,
        // and its bounded work never waits for a foreground widget or frame.
        final resolve = _resolveDisplay;
        if (resolve != null && inviteSignal != null) {
          try {
            _display = await resolve(inviteSignal).timeout(_displayTimeout);
          } catch (_) {
            _display = null;
          }
        }
        return HeadlessCallAdmissionDisposition.admitted;
      }
      if (boundInvites == 0 && companionInvites > 0 && !rejectedRows) {
        // The wake's own row is gone; the invite already had its own wake.
        return HeadlessCallAdmissionDisposition.emptyOrAlreadyAcked;
      }
      _diagnosticCause = 'authority_rejected';
      return HeadlessCallAdmissionDisposition.permanentReject;
    } catch (_) {
      _diagnosticCause = 'adoption_failed';
      return HeadlessCallAdmissionDisposition.deferred;
    } finally {
      for (final reservation in reservations.reversed) {
        reservation.rollbackReplay();
      }
    }
  }

  /// Writes the terminal row for a call no coordinator will ever see.
  ///
  /// Best effort by construction: releasing the relay's pending slot is
  /// custody work and must not be undone by a history write that failed.
  Future<void> _recordHistory({
    required CallSignal? terminal,
    CallSignal? invite,
  }) async {
    final recorder = _historyRecorder;
    if (recorder == null || terminal == null) return;
    try {
      await recorder(
        terminal: terminal,
        reason: terminal.event == CallSignalType.reject
            ? CallEndReason.declined
            : CallEndReason.callerCancelled,
        invite: invite,
      );
    } catch (_) {
      // The ack already happened; a missing row is a display gap, not custody.
    }
  }

  /// Decline-reply mode (plan 404): the native call was declined while no
  /// Dart owner existed to answer the caller (device 2026-09-05 17:44Z: the
  /// iPhone rang back until its own cancel). Every row is authenticated
  /// against its own expiry. A terminal row means the caller already ended
  /// the call; otherwise the invite yields the caller's `reject`. The rows of
  /// the ended call are acknowledged once the reply reached custody. Nothing
  /// is presented and no replay reservation is kept.
  Future<HeadlessCallAdmissionDisposition> _declineReplyOnce(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    late final CallMailboxRetrieveResult page;
    try {
      page = await _traceHeadlessAdmissionStep(
        'mailbox_retrieve',
        () => _mailboxClient.retrieve(
          callHandle: invocation.callId,
          limit: BridgeCallMailboxClient.maxRetrieveEvents,
        ),
      );
    } catch (_) {
      _emitDeclineReplyResult('retrieve_failed');
      return HeadlessCallAdmissionDisposition.deferred;
    }
    if (page.hasMore) {
      _emitDeclineReplyResult('page_incomplete');
      return HeadlessCallAdmissionDisposition.deferred;
    }
    if (page.events.isEmpty) {
      _emitDeclineReplyResult('empty');
      return HeadlessCallAdmissionDisposition.emptyOrAlreadyAcked;
    }
    final reservations = <HeadlessAuthenticatedMailboxEvent>[];
    final authenticatedMessageIds = <String>[];
    CallSignal? invite;
    var terminal = false;
    var deferredRows = false;
    try {
      for (final event in page.events) {
        final rowInvocation = HeadlessCallAdmissionInvocation(
          nonce: invocation.nonce,
          callId: invocation.callId,
          wakeHandle: invocation.wakeHandle,
          expiresAtMs: event.expiresAtMs,
          mode: invocation.mode,
        );
        HeadlessAuthenticatedMailboxEvent authenticated;
        try {
          authenticated = await _authenticateEvent(
            invocation: rowInvocation,
            event: event,
          );
        } on IncomingCallPrePresentationAdmissionException catch (error) {
          if (error.code ==
              IncomingCallPrePresentationAdmissionFailureCode.deferred) {
            deferredRows = true;
          }
          continue;
        }
        reservations.add(authenticated);
        authenticatedMessageIds.add(event.messageId);
        switch (authenticated.event) {
          case CallSignalType.reject:
          case CallSignalType.terminate:
            terminal = true;
          case CallSignalType.invite:
            invite ??= authenticated.signal;
          default:
            break;
        }
      }
      if (terminal) {
        await _acknowledgeEndedCall(invocation.callId, authenticatedMessageIds);
        _emitDeclineReplyResult('already_ended');
        return HeadlessCallAdmissionDisposition.terminal;
      }
      final pendingInvite = invite;
      if (pendingInvite == null) {
        _emitDeclineReplyResult(deferredRows ? 'invite_deferred' : 'no_invite');
        return deferredRows
            ? HeadlessCallAdmissionDisposition.deferred
            : HeadlessCallAdmissionDisposition.permanentReject;
      }
      final sender = _declineReplySender;
      if (sender == null) {
        _emitDeclineReplyResult('no_sender');
        return HeadlessCallAdmissionDisposition.deferred;
      }
      var sent = false;
      try {
        sent = await sender(pendingInvite, invocation.callId);
      } catch (_) {
        sent = false;
      }
      if (!sent) {
        _emitDeclineReplyResult('unsent');
        return HeadlessCallAdmissionDisposition.deferred;
      }
      await _acknowledgeEndedCall(invocation.callId, authenticatedMessageIds);
      _emitDeclineReplyResult('sent');
      return HeadlessCallAdmissionDisposition.terminal;
    } catch (_) {
      _emitDeclineReplyResult('error');
      return HeadlessCallAdmissionDisposition.deferred;
    } finally {
      for (final reservation in reservations.reversed) {
        reservation.rollbackReplay();
      }
    }
  }

  static void _emitDeclineReplyResult(String outcome) {
    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_HEADLESS_DECLINE_REPLY_RESULT',
        details: <String, Object?>{'outcome': outcome},
      );
    } catch (_) {
      // Fixed-shape diagnostics cannot change the reply outcome.
    }
  }

  /// Best effort: a failed acknowledgement leaves the rows to expire on the
  /// relay and never changes the terminal verdict the native side acts on.
  Future<void> _acknowledgeEndedCall(
    String callHandle,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return;
    try {
      await _mailboxClient.ack(callHandle: callHandle, messageIds: messageIds);
    } catch (_) {
      // The relay drops the handle once its rows expire; presentation and
      // termination are already decided from the authenticated page.
    }
  }

  @override
  Future<HeadlessCallAdmissionCleanup> close() =>
      _cleanup ??= _closeResources();
}

abstract interface class ProductionHeadlessCallAdmissionSession {
  Future<HeadlessCallAdmissionDisposition> evaluate(
    HeadlessCallAdmissionInvocation invocation,
  );

  Future<HeadlessCallAdmissionCleanup> close();
}

/// Diagnostic metadata only; never participates in admission or lease gates.
abstract interface class HeadlessCallAdmissionDiagnosticSource {
  String? get diagnosticCause;
}

abstract interface class HeadlessCallAdmissionDisplaySource {
  HeadlessIncomingCallDisplay? get display;
}

abstract interface class ProductionHeadlessCallAdmissionBackend {
  Future<ProductionHeadlessCallAdmissionSession?> acquire(
    HeadlessCallAdmissionInvocation invocation,
  );

  Future<HeadlessCallAdmissionCleanup> emergencyCleanup();
}

/// Owns the bounded admission run and turns every acquisition, expiry, stop,
/// evaluation, or teardown uncertainty into a no-presentation disposition.
final class ProductionHeadlessCallAdmissionRunner {
  ProductionHeadlessCallAdmissionRunner({
    required ProductionHeadlessCallAdmissionBackend backend,
    int Function()? nowMs,
  }) : _backend = backend,
       _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  /// The wake's exact expiry is the caller's (45 s lifetime) and may lead
  /// this device's clock by up to 30 s, the same lead that native
  /// `CallPayloadParser.MAX_CALLER_EXPIRY_AHEAD_MS` and
  /// `SecureCallEnvelopeCodec.maxFutureClockSkew` accept (beta 2026-09-25:
  /// a callee 13 s behind the caller got an expiry 53 s ahead).
  static const int maximumFutureLifetimeMs = 75 * 1000;

  final ProductionHeadlessCallAdmissionBackend _backend;
  final int Function() _nowMs;

  Future<HeadlessCallAdmissionRunReport> run({
    required HeadlessCallAdmissionInvocation invocation,
    required bool Function() isStopRequested,
  }) async {
    HeadlessCallAdmissionDiagnosticSource? diagnosticSource =
        _backend is HeadlessCallAdmissionDiagnosticSource
        ? _backend as HeadlessCallAdmissionDiagnosticSource
        : null;
    var failureCause = 'unknown';
    try {
      final now = _nowMs();
      final stoppedBeforeAcquire = isStopRequested();
      if (stoppedBeforeAcquire ||
          now < 0 ||
          invocation.expiresAtMs <= now ||
          invocation.expiresAtMs - now > maximumFutureLifetimeMs) {
        return _deferred(
          await _backend.emergencyCleanup(),
          diagnosticCause: stoppedBeforeAcquire
              ? 'canceled'
              : (invocation.expiresAtMs <= now ? 'expired' : 'invalid_request'),
        );
      }
      final session = await _backend.acquire(invocation);
      if (session == null) {
        return _deferred(
          await _backend.emergencyCleanup(),
          diagnosticCause: _readDiagnosticCause(diagnosticSource),
        );
      }
      if (isStopRequested()) {
        return _deferred(
          await _backend.emergencyCleanup(),
          diagnosticCause: 'canceled',
        );
      }
      diagnosticSource = session is HeadlessCallAdmissionDiagnosticSource
          ? session as HeadlessCallAdmissionDiagnosticSource
          : null;
      failureCause = 'adoption_failed';
      final disposition = await _traceHeadlessAdmissionStep(
        'evaluate',
        () => session.evaluate(invocation),
      );
      final display = session is HeadlessCallAdmissionDisplaySource
          ? (session as HeadlessCallAdmissionDisplaySource).display
          : null;
      failureCause = 'cleanup_failed';
      final cleanup = await _traceHeadlessAdmissionStep('close', session.close);
      if (!cleanup.databaseClosed || !cleanup.leaseReleased) {
        return _deferred(cleanup);
      }
      final completedAt = _nowMs();
      final stoppedAfterEvaluation = isStopRequested();
      if (stoppedAfterEvaluation ||
          completedAt < 0 ||
          completedAt >= invocation.expiresAtMs) {
        return _deferred(
          cleanup,
          diagnosticCause: stoppedAfterEvaluation ? 'canceled' : 'expired',
        );
      }
      return HeadlessCallAdmissionRunReport(
        disposition: disposition,
        requiredPersistenceComplete:
            disposition != HeadlessCallAdmissionDisposition.deferred,
        databaseClosed: true,
        leaseReleased: true,
        diagnosticCause: _readDiagnosticCause(diagnosticSource),
        display: disposition == HeadlessCallAdmissionDisposition.admitted
            ? display
            : null,
      );
    } catch (_) {
      HeadlessCallAdmissionCleanup cleanup;
      try {
        cleanup = await _backend.emergencyCleanup();
      } catch (_) {
        cleanup = const HeadlessCallAdmissionCleanup(
          databaseClosed: false,
          leaseReleased: false,
        );
      }
      return _deferred(
        cleanup,
        diagnosticCause: failureCause == 'cleanup_failed'
            ? failureCause
            : _readDiagnosticCause(diagnosticSource) ?? failureCause,
      );
    }
  }

  static String? _readDiagnosticCause(
    HeadlessCallAdmissionDiagnosticSource? source,
  ) {
    try {
      return source?.diagnosticCause;
    } catch (_) {
      return null;
    }
  }

  static HeadlessCallAdmissionRunReport _deferred(
    HeadlessCallAdmissionCleanup cleanup, {
    String? diagnosticCause,
  }) => HeadlessCallAdmissionRunReport(
    disposition: HeadlessCallAdmissionDisposition.deferred,
    requiredPersistenceComplete: false,
    databaseClosed: cleanup.databaseClosed,
    leaseReleased: cleanup.leaseReleased,
    diagnosticCause: !cleanup.databaseClosed || !cleanup.leaseReleased
        ? 'cleanup_failed'
        : diagnosticCause,
  );
}

/// Android production owner for the one admission-only SQLCipher/Go runtime.
/// It starts no Flutter UI, notification owner, listener, coordinator, or
/// media graph. The exact mailbox row remains unacknowledged for foreground
/// canonical adoption; only the rows of a call the caller already ended are
/// acknowledged, so an ended call stops occupying a relay pending-call slot.
final class AndroidProductionHeadlessCallAdmissionBackend
    implements
        ProductionHeadlessCallAdmissionBackend,
        HeadlessCallAdmissionDiagnosticSource {
  AndroidProductionHeadlessCallAdmissionBackend({
    SecureKeyStore? secureKeyStore,
    CanonicalRuntimeLeaseGateway? leaseGateway,
  }) : _secureKeyStore = secureKeyStore ?? FlutterSecureKeyStore() {
    _writableSession = CanonicalWritableRuntimeSession(
      gateway: _DiagnosticAdmissionLeaseGateway(
        leaseGateway ?? MethodChannelCanonicalRuntimeLeaseGateway(),
        (cause) => _diagnosticCause = cause,
      ),
    );
    _bindingCoordinator = CanonicalRuntimeBindingCoordinator(
      secureKeyStore: _secureKeyStore,
    );
    _migrationAuthority = SecureKeyStoreAccountMigrationAuthorityRepository(
      secureKeyStore: _secureKeyStore,
    );
    _linkedAuthority = LinkedInstallationAuthority(
      secureKeyStore: _secureKeyStore,
    );
  }

  final SecureKeyStore _secureKeyStore;
  late final CanonicalWritableRuntimeSession _writableSession;
  late final CanonicalRuntimeBindingCoordinator _bindingCoordinator;
  late final SecureKeyStoreAccountMigrationAuthorityRepository
  _migrationAuthority;
  late final LinkedInstallationAuthority _linkedAuthority;
  Database? _database;
  GoBridgeClient? _bridge;
  MailboxProductionHeadlessCallAdmissionSession? _activeSession;
  Future<HeadlessCallAdmissionCleanup>? _cleanupInFlight;

  @override
  String? get diagnosticCause => _diagnosticCause;
  String? _diagnosticCause;

  @override
  Future<ProductionHeadlessCallAdmissionSession?> acquire(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    _diagnosticCause = null;
    if (_activeSession != null || _writableSession.hasWritableLease) {
      _diagnosticCause = 'busy';
      return null;
    }
    final binding = await _traceHeadlessAdmissionStep(
      'binding',
      _bindingCoordinator.readCurrentAccountBinding,
    );
    if (binding == null) {
      // In stage=admission this describes missing local account binding,
      // before any remote caller or envelope authority has been examined.
      _diagnosticCause = 'authority_invalid';
      return null;
    }
    final database = await _traceHeadlessAdmissionStep(
      'lease_and_database',
      () => _writableSession.acquireThenOpen<Database>(
        binding: binding,
        openDatabase: () =>
            _openExistingDatabase(onOpened: (opened) => _database = opened),
        closeAfterOpenFailure: _closeCurrentDatabase,
        closeDatabaseOnRuntimeAttachFailure: (opened) async {
          if (opened.isOpen) await opened.close();
          return !opened.isOpen;
        },
      ),
    );
    _database = database;

    final identity = await _traceHeadlessAdmissionStep(
      'identity',
      () => loadPassiveIdentitySnapshot(
        dbLoadIdentityRow: () => dbLoadIdentityRow(database),
        secureKeyStore: _secureKeyStore,
      ),
    );
    if (identity == null ||
        identity.mlKemSecretKey?.trim().isNotEmpty != true) {
      throw StateError('headless call authority is unavailable');
    }
    final verifiedBinding = await _traceHeadlessAdmissionStep(
      'binding_verify',
      () => _bindingCoordinator.deriveExistingAccountBinding(identity.peerId),
    );
    if (verifiedBinding != binding) {
      throw StateError('headless call authority is unavailable');
    }
    final migration = await _traceHeadlessAdmissionStep(
      'migration_authority',
      _migrationAuthority.loadAuthority,
    );
    if (migration != null &&
        (migration.isFailClosed ||
            !migration.allowsNormalStartup ||
            migration.state == AccountMigrationAuthorityState.noAccount ||
            (migration.accountPeerId?.trim().isNotEmpty == true &&
                migration.accountPeerId != identity.peerId))) {
      throw StateError('headless call migration authority refused');
    }
    final linked = await _traceHeadlessAdmissionStep(
      'linked_authority',
      () => _linkedAuthority.load(expectedAccountPeerId: identity.peerId),
    );
    final physicalPeerId = selectNotificationCompletedOutcomePhysicalPeerId(
      accountPeerId: identity.peerId,
      accountPublicKey: identity.publicKey,
      authority: linked,
    );
    if (physicalPeerId == null || linked.refusesStartup) {
      throw StateError('headless call installation authority refused');
    }
    final physicalPrivateKey = linked.isActiveLinkedSecondary
        ? linked.credential!.transportPrivateKey
        : identity.privateKey;

    final bridge = GoBridgeClient();
    _bridge = bridge;
    await _traceHeadlessAdmissionStep('go_initialize', bridge.initialize);
    final started = await _traceHeadlessAdmissionStep(
      'node_start',
      () => callP2PNodeStart(
        bridge,
        privateKeyHex: base64ToHex(physicalPrivateKey),
        relayAddresses: defaultRelayAddresses(),
        autoRegister: true,
        namespace: 'mknoon:chat:$physicalPeerId',
        featureFlags: defaultResilienceFeatureFlags(),
      ),
    );
    if (started['ok'] != true || started['peerId'] != physicalPeerId) {
      throw StateError('headless call transport did not start');
    }

    int nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;
    final codec = SecureCallEnvelopeCodec(
      crypto: BridgeCallEnvelopeCrypto(bridge: bridge),
      nowMs: nowMs,
    );
    final roster = DatabaseCallTrustedRosterProvider(database);
    final mailbox = BridgeCallMailboxClient(bridge: bridge);
    final authority = BridgeCallAuthorityClient(bridge: bridge);
    final resolver = CallEndpointResolver(
      nowMs: nowMs,
      verifyEndpointSignature: (endpoint, trustedSigningPublicKey) =>
          authority.verifyEndpoint(
            endpoint,
            trustedDeviceSigningPublicKey: trustedSigningPublicKey,
          ),
    );
    final receivedWakeHandles = ReceivedCallWakeHandleStoreImpl(
      secureKeyStore: _secureKeyStore,
    );
    // 406/408: a killed-app call never reaches CallCoordinator, so this
    // isolate is the only place its row can be written AND the only place its
    // missed-call card can be posted. Without both, the case where the user
    // was least able to notice the call is the one that tells them least.
    final callHistoryRepository = CallHistoryRepositoryImpl(database);
    final callHistory = CallHistoryProjector(callHistoryRepository);
    final headlessCard = HeadlessMissedCallNotification();
    final missedCallNotifier = MissedCallNotifier(
      post:
          ({
            required String contactAccountPeerId,
            required String title,
            required String body,
          }) => headlessCard.show(
            contactAccountPeerId: contactAccountPeerId,
            title: title,
            body: body,
          ),
      resolveContactName: (contactAccountPeerId) async {
        final rows = await database.query(
          'contacts',
          columns: const <String>['username'],
          where: 'peer_id = ?',
          whereArgs: <Object?>[contactAccountPeerId],
          limit: 1,
        );
        final username = rows.isEmpty ? null : rows.first['username'];
        return username is String ? username : null;
      },
      // The app is dead: no conversation can be on screen, so nothing here
      // can legitimately suppress the card.
      isSuppressed: (_) async => false,
      missedBody: localizedMissedCallBody(),
      unknownCallerTitle: localizedMissedCallUnknownCaller(),
    );
    Future<void> recordTerminalCallHistory({
      required CallSignal terminal,
      required CallEndReason reason,
      CallSignal? invite,
    }) => recordHeadlessTerminalCall(
      repository: callHistoryRepository,
      projector: callHistory,
      notifier: missedCallNotifier,
      terminal: terminal,
      reason: reason,
      invite: invite,
    );

    // Plan 404: the decline reply writes through the foreground's transport
    // shape (direct race + mailbox custody) without a coordinator lane.
    final signalingService = CallSignalingService(
      codec: codec,
      directTransport: BridgeCallDirectTransport(bridge: bridge),
      mailboxClient: mailbox,
      networkEffectsAllowed: () => true,
    );
    final declineReply = HeadlessCallDeclineReplyTransmitter(
      transmit: signalingService.transmit,
      resolveEndpoint: (contactAccountPeerId) => resolveProductionCallEndpoint(
        contactAccountPeerId: contactAccountPeerId,
        resolver: resolver,
        rosterProvider: roster,
        authorityClient: authority,
        receivedCallWakeHandleStore: receivedWakeHandles,
      ),
      localAccountPeerId: identity.peerId,
      localDevicePeerId: physicalPeerId,
      loadSigningPrivateKey: () async => identity.privateKey,
      nowMs: nowMs,
    );
    final ringingReply = HeadlessCallRingingReplyTransmitter(
      transmit: signalingService.transmit,
      resolveEndpoint: (contactAccountPeerId) => resolveProductionCallEndpoint(
        contactAccountPeerId: contactAccountPeerId,
        resolver: resolver,
        rosterProvider: roster,
        authorityClient: authority,
        receivedCallWakeHandleStore: receivedWakeHandles,
      ),
      isNativeRinging: (callHandle, expiresAtMs) async {
        if (invocation.mode != HeadlessCallAdmissionMode.ringingReply ||
            invocation.callId != callHandle ||
            invocation.expiresAtMs != expiresAtMs) {
          return false;
        }
        return await const MethodChannel(
              'mknoon/headless_call_admission',
            ).invokeMethod<bool>('isRinging', invocation.identityPayload()) ??
            false;
      },
      localAccountPeerId: identity.peerId,
      localDevicePeerId: physicalPeerId,
      loadSigningPrivateKey: () async => identity.privateKey,
      nowMs: nowMs,
    );
    final admission = IncomingCallPrePresentationAdmission(
      codec: codec,
      trustedRosterProvider: roster,
      localAuthorityProvider: () async => CallLocalDeviceAuthority(
        accountPeerId: identity.peerId,
        devicePeerId: physicalPeerId,
        mlKemSecretKey: identity.mlKemSecretKey!,
      ),
    );
    final session = MailboxProductionHeadlessCallAdmissionSession(
      mailboxClient: mailbox,
      authenticateEvent: ({required invocation, required event}) async {
        final authenticated = await admission.authenticateMailboxEvent(
          nativeCallId: invocation.callId,
          wakeExpiresAtMs: invocation.expiresAtMs,
          event: event,
        );
        return HeadlessAuthenticatedMailboxEvent(
          event: authenticated.signal.event,
          rollbackReplay: authenticated.rollbackReplay,
          signal: authenticated.signal,
        );
      },
      declineReplySender: (invite, callHandle) =>
          declineReply.sendDeclineFor(invite, callHandle: callHandle),
      ringingReplySender: (invite, callHandle) =>
          ringingReply.sendRingingFor(invite, callHandle: callHandle),
      historyRecorder: recordTerminalCallHistory,
      resolveDisplay: (invite) async {
        // These are local reads under the same authenticated DB owner. Start
        // them together; a timed-out projection never starts a later DB read,
        // sends a native update, or changes the saved call transport policy.
        final deadline = DateTime.now().add(const Duration(seconds: 1));
        final local = await Future.wait<Object?>([
          database.query(
            'contacts',
            columns: const <String>['username'],
            where: 'peer_id = ?',
            whereArgs: <Object?>[invite.senderAccountPeerId],
            limit: 1,
          ),
          loadBackgroundPreference(secureKeyStore: _secureKeyStore),
          getApplicationDocumentsDirectory(),
        ]);
        if (DateTime.now().isAfter(deadline)) return null;
        final rows = local[0] as List<Map<String, Object?>>;
        final name = rows.isEmpty ? null : rows.first['username'];
        final normalized = name is String ? name.trim() : '';
        final displayName = normalized.isEmpty ? 'Unknown contact' : normalized;
        final light = local[1] == BackgroundPreference.daylightLagoon;
        final directory = local[2] as Directory;
        final remaining =
            deadline.difference(DateTime.now()).inMilliseconds - 50;
        if (remaining <= 0) return null;
        final png = await LockedCallProjection.renderAvatar(
          invite.senderAccountPeerId,
          light,
          documentsDirectory: directory.path,
        ).timeout(Duration(milliseconds: remaining), onTimeout: () => null);
        return HeadlessIncomingCallDisplay(
          displayName: displayName.length > 128
              ? displayName.substring(0, 128)
              : displayName,
          avatarPng: png != null && png.length <= 512 * 1024 ? png : null,
          light: light,
        );
      },
      closeResources: _closeResources,
    );
    _activeSession = session;
    return session;
  }

  Future<Database> _openExistingDatabase({
    required void Function(Database database) onOpened,
  }) async {
    final database = await _traceHeadlessAdmissionStep(
      'database_open',
      () => openEncryptedDatabase(
        secureKeyStore: _secureKeyStore,
        dbName: 'identity.db',
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        requireExisting: true,
        onOpened: onOpened,
      ),
    );
    await _traceHeadlessAdmissionStep('database_prepare', () async {
      await repairDirectNotificationDurabilityDeleteTriggers(database);
      await repairLegacyPushMessageTransports(database);
      await migrateSecretsToSecureStorage(
        db: database,
        secureKeyStore: _secureKeyStore,
      );
      await runSecretNullChecksMigration(database);
      await scrubLegacyGroupSecretsToSecureStorage(
        db: database,
        secureKeyStore: _secureKeyStore,
      );
    });
    return database;
  }

  @override
  Future<HeadlessCallAdmissionCleanup> emergencyCleanup() => _closeResources();

  Future<HeadlessCallAdmissionCleanup> _closeResources() {
    final inFlight = _cleanupInFlight;
    if (inFlight != null) return inFlight;
    late final Future<HeadlessCallAdmissionCleanup> attempt;
    attempt = _closeResourcesOnce().whenComplete(() {
      if (identical(_cleanupInFlight, attempt)) _cleanupInFlight = null;
    });
    _cleanupInFlight = attempt;
    return attempt;
  }

  Future<HeadlessCallAdmissionCleanup> _closeResourcesOnce() async {
    final bridge = _bridge;
    if (bridge != null && bridge.isInitialized) {
      try {
        await callP2PNodeStop(bridge);
      } catch (_) {
        // Native quiescence below remains the authoritative release fence.
      }
    }
    var runtimeQuiescent = !_writableSession.hasWritableLease;
    if (_writableSession.hasWritableLease) {
      try {
        runtimeQuiescent =
            await _writableSession.beginDrain() &&
            await _writableSession.awaitRuntimeQuiescence();
      } catch (_) {
        runtimeQuiescent = false;
      }
    }
    if (!runtimeQuiescent) return _lifecycleFacts();

    bridge?.dispose();
    _bridge = null;
    final databaseClosed = await _closeCurrentDatabase();
    var leaseReleased = !_writableSession.hasWritableLease;
    if (!leaseReleased) {
      try {
        leaseReleased = await _writableSession.releaseAfterDatabaseClose(
          databaseClosed: databaseClosed,
        );
      } catch (_) {
        leaseReleased = false;
      }
    }
    if (databaseClosed && leaseReleased) _activeSession = null;
    return HeadlessCallAdmissionCleanup(
      databaseClosed: databaseClosed,
      leaseReleased: leaseReleased,
    );
  }

  Future<bool> _closeCurrentDatabase() async {
    final database = _database;
    if (database == null) return true;
    try {
      if (database.isOpen) await database.close();
    } catch (_) {
      return false;
    }
    final closed = !database.isOpen;
    if (closed) _database = null;
    return closed;
  }

  HeadlessCallAdmissionCleanup _lifecycleFacts() =>
      HeadlessCallAdmissionCleanup(
        databaseClosed: _database?.isOpen != true,
        leaseReleased: !_writableSession.hasWritableLease,
      );
}

/// Observes the one existing acquisition; every authority method/result is
/// forwarded unchanged. No bindings, payloads or exception text are recorded.
final class _DiagnosticAdmissionLeaseGateway
    implements CanonicalRuntimeLeaseGateway {
  _DiagnosticAdmissionLeaseGateway(this._delegate, this._onCause);
  final CanonicalRuntimeLeaseGateway _delegate;
  final void Function(String cause) _onCause;

  @override
  Future<CanonicalRuntimeLeaseSnapshot> acquire(String binding) async {
    final CanonicalRuntimeLeaseSnapshot snapshot;
    try {
      snapshot = await _traceHeadlessAdmissionStep(
        'lease_acquire',
        () => _delegate.acquire(binding),
      );
    } catch (error) {
      // An existing foreground canonical owner is expected contention, not a
      // missing/broken method channel. Never record native exception details.
      _onCause(
        error is PlatformException && error.code == 'lease_unavailable'
            ? 'graph_not_owner'
            : 'bridge_unavailable',
      );
      rethrow;
    }
    if (snapshot.state != CanonicalRuntimeLeaseState.active) {
      _onCause('graph_not_owner');
    }
    return snapshot;
  }

  @override
  Future<bool> attachRuntime() =>
      _traceHeadlessAdmissionStep('lease_attach', _delegate.attachRuntime);
  @override
  Future<CanonicalRuntimeLeaseSnapshot> rebind(String binding) =>
      _delegate.rebind(binding);
  @override
  Future<bool> beginDrain() => _delegate.beginDrain();
  @override
  Future<bool> quiesceRuntime() => _delegate.quiesceRuntime();
  @override
  Future<bool> release({required bool databaseClosed}) =>
      _delegate.release(databaseClosed: databaseClosed);
  @override
  Future<CanonicalRuntimeLeaseSnapshot> status() => _delegate.status();
}

final AndroidProductionHeadlessCallAdmissionBackend
_productionHeadlessCallAdmissionBackend =
    AndroidProductionHeadlessCallAdmissionBackend();
final ProductionHeadlessCallAdmissionRunner
_productionHeadlessCallAdmissionRunner = ProductionHeadlessCallAdmissionRunner(
  backend: _productionHeadlessCallAdmissionBackend,
);

Future<HeadlessCallAdmissionRunReport> runProductionHeadlessCallAdmission({
  required HeadlessCallAdmissionInvocation invocation,
  required bool Function() isStopRequested,
}) => _traceHeadlessAdmissionStep(
  'admission_run',
  () => _productionHeadlessCallAdmissionRunner.run(
    invocation: invocation,
    isStopRequested: isStopRequested,
  ),
);

Future<HeadlessCallAdmissionCleanup> cleanupProductionHeadlessCallAdmission() =>
    _productionHeadlessCallAdmissionBackend.emergencyCleanup();

Future<void> runProductionAndroidHeadlessCallAdmission(
  List<String> arguments,
) => runAndroidHeadlessCallAdmission(
  arguments,
  runAdmission: runProductionHeadlessCallAdmission,
  emergencyShutdown: cleanupProductionHeadlessCallAdmission,
);
