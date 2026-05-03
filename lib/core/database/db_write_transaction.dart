import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

/// Marker key in the current Zone that signals the running closure is the
/// body of a [dbWriteTransaction]. When set, calling Bridge.send is a bug:
/// it would hold the SQLCipher write lock across a native method-channel
/// round-trip and starve every concurrent reader.
///
/// Private so callers can only opt in via [dbWriteTransaction] or, for
/// tests, [runInDbWriteTransactionZoneForTest].
const Object _dbWriteTxnZoneKey = #db_write_transaction_active;

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
}) {
  return runZoned(
    () => db.transaction(body, exclusive: exclusive),
    zoneValues: {_dbWriteTxnZoneKey: true},
  );
}

/// Test-only helper to enter the same Zone marker that [dbWriteTransaction]
/// installs, without needing a real [Database]. Lets unit tests verify the
/// bridge guard fires from any code path that ends up calling Bridge.send.
Future<T> runInDbWriteTransactionZoneForTest<T>(
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_dbWriteTxnZoneKey: true});
}
