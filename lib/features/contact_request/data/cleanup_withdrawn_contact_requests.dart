import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../core/database/db_write_transaction.dart';

const _eligible = '''status = 'pending'
AND EXISTS (SELECT 1 FROM contact_relationship_consent consent
  WHERE consent.peer_id = contact_requests.peer_id AND consent.state = 'withdrawn')
AND NOT EXISTS (SELECT 1 FROM contacts
  WHERE contacts.peer_id = contact_requests.peer_id)''';

/// Retires legacy pending notifications before removing their exact retry rows.
/// Presentation reads independently hide these rows if cleanup must retry.
Future<int> cleanupWithdrawnContactRequests({
  required Database db,
  required Future<void> Function(String peerId, bool Function() isExpired)
  retireNotification,
  Duration timeout = const Duration(milliseconds: 150),
  int batchLimit = 100,
}) async {
  final clock = Stopwatch()..start();
  var timedOut = false;
  var deleted = 0;
  bool isExpired() => timedOut || clock.elapsed >= timeout;

  Future<int> run() async {
    try {
      if (isExpired() || batchLimit <= 0) return deleted;
      final rows = await db.query(
        'contact_requests',
        where: _eligible,
        limit: batchLimit > 100 ? 100 : batchLimit,
      );
      if (isExpired()) return deleted;
      for (final row in rows) {
        if (isExpired()) break;
        // Compare every stored field, including nullable keys, so a replacement
        // cannot be removed using an older notification-retirement attempt.
        final identity = row.keys.map((key) => '$key IS ?').join(' AND ');
        final arguments = row.values.toList();
        final exact = '$_eligible AND $identity';
        try {
          final current = await db.query(
            'contact_requests',
            where: exact,
            whereArgs: arguments,
            limit: 1,
          );
          if (isExpired()) break;
          if (current.isEmpty) continue;
          await retireNotification(row['peer_id']! as String, isExpired);
          if (isExpired()) break;
          final count = await dbWriteTransaction(db, (txn) async {
            if (isExpired()) throw const _CleanupExpired();
            final count = await txn.delete(
              'contact_requests',
              where: exact,
              whereArgs: arguments,
            );
            if (isExpired()) throw const _CleanupExpired();
            return count;
          });
          deleted += count;
          if (isExpired()) break;
        } catch (_) {
          // Cancellation or SQL failure leaves this row as the next launch's
          // retry ledger; independent rows can still be retired this launch.
          if (isExpired()) break;
        }
      }
    } catch (_) {
      // Database availability must not turn local cleanup into a startup gate.
    }
    return deleted;
  }

  return run().timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      return deleted;
    },
  );
}

class _CleanupExpired implements Exception {
  const _CleanupExpired();
}
