import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint-style test: any new `db.transaction(...)` write outside the
/// dbWriteTransaction helper would silently re-introduce the lock-window
/// anti-pattern (bridge / outer-repo work inside a SQLCipher write txn,
/// producing the 10s "database has been locked" warning that stalled the
/// Orbit screen on cold start).
///
/// All write transactions in lib/ MUST go through
/// `dbWriteTransaction(...)`, defined in
/// `lib/core/database/db_write_transaction.dart`. Migrations are exempt
/// (one-time, run before any concurrent reader is active).
void main() {
  test(
    'no raw db.transaction(...) call outside dbWriteTransaction or migrations',
    () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ not found');

      const allowedSubpaths = <String>{
        // The helper itself is the only place that may invoke
        // Database.transaction directly — everywhere else must go through
        // the helper so the zone-flag guard fires.
        'lib/core/database/db_write_transaction.dart',
        // One-time DB migrations run inside encrypted_db_opener and
        // complete before any feature code starts. Their transactions
        // never overlap with concurrent bridge calls.
        'lib/core/database/migrations/',
      };

      final offenders = <String>[];
      // Match any receiver, not just `db` — `_db.transaction(...)` is the
      // canonical Dart private-field shape and a likely future-regression
      // shape. The receiver doesn't matter; what matters is the
      // `.transaction(` call against a Database/DatabaseExecutor in any
      // file outside the allowed subpaths.
      final pattern = RegExp(r'\.transaction\s*\(');

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // Normalize Windows separators to '/' so the allowed-subpath check
        // works on every host. `r'\\'` is two literal backslashes (no-op on
        // Windows, where listSync yields single-backslash separators) — use
        // a regular string '\\' (one backslash) for the actual replacement.
        final normalized = entity.path.replaceAll('\\', '/');
        if (allowedSubpaths.any(
          (allowed) =>
              normalized == allowed || normalized.startsWith(allowed),
        )) {
          continue;
        }
        final content = entity.readAsStringSync();
        if (pattern.hasMatch(content)) {
          for (final match in pattern.allMatches(content)) {
            final lineNumber =
                content.substring(0, match.start).split('\n').length;
            offenders.add('$normalized:$lineNumber');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Raw `db.transaction(...)` calls bypass the bridge-call zone '
            'guard. Replace each occurrence with `dbWriteTransaction(db, '
            '(txn) async { ... })` from '
            'lib/core/database/db_write_transaction.dart so future bridge '
            'or outer-repo calls inside the body fail fast in tests rather '
            'than silently holding the SQLCipher write lock at runtime. '
            'Offenders: $offenders',
      );
    },
  );
}
