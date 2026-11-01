import '../../../core/diagnostics/app_diagnostics.dart';

// Only these closed classifications cross the diagnostic boundary. In
// particular, unsigned envelope intent is never evidence of a local action.
enum ContactRequestDiagnosticSource { live, storedReplay, localAction }

enum ContactRequestConsentClass { active, withdrawn, declined, none, unknown }

enum ContactRequestDiagnosticAction {
  withdraw,
  localAdd,
  mutualIntroAdd,
  admit,
  replay,
}

enum ContactRequestDisposition {
  ignored,
  pending,
  automatic,
  committed,
  failed,
}

void recordContactRequestDiagnostic({
  required ContactRequestDiagnosticSource source,
  required ContactRequestConsentClass consent,
  required ContactRequestDiagnosticAction action,
  required ContactRequestDisposition disposition,
}) {
  try {
    AppDiagnostics.instance.record(
      feature: 'contact_request',
      stage: disposition == ContactRequestDisposition.committed
          ? 'commit'
          : source == ContactRequestDiagnosticSource.storedReplay
          ? 'present'
          : 'verify',
      outcome: switch (disposition) {
        ContactRequestDisposition.ignored => 'rejected',
        ContactRequestDisposition.pending => 'pending',
        ContactRequestDisposition.failed => 'failed',
        ContactRequestDisposition.automatic ||
        ContactRequestDisposition.committed => 'ok',
      },
      values: {
        'requestSource': switch (source) {
          ContactRequestDiagnosticSource.live => 'live',
          ContactRequestDiagnosticSource.storedReplay => 'stored_replay',
          ContactRequestDiagnosticSource.localAction => 'local_action',
        },
        'consentClass': consent.name,
        'requestAction': switch (action) {
          ContactRequestDiagnosticAction.localAdd => 'local_add',
          ContactRequestDiagnosticAction.mutualIntroAdd => 'mutual_intro_add',
          ContactRequestDiagnosticAction.withdraw => 'withdraw',
          ContactRequestDiagnosticAction.admit => 'admit',
          ContactRequestDiagnosticAction.replay => 'replay',
        },
        'requestDisposition': disposition.name,
      },
    );
  } catch (_) {
    // Observation cannot change consent, communication, or error propagation.
  }
}
