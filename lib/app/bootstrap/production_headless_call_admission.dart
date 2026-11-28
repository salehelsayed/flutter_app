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
import 'package:flutter_app/features/call/application/voice_call_feature_flags.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_wire_signal.dart';
import 'package:flutter_app/features/call/infrastructure/bridge_call_direct_transport.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/headless_call_admission_entrypoint.dart';
import 'package:flutter_app/features/call/infrastructure/headless_call_v2_reply.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_endpoint_resolution.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/call/presentation/locked_call_projection.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/call/infrastructure/active_call_history_checkpoint.dart';
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
  }) : v2Admission = null,
       _rollbackReplay = rollbackReplay;

  HeadlessAuthenticatedMailboxEvent._authenticated(
    AuthenticatedIncomingCallWireAdmission admission,
  ) : event = CallSignalType.parse(admission.signal.eventWireName),
      signal = admission is AuthenticatedIncomingCallAdmission
          ? admission.signal
          : null,
      v2Admission = admission is AuthenticatedIncomingCallAdmissionV2
          ? admission
          : null,
      _rollbackReplay = admission.rollbackReplay;

  final CallSignalType event;

  final CallSignal? signal;
  final AuthenticatedIncomingCallAdmissionV2? v2Admission;
  CallWireSignal? get wireSignal => v2Admission?.signal ?? signal;
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

AuthenticateHeadlessMailboxEvent createProductionHeadlessMailboxAuthenticator({
  required SecureCallEnvelopeCodec codec,
  required CallTrustedRosterProvider roster,
  required CallLocalAuthorityProvider localAuthorityProvider,
  bool videoEnabled = false,
  ResolveHeadlessCallEndpoint? resolveV2Endpoint,
  int Function()? nowMs,
}) {
  final admission = IncomingCallPrePresentationAdmission(
    codec: codec,
    trustedRosterProvider: roster,
    localAuthorityProvider: localAuthorityProvider,
    videoEnabled: videoEnabled,
    resolveV2Endpoint: resolveV2Endpoint,
    nowMs: nowMs,
  );
  return ({required invocation, required event}) async {
    final authenticated = await admission.authenticateVersionedMailboxEvent(
      nativeCallId: invocation.callId,
      wakeExpiresAtMs: invocation.expiresAtMs,
      event: event,
    );
    return HeadlessAuthenticatedMailboxEvent._authenticated(authenticated);
  };
}

/// Sends the caller one `reject` for [invite] under [callHandle], the mailbox
/// handle the invite row was retrieved with (the caller keys its context by
/// it, not by the call id). Resolves true once the reject reached custody
/// (direct acceptance or mailbox store); never throws.
typedef HeadlessTerminalReplySender =
    Future<bool> Function(CallSignal invite, String callHandle);

typedef HeadlessRingingReplySender =
    Future<bool> Function(CallSignal invite, String callHandle);

typedef HeadlessCallV2ReplySender =
    Future<bool> Function(AuthenticatedIncomingCallAdmissionV2 invite);

/// 406: writes the local terminal call-history row for a call that ended with
/// no coordinator to project it.
///
/// A killed-app call never reaches `CallCoordinator`, so without this the chat
/// shows nothing at all for it — the row the conversation renders simply never
/// exists. [invite] is absent when the invite row was acknowledged by an
/// earlier run and only the terminal row remains.
typedef HeadlessCallHistoryRecorder =
    Future<void> Function({
      required CallWireSignal terminal,
      required String callHandle,
      required CallEndReason reason,
      CallWireSignal? invite,
    });

/// Preserves an authenticated connected checkpoint before the ordinary
/// headless terminal writer can create a never-connected history row.
HeadlessCallHistoryRecorder createProductionHeadlessCallHistoryRecorder({
  required Database database,
  required SecureKeyStore secureKeyStore,
  required IdentityModel localIdentity,
  required MissedCallNotifier notifier,
}) {
  final repository = CallHistoryRepositoryImpl(database);
  final projector = CallHistoryProjector(repository);
  final checkpoint = ActiveCallHistoryCheckpoint(
    database: database,
    secureKeyStore: secureKeyStore,
    localIdentity: localIdentity,
    readContext: (_) => null,
    clock: () => DateTime.now().toUtc(),
  );
  return ({
    required terminal,
    required callHandle,
    required reason,
    invite,
  }) async {
    if (await checkpoint.settleConnectedTerminal(
      callId: terminal.callId,
      callHandle: callHandle,
      remoteAccountPeerId: terminal.senderAccountPeerId,
      remoteDevicePeerId: terminal.senderDevicePeerId,
    )) {
      return;
    }
    await recordHeadlessTerminalCall(
      repository: repository,
      projector: projector,
      notifier: notifier,
      terminal: terminal,
      reason: reason,
      invite: invite,
    );
  };
}

typedef _AuthenticatedMailboxRow = ({
  CallMailboxEvent event,
  HeadlessAuthenticatedMailboxEvent admission,
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
    HeadlessTerminalReplySender? declineReplySender,
    HeadlessRingingReplySender? ringingReplySender,
    HeadlessTerminalReplySender? presentationFailureReplySender,
    HeadlessCallV2ReplySender? declineV2ReplySender,
    HeadlessCallV2ReplySender? ringingV2ReplySender,
    HeadlessCallHistoryRecorder? historyRecorder,
    Future<HeadlessIncomingCallDisplay?> Function(CallWireSignal invite)?
    resolveDisplay,
    Duration displayTimeout = const Duration(seconds: 1),
  }) : _mailboxClient = mailboxClient,
       _authenticateEvent = authenticateEvent,
       _closeResources = closeResources,
       _declineReplySender = declineReplySender,
       _ringingReplySender = ringingReplySender,
       _presentationFailureReplySender = presentationFailureReplySender,
       _declineV2ReplySender = declineV2ReplySender,
       _ringingV2ReplySender = ringingV2ReplySender,
       _historyRecorder = historyRecorder,
       _resolveDisplay = resolveDisplay,
       _displayTimeout = displayTimeout;

  final CallMailboxClient _mailboxClient;
  final AuthenticateHeadlessMailboxEvent _authenticateEvent;
  final HeadlessTerminalReplySender? _declineReplySender;
  final HeadlessRingingReplySender? _ringingReplySender;
  final HeadlessTerminalReplySender? _presentationFailureReplySender;
  final HeadlessCallV2ReplySender? _declineV2ReplySender;
  final HeadlessCallV2ReplySender? _ringingV2ReplySender;
  final HeadlessCallHistoryRecorder? _historyRecorder;
  final Future<HeadlessCallAdmissionCleanup> Function() _closeResources;
  final Future<HeadlessIncomingCallDisplay?> Function(CallWireSignal invite)?
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
    HeadlessCallAdmissionMode.ringingReply ||
    HeadlessCallAdmissionMode.presentationFailureReply =>
      _presentationReplyOnce(invocation),
  };

  /// Reauthenticates the invite after native presentation has settled.
  /// A ringing reply leaves custody for the foreground owner.
  Future<HeadlessCallAdmissionDisposition> _presentationReplyOnce(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    final failed =
        invocation.mode == HeadlessCallAdmissionMode.presentationFailureReply;
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
    final rows = <_AuthenticatedMailboxRow>[];
    final invites = <_AuthenticatedMailboxRow>[];
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
        final row = (event: event, admission: authenticated);
        rows.add(row);
        if (failed && authenticated.v2Admission != null) {
          return HeadlessCallAdmissionDisposition.deferred;
        }
        switch (authenticated.event) {
          case CallSignalType.reject:
          case CallSignalType.terminate:
            break;
          case CallSignalType.invite:
            invites.add(row);
          default:
            return HeadlessCallAdmissionDisposition.deferred;
        }
      }
      final terminal = _matchingTerminal(rows, invites);
      if (terminal != null) {
        if (!failed) return HeadlessCallAdmissionDisposition.deferred;
        await _acknowledgeEndedCall(invocation.callId, rows, terminal);
        return HeadlessCallAdmissionDisposition.terminal;
      }
      if (invites.length != 1) {
        return HeadlessCallAdmissionDisposition.deferred;
      }
      final invite = invites.single;
      if (failed) {
        final sender = _presentationFailureReplySender;
        final signal = invite.admission.signal;
        if (invite.event.expiresAtMs != invocation.expiresAtMs ||
            sender == null ||
            signal == null ||
            !await sender(signal, invocation.callId)) {
          return HeadlessCallAdmissionDisposition.deferred;
        }
        await _acknowledgeEndedCall(invocation.callId, rows, invite);
        return HeadlessCallAdmissionDisposition.terminal;
      }
      final send = _replyFor(invite, invocation.callId, ringing: true);
      return send != null && await send()
          ? HeadlessCallAdmissionDisposition.terminal
          : HeadlessCallAdmissionDisposition.deferred;
    } catch (_) {
      return HeadlessCallAdmissionDisposition.deferred;
    } finally {
      for (final row in rows.reversed) {
        row.admission.rollbackReplay();
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
    final rows = <_AuthenticatedMailboxRow>[];
    final invites = <_AuthenticatedMailboxRow>[];
    CallWireSignal? inviteSignal;
    var boundInvites = 0;
    var companionInvites = 0;
    var deferredRows = false;
    var rejectedRows = false;
    var unresolvedV2Invite = false;
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
          if (error.gate ==
              IncomingCallPrePresentationAdmissionGate.endpointUnavailable) {
            unresolvedV2Invite = true;
          }
          try {
            emitFlowEvent(
              layer: 'FL',
              event: 'CALL_HEADLESS_ADMISSION_ROW_REFUSED',
              details: <String, Object?>{
                'outcome': error.code.name,
                'reasonCode': error.reasonCode,
              },
            );
          } catch (_) {
            // Diagnostics cannot change admission or cleanup behavior.
          }
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
        final row = (event: event, admission: authenticated);
        rows.add(row);
        switch (authenticated.event) {
          case CallSignalType.reject:
          case CallSignalType.terminate:
            break;
          case CallSignalType.invite:
            invites.add(row);
            inviteSignal ??= authenticated.wireSignal;
            if (bound) {
              boundInvites++;
            } else {
              companionInvites++;
            }
          default:
            rejectedRows = true;
        }
      }
      final terminal = _matchingTerminal(
        rows,
        invites,
        allowV1: !unresolvedV2Invite,
      );
      if (terminal != null) {
        // The caller ended this call: no foreground owner is left to adopt
        // it, and its unacknowledged rows would hold one of the recipient's
        // two pending-call slots at the relay until they expire (device
        // 2026-09-05 17:15Z: the next call to the locked Pixel was refused
        // with CALL_RECIPIENT_CAPACITY, "Couldn't start voice call").
        await _acknowledgeEndedCall(invocation.callId, rows, terminal);
        // 406: no foreground owner will ever project this call, so the row has
        // to be written here or the chat shows nothing for it.
        await _recordHistory(
          terminal: terminal.admission.wireSignal,
          callHandle: invocation.callId,
          invite: inviteSignal,
        );
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
            final name = _display?.displayName.trim();
            if (name == '' || name == inviteSignal.senderAccountPeerId) {
              _display = null;
            }
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
      for (final row in rows.reversed) {
        row.admission.rollbackReplay();
      }
    }
  }

  /// Writes the terminal row for a call no coordinator will ever see.
  ///
  /// Best effort by construction: releasing the relay's pending slot is
  /// custody work and must not be undone by a history write that failed.
  Future<void> _recordHistory({
    required CallWireSignal? terminal,
    required String callHandle,
    CallWireSignal? invite,
  }) async {
    final recorder = _historyRecorder;
    if (recorder == null || terminal == null) return;
    try {
      await recorder(
        terminal: terminal,
        callHandle: callHandle,
        reason: terminal.eventWireName == CallSignalType.reject.wireName
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
    final rows = <_AuthenticatedMailboxRow>[];
    final invites = <_AuthenticatedMailboxRow>[];
    var deferredRows = false;
    var unresolvedV2Invite = false;
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
          if (error.gate ==
              IncomingCallPrePresentationAdmissionGate.endpointUnavailable) {
            unresolvedV2Invite = true;
          }
          continue;
        }
        final row = (event: event, admission: authenticated);
        rows.add(row);
        if (authenticated.event == CallSignalType.invite) invites.add(row);
      }
      final terminal = _matchingTerminal(
        rows,
        invites,
        allowV1: !unresolvedV2Invite,
      );
      if (terminal != null) {
        await _acknowledgeEndedCall(invocation.callId, rows, terminal);
        _emitDeclineReplyResult('already_ended');
        return HeadlessCallAdmissionDisposition.terminal;
      }
      final pendingInvite = invites
          .where((row) => row.admission.wireSignal != null)
          .firstOrNull;
      if (pendingInvite == null) {
        _emitDeclineReplyResult(deferredRows ? 'invite_deferred' : 'no_invite');
        return deferredRows
            ? HeadlessCallAdmissionDisposition.deferred
            : HeadlessCallAdmissionDisposition.permanentReject;
      }
      if (invites.any((row) => row.admission.v2Admission != null) &&
          (invites.length != 1 ||
              pendingInvite.event.expiresAtMs != invocation.expiresAtMs)) {
        _emitDeclineReplyResult('invite_deferred');
        return HeadlessCallAdmissionDisposition.deferred;
      }
      final send = _replyFor(pendingInvite, invocation.callId, ringing: false);
      if (send == null) {
        _emitDeclineReplyResult('no_sender');
        return HeadlessCallAdmissionDisposition.deferred;
      }
      var sent = false;
      try {
        sent = await send();
      } catch (_) {
        sent = false;
      }
      if (!sent) {
        _emitDeclineReplyResult('unsent');
        return HeadlessCallAdmissionDisposition.deferred;
      }
      await _acknowledgeEndedCall(invocation.callId, rows, pendingInvite);
      _emitDeclineReplyResult('sent');
      return HeadlessCallAdmissionDisposition.terminal;
    } catch (_) {
      _emitDeclineReplyResult('error');
      return HeadlessCallAdmissionDisposition.deferred;
    } finally {
      for (final row in rows.reversed) {
        row.admission.rollbackReplay();
      }
    }
  }

  Future<bool> Function()? _replyFor(
    _AuthenticatedMailboxRow row,
    String callHandle, {
    required bool ringing,
  }) {
    final v2 = row.admission.v2Admission;
    if (v2 != null) {
      final sender = ringing ? _ringingV2ReplySender : _declineV2ReplySender;
      return sender == null ? null : () => sender(v2);
    }
    final signal = row.admission.signal;
    final sender = ringing ? _ringingReplySender : _declineReplySender;
    return sender != null && signal != null
        ? () => sender(signal, callHandle)
        : null;
  }

  static _AuthenticatedMailboxRow? _matchingTerminal(
    List<_AuthenticatedMailboxRow> rows,
    List<_AuthenticatedMailboxRow> invites, {
    bool allowV1 = true,
  }) {
    _AuthenticatedMailboxRow? match;
    for (final row in rows) {
      if (!allowV1 && row.admission.v2Admission == null) continue;
      final event = row.admission.event;
      final isTerminal =
          event == CallSignalType.reject || event == CallSignalType.terminate;
      if (isTerminal && invites.every((invite) => _sameCall(row, invite))) {
        if (row.admission.wireSignal != null) return row;
        match ??= row;
      }
    }
    return match;
  }

  static bool _sameCall(
    _AuthenticatedMailboxRow a,
    _AuthenticatedMailboxRow b,
  ) {
    final aV2 = a.admission.v2Admission;
    final bV2 = b.admission.v2Admission;
    if (aV2 == null && bV2 == null) return true;
    // Match the foreground mailbox's authenticated schema, handle, call ID,
    // and participant binding when a V2 row is present.
    if (aV2 == null || bV2 == null) return false;
    final first = aV2.signal;
    final second = bV2.signal;
    return aV2.callHandle == bV2.callHandle &&
        first.callId == second.callId &&
        first.senderAccountPeerId == second.senderAccountPeerId &&
        first.senderDevicePeerId == second.senderDevicePeerId &&
        first.recipientAccountPeerId == second.recipientAccountPeerId &&
        first.recipientDevicePeerId == second.recipientDevicePeerId;
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
    List<_AuthenticatedMailboxRow> rows,
    _AuthenticatedMailboxRow ended,
  ) async {
    final messageIds = <String>[
      for (final row in rows)
        if (_sameCall(row, ended)) row.event.messageId,
    ];
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
    final videoEnabled =
        productionVoiceCallFeatureFlags()['video_call_v2_enabled'] == true;
    final codec = SecureCallEnvelopeCodec(
      crypto: BridgeCallEnvelopeCrypto(bridge: bridge),
      nowMs: nowMs,
      videoEnabled: videoEnabled,
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
    Future<ResolvedCallEndpoint> resolveEndpoint(String contactAccountPeerId) =>
        resolveProductionCallEndpoint(
          contactAccountPeerId: contactAccountPeerId,
          resolver: resolver,
          rosterProvider: roster,
          authorityClient: authority,
          receivedCallWakeHandleStore: receivedWakeHandles,
        );

    Future<bool> isNativeRinging(String callHandle, int expiresAtMs) async {
      if (invocation.mode != HeadlessCallAdmissionMode.ringingReply ||
          invocation.callId != callHandle ||
          invocation.expiresAtMs != expiresAtMs) {
        return false;
      }
      return await const MethodChannel(
            'mknoon/headless_call_admission',
          ).invokeMethod<bool>('isRinging', invocation.identityPayload()) ??
          false;
    }

    Future<String> loadSigningPrivateKey() async => identity.privateKey;

    // 406/408: a killed-app call never reaches CallCoordinator, so this
    // isolate is the only place its row can be written AND the only place its
    // missed-call card can be posted. Without both, the case where the user
    // was least able to notice the call is the one that tells them least.
    final headlessCard = HeadlessMissedCallNotification();
    final missedCallNotifier = MissedCallNotifier(
      postWithAction: (entry, title, body) => headlessCard.show(
        contactAccountPeerId: entry.contactAccountPeerId,
        callId: entry.callId.value,
        title: title,
        body: body,
      ),
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
      missedBody: localizedMissedCallBody,
      unknownCallerTitle: localizedMissedCallUnknownCaller,
    );
    final recordTerminalCallHistory =
        createProductionHeadlessCallHistoryRecorder(
          database: database,
          secureKeyStore: _secureKeyStore,
          localIdentity: identity,
          notifier: missedCallNotifier,
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
      resolveEndpoint: resolveEndpoint,
      localAccountPeerId: identity.peerId,
      localDevicePeerId: physicalPeerId,
      loadSigningPrivateKey: loadSigningPrivateKey,
      nowMs: nowMs,
    );
    final ringingReply = HeadlessCallRingingReplyTransmitter(
      transmit: signalingService.transmit,
      resolveEndpoint: resolveEndpoint,
      isNativeRinging: isNativeRinging,
      localAccountPeerId: identity.peerId,
      localDevicePeerId: physicalPeerId,
      loadSigningPrivateKey: loadSigningPrivateKey,
      nowMs: nowMs,
    );
    final v2Reply = videoEnabled
        ? HeadlessCallV2ReplyTransmitter(
            signalingService: signalingService,
            resolveEndpoint: resolveEndpoint,
            isNativeRinging: isNativeRinging,
            localAccountPeerId: identity.peerId,
            localDevicePeerId: physicalPeerId,
            loadSigningPrivateKey: loadSigningPrivateKey,
            nowMs: nowMs,
          )
        : null;
    final session = MailboxProductionHeadlessCallAdmissionSession(
      mailboxClient: mailbox,
      authenticateEvent: createProductionHeadlessMailboxAuthenticator(
        codec: codec,
        roster: roster,
        localAuthorityProvider: () async => CallLocalDeviceAuthority(
          accountPeerId: identity.peerId,
          devicePeerId: physicalPeerId,
          mlKemSecretKey: identity.mlKemSecretKey!,
        ),
        videoEnabled: videoEnabled,
        resolveV2Endpoint: videoEnabled ? resolveEndpoint : null,
        nowMs: nowMs,
      ),
      declineReplySender: (invite, callHandle) =>
          declineReply.sendDeclineFor(invite, callHandle: callHandle),
      ringingReplySender: (invite, callHandle) =>
          ringingReply.sendRingingFor(invite, callHandle: callHandle),
      presentationFailureReplySender: (invite, callHandle) =>
          declineReply.sendPresentationFailureFor(
            invite,
            callHandle: callHandle,
            isAuthorized: () async {
              if (invocation.mode !=
                      HeadlessCallAdmissionMode.presentationFailureReply ||
                  invocation.callId != callHandle ||
                  invocation.expiresAtMs != invite.expiresAtMs) {
                return false;
              }
              return await const MethodChannel('mknoon/headless_call_admission')
                      .invokeMethod<bool>(
                        'isPresentationFailure',
                        invocation.identityPayload(),
                      ) ??
                  false;
            },
          ),
      declineV2ReplySender: v2Reply?.sendDeclineFor,
      ringingV2ReplySender: v2Reply?.sendRingingFor,
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
