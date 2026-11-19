import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';
import '../diagnostics/app_diagnostic_events.dart';
import 'outgoing_transport_mutation.dart';

/// Marker key in the current Zone that signals the running closure is the
/// body of a [dbWriteTransaction]. When set, calling Bridge.send is a bug:
/// it would hold the SQLCipher write lock across a native method-channel
/// round-trip and starve every concurrent reader.
///
/// Private so callers can only opt in via [dbWriteTransaction] or, for
/// tests, [runInDbWriteTransactionZoneForTest].
const Object _dbWriteTxnZoneKey = #db_write_transaction_active;
const Object _initialAuthorityScopeKey = #outgoing_initial_authority_scope;
const Object _initialAuthorityTransactionKey = #outgoing_initial_authority_transaction;

Future<T> runWithOutgoingInitialAuthorityObserver<T>(
  OutgoingInitialAuthorityObserver? observer,
  Future<T> Function() work, {
  ({OutgoingInitialAuthorityObserver? observer})? mutationObservation,
}) => runZoned(work, zoneValues: {
  _initialAuthorityScopeKey: (
    observer: observer, mutationObservation: mutationObservation),
});

/// A present-null caller scope stays authoritative over repository defaults.
Future<T> observeOutgoingInitialAuthority<T>(
  Future<T> Function() work, {
  OutgoingInitialAuthorityObserver? Function()? captureMutationObserver,
}) {
  final scope = Zone.current[_initialAuthorityScopeKey] as ({
    OutgoingInitialAuthorityObserver? observer,
    ({OutgoingInitialAuthorityObserver? observer})? mutationObservation,
  })?;
  final observer = scope?.observer;
  var mutationObservation = scope?.mutationObservation;
  if (mutationObservation == null) {
    OutgoingInitialAuthorityObserver? negative;
    try { negative = captureMutationObserver?.call(); } catch (_) {}
    mutationObservation = (observer: negative);
  }
  return runWithOutgoingInitialAuthorityObserver(observer, work,
      mutationObservation: mutationObservation);
}

final class _InitialAuthorityTransaction {
  _InitialAuthorityTransaction(this.observer, this.mutationObserver, this.sqlRealm);
  final OutgoingInitialAuthorityObserver? observer;
  final OutgoingInitialAuthorityObserver? mutationObserver;
  final Object sqlRealm;
  final List<void Function(bool)> completions = [];
  final Set<(OutgoingInitialAuthorityKind, String, String?, String?, String?)> decisions = {};

  void stage(OutgoingInitialAuthorityDecision decision) {
    if (!decisions.add((decision.kind, decision.contactAccountPeerId,
        decision.messageId, decision.senderAccountPeerId, decision.envelopeSenderPeerId))) {
      return;
    }
    try {
      final negative = decision.kind == OutgoingInitialAuthorityKind.superseded ||
          decision.kind == OutgoingInitialAuthorityKind.envelopeReplaced ||
          decision.kind == OutgoingInitialAuthorityKind.contactRemoved;
      final completion = (negative ? mutationObserver : observer)
          ?.call(decision, sqlRealm);
      if (completion != null) {
        completions.add(completion);
      }
    } catch (_) {
      // Optional observation cannot fail or delay the database owner.
    }
  }

  void resolve(bool committed) {
    for (final completion in completions) {
      try { completion(committed); } catch (_) {}
    }
  }
}

/// DatabaseExecutor leaves stage facts; only dbWriteTransaction resolves them.
void stageOutgoingInitialAuthorityDecision(
  OutgoingInitialAuthorityDecision decision,
) {
  (Zone.current[_initialAuthorityTransactionKey] as _InitialAuthorityTransaction?)
      ?.stage(decision);
}

/// Thrown when Bridge.send is invoked from inside a [dbWriteTransaction]
/// body. The guard runs in every concrete Bridge implementation
/// (GoBridgeClient, FakeBridge) so violations fail fast in tests and
/// during development.
class BridgeCallInsideDbTransactionError extends Error {
  BridgeCallInsideDbTransactionError({this.commandPreview = ''});

  final String commandPreview;

  @override
  String toString() {
    final cmd = commandPreview.isEmpty ? '' : ' (cmd="$commandPreview")';
    return 'BridgeCallInsideDbTransactionError: a Bridge.send call$cmd was '
        'attempted inside a dbWriteTransaction body. Holding the SQLCipher '
        'write lock across native method-channel hops causes the canonical '
        '"database has been locked for 0:00:10" sqflite warning and starves '
        'every concurrent DB reader (e.g. OrbitWired._loadOrbitData stalls '
        'on its skeleton placeholders). Move the bridge call outside the '
        'transaction. See test/features/groups/application/'
        'drain_lock_window_test.dart and lib/core/database/'
        'db_write_transaction.dart for the pattern.';
  }
}

/// Whether the current asynchronous context is executing inside a
/// [dbWriteTransaction] body.
bool isInsideDbWriteTransaction() {
  return Zone.current[_dbWriteTxnZoneKey] == true;
}

/// Asserts that the caller is *not* inside a [dbWriteTransaction] body.
/// Throws [BridgeCallInsideDbTransactionError] when the zone flag is set.
///
/// Concrete Bridge implementations call this at the top of their `send()`
/// method so the guard fires regardless of which call helper was used.
void assertNotInsideDbWriteTransaction({String commandPreview = ''}) {
  if (isInsideDbWriteTransaction()) {
    throw BridgeCallInsideDbTransactionError(commandPreview: commandPreview);
  }
}

/// Runs [body] inside a SQLCipher write transaction with a Zone marker that
/// trips the bridge guard if any code on the call path tries to invoke
/// Bridge.send. Use this at every site that previously called
/// `db.transaction(...)` so the anti-pattern (bridge work inside a write
/// txn) is impossible to introduce silently.
Future<T> dbWriteTransaction<T>(
  Database db,
  Future<T> Function(Transaction txn) body, {
  bool? exclusive,
  Future<void> Function()? beforeAuthorityResolutionForTest,
}) async {
  final elapsed = Stopwatch()..start();
  var successful = false;
  final scope = Zone.current[_initialAuthorityScopeKey] as ({
    OutgoingInitialAuthorityObserver? observer,
    ({OutgoingInitialAuthorityObserver? observer})? mutationObservation,
  })?;
  final authority = _InitialAuthorityTransaction(
      scope?.observer, scope?.mutationObservation?.observer, db);
  try {
    final value = await runZoned(
      () => db.transaction(body, exclusive: exclusive),
      zoneValues: {
        _dbWriteTxnZoneKey: true,
        _initialAuthorityTransactionKey: authority,
      },
    );
    successful = true;
    if (beforeAuthorityResolutionForTest != null) {
      await beforeAuthorityResolutionForTest();
    }
    return value;
  } finally {
    authority.resolve(successful);
    AppDiagnosticEvents.storageTransaction(
      successful,
      elapsed.elapsedMilliseconds,
    );
  }
}

/// Test-only helper to enter the same Zone marker that [dbWriteTransaction]
/// installs, without needing a real [Database]. Lets unit tests verify the
/// bridge guard fires from any code path that ends up calling Bridge.send.
Future<T> runInDbWriteTransactionZoneForTest<T>(Future<T> Function() body) {
  return runZoned(body, zoneValues: {_dbWriteTxnZoneKey: true});
}
