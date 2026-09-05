import 'package:flutter_app/core/database/helpers/call_history_db_helpers.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../domain/call_id.dart';
import 'call_history_repository.dart';

final class CallHistoryRepositoryImpl implements CallHistoryRepository {
  const CallHistoryRepositoryImpl(this.database);

  final Database database;

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) =>
      insertCallHistoryTerminal(database, entry.toMap());

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async {
    final row = await loadCallHistoryById(database, callId.value);
    return row == null ? null : CallHistoryEntry.fromMap(row);
  }

  /// 409: newest-first rows for a batch of contacts, for the Orbit rows.
  Future<List<CallHistoryEntry>> latestForContacts(
    List<String> contactAccountPeerIds,
  ) async => (await loadLatestCallHistoryForContacts(
    database,
    contactAccountPeerIds,
  )).map(CallHistoryEntry.fromMap).toList(growable: false);

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => (await loadCallHistoryForContact(
    database,
    contactAccountPeerId,
  )).map(CallHistoryEntry.fromMap).toList(growable: false);
}
