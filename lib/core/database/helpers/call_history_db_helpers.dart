import 'package:sqflite_sqlcipher/sqflite.dart';

import '../migrations/117_call_history.dart';
import '../db_write_transaction.dart';

Future<void> insertCallHistoryTerminal(
  Database database,
  Map<String, Object?> row,
) async {
  await database.insert(
    kCallHistoryTable,
    row,
    conflictAlgorithm: ConflictAlgorithm.ignore,
  );
}

Future<Map<String, Object?>?> loadCallHistoryById(
  Database database,
  String callId,
) async {
  final rows = await database.query(
    kCallHistoryTable,
    where: 'call_id = ?',
    whereArgs: <Object?>[callId],
    limit: 1,
  );
  return rows.isEmpty ? null : Map<String, Object?>.of(rows.single);
}

Future<List<Map<String, Object?>>> loadCallHistoryForContact(
  Database database,
  String contactAccountPeerId,
) async => (await database.query(
  kCallHistoryTable,
  where: 'contact_account_peer_id = ?',
  whereArgs: <Object?>[contactAccountPeerId],
  orderBy: 'started_at DESC, call_id ASC',
)).map(Map<String, Object?>.of).toList(growable: false);

/// Bounded global page over the same terminal table. Counts and rows share a
/// read transaction, and local contact names are resolved at query time.
Future<({List<Map<String, Object?>> rows, int total, int missed})>
loadCallHistoryPage(
  Database database, {
  required bool missedOnly,
  required String search,
  required int limit,
  String? cursorStartedAt,
  String? cursorCallId,
}) {
  if (limit < 1 || limit > 101) throw ArgumentError.value(limit, 'limit');
  const missed =
      "h.direction = 'incoming' AND h.status IN ('missed', 'cancelled', 'busy')";
  const from =
      '$kCallHistoryTable h LEFT JOIN contacts c ON c.peer_id = h.contact_account_peer_id';
  // DateTime emits three fractional digits for exact milliseconds and six
  // otherwise. Normalize only comparisons; persisted history stays unchanged.
  const timestamp =
      "CASE WHEN substr(h.started_at, -5, 1) = '.' "
      "THEN substr(h.started_at, 1, length(h.started_at) - 1) || '000Z' "
      "ELSE h.started_at END";
  final cursorTimestamp = cursorStartedAt?.replaceFirstMapped(
    RegExp(r'\.(\d{3})Z$'),
    (match) => '.${match[1]}000Z',
  );
  final query = search.trim();
  final searchWhere = query.isEmpty
      ? '1 = 1'
      : "instr(lower(COALESCE(c.username, '')), lower(?)) > 0";
  final searchArgs = <Object?>[if (query.isNotEmpty) query];
  return dbWriteTransaction(database, (tx) async {
    final counts = (await tx.rawQuery(
      'SELECT COUNT(*) AS total, '
      'COALESCE(SUM(CASE WHEN $missed THEN 1 ELSE 0 END), 0) AS missed '
      'FROM $from WHERE $searchWhere',
      searchArgs,
    )).single;
    final where = <String>[
      searchWhere,
      if (missedOnly) '($missed)',
      if (cursorStartedAt != null && cursorCallId != null)
        '(($timestamp) < ? OR (($timestamp) = ? AND h.call_id > ?))',
    ];
    final rows = await tx.rawQuery(
      'SELECT h.*, c.username AS local_contact_name '
      'FROM $from WHERE ${where.join(' AND ')} '
      'ORDER BY ($timestamp) DESC, h.call_id ASC LIMIT ?',
      [
        ...searchArgs,
        if (cursorStartedAt != null && cursorCallId != null) ...[
          cursorTimestamp,
          cursorTimestamp,
          cursorCallId,
        ],
        limit,
      ],
    );
    return (
      rows: rows.map(Map<String, Object?>.of).toList(growable: false),
      total: counts['total'] as int,
      missed: counts['missed'] as int,
    );
  });
}

/// 409: the newest terminal call for each of [contactAccountPeerIds].
///
/// One query for the whole Orbit roster rather than one per contact. The rows
/// come back newest-first on the existing
/// `(contact_account_peer_id, started_at DESC, call_id ASC)` index, so the
/// caller keeps the FIRST row it sees per contact.
Future<List<Map<String, Object?>>> loadLatestCallHistoryForContacts(
  Database database,
  List<String> contactAccountPeerIds,
) async {
  if (contactAccountPeerIds.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  final placeholders = List<String>.filled(
    contactAccountPeerIds.length,
    '?',
  ).join(', ');
  return (await database.query(
    kCallHistoryTable,
    where: 'contact_account_peer_id IN ($placeholders)',
    whereArgs: contactAccountPeerIds,
    orderBy: 'contact_account_peer_id ASC, started_at DESC, call_id ASC',
  )).map(Map<String, Object?>.of).toList(growable: false);
}

/// 410: the ONE definition of a call the unread badge may count.
///
/// An incoming call the user never took: `missed`, `cancelled` (the caller
/// hung up first, which is a missed call from the callee's side) or `busy`.
/// An answered call, one the user declined, a failed call, and everything
/// outgoing are all things the user already knows about, so counting them
/// would make the badge mean "something happened" instead of "you missed
/// something".
const String kUnreadCallHistoryPredicate =
    "direction = 'incoming' AND "
    "status IN ('missed', 'cancelled', 'busy') AND "
    'read_at IS NULL';

/// Unread call counts keyed by contact. Contacts with none are OMITTED, so a
/// caller can merge this into an existing count map without zero-writes.
Future<Map<String, int>> loadUnreadCallCountsForContacts(
  Database database,
  List<String> contactAccountPeerIds,
) async {
  if (contactAccountPeerIds.isEmpty) return const <String, int>{};
  final placeholders = List<String>.filled(
    contactAccountPeerIds.length,
    '?',
  ).join(', ');
  final rows = await database.rawQuery(
    'SELECT contact_account_peer_id AS peer_id, COUNT(*) AS unread '
    'FROM $kCallHistoryTable '
    'WHERE contact_account_peer_id IN ($placeholders) '
    'AND $kUnreadCallHistoryPredicate '
    'GROUP BY contact_account_peer_id',
    contactAccountPeerIds,
  );
  return <String, int>{
    for (final row in rows)
      if (row['peer_id'] is String && (row['unread'] as int? ?? 0) > 0)
        row['peer_id']! as String: row['unread']! as int,
  };
}

/// Stamps this contact's unread calls as read. Returns how many changed.
///
/// Scoped by the SAME predicate the badge counts, so the column keeps exactly
/// one meaning and a completed or declined call is never stamped.
Future<int> markCallHistoryRead(
  Database database,
  String contactAccountPeerId,
  DateTime readAt,
) => database.update(
  kCallHistoryTable,
  <String, Object?>{'read_at': readAt.toUtc().toIso8601String()},
  where: 'contact_account_peer_id = ? AND $kUnreadCallHistoryPredicate',
  whereArgs: <Object?>[contactAccountPeerId],
);
