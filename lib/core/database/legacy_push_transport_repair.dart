import 'package:sqflite_sqlcipher/sqflite.dart';

/// Repairs the invalid transport value written by the historical rich-push
/// fast path. Rich push is a projection of a message already accepted by the
/// relay inbox, so its canonical persisted transport is `inbox`.
///
/// This runs after every writable database open instead of changing the schema
/// version for a data-only compatibility repair. The predicate is deliberately
/// narrow: only incoming legacy `push` rows are changed.
Future<int> repairLegacyPushMessageTransports(Database database) =>
    database.transaction<int>(
      (transaction) => transaction.update(
        'messages',
        const <String, Object?>{'transport': 'inbox'},
        where: 'is_incoming = ? AND transport = ?',
        whereArgs: const <Object?>[1, 'push'],
      ),
    );
