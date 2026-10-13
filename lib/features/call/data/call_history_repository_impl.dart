import 'package:flutter_app/core/database/helpers/call_history_db_helpers.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../domain/call_id.dart';
import 'call_history_repository.dart';

final class CallHistoryRepositoryImpl
    implements CallHistoryRepository, CallHistoryBrowser {
  const CallHistoryRepositoryImpl(this.database);

  final Database database;

  @override
  Future<CallHistoryPage> browse({
    bool missedOnly = false,
    String search = '',
    CallHistoryCursor? cursor,
    int pageSize = 50,
  }) {
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }
    return _browse(
      missedOnly: missedOnly,
      search: search,
      cursor: cursor,
      pageSize: pageSize,
    );
  }

  Future<CallHistoryPage> _browse({
    required bool missedOnly,
    required String search,
    required CallHistoryCursor? cursor,
    required int pageSize,
  }) async {
    final page = await loadCallHistoryPage(
      database,
      missedOnly: missedOnly,
      search: search,
      limit: pageSize + 1,
      cursorStartedAt: cursor?.startedAt.toUtc().toIso8601String(),
      cursorCallId: cursor?.callId.value,
    );
    final rows = page.rows
        .take(pageSize)
        .map(
          (map) => CallHistoryListRow(
            CallHistoryEntry.fromMap(map),
            map['local_contact_name'] as String?,
          ),
        )
        .toList(growable: false);
    return CallHistoryPage(
      rows: List.unmodifiable(rows),
      total: page.total,
      missed: page.missed,
      next: page.rows.length <= pageSize || rows.isEmpty
          ? null
          : CallHistoryCursor(
              rows.last.entry.startedAt,
              rows.last.entry.callId,
            ),
    );
  }

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) =>
      insertCallHistoryTerminal(database, entry.toMap());

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async {
    final row = await loadCallHistoryById(database, callId.value);
    return row == null ? null : CallHistoryEntry.fromMap(row);
  }

  /// 410: unread missed-call counts for a batch of contacts.
  Future<Map<String, int>> unreadCallCountsForContacts(
    List<String> contactAccountPeerIds,
  ) => loadUnreadCallCountsForContacts(database, contactAccountPeerIds);

  /// 410: stamps this contact's unread calls as read when the chat is opened.
  Future<int> markCallsRead(String contactAccountPeerId, DateTime readAt) =>
      markCallHistoryRead(database, contactAccountPeerId, readAt);

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
