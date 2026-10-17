import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// SE-42 D12 (checklist CL2.7) synthetic fixture: an exact-millisecond incoming
/// missed call and a later incoming missed call in the same millisecond that
/// only microseconds separate. Test-only.
///
/// [D12Fixture.synthetic] also seeds an uncallable synthetic contact. A callable
/// fixture names an already paired disposable peer, whose contact is kept.
final class D12Fixture {
  const D12Fixture({
    required this.peerId,
    required this.olderCallId,
    required this.newerCallId,
  });

  static const synthetic = D12Fixture(
    peerId: d12ContactPeerId,
    olderCallId: 'd1200000-0000-4000-8000-000000000001',
    newerCallId: 'd1200000-0000-4000-8000-000000000002',
  );

  /// Distinct call ids per [round] so paired-peer rows never collide with
  /// [synthetic] or an earlier round. A later round seeds a newer pair, so its
  /// newest missed call becomes the contact's newest call again.
  static D12Fixture pairedPeer(String peerId, {int round = 1}) {
    if (round < 1 || round > 4) throw RangeError.range(round, 1, 4, 'round');
    String id(int n) =>
        'd1200000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
    return D12Fixture(
      peerId: peerId,
      olderCallId: id(2 * round + 1),
      newerCallId: id(2 * round + 2),
    );
  }

  final String peerId;
  final String olderCallId;
  final String newerCallId;
}

const d12ContactPeerId = '12D3KooWSeedFriendD12CallbackAAAAAAAAAAAAAAAAAAAAAAA';
const d12ContactUsername = 'D12 Synthetic';

/// Seeds the fixture. Repeating it keeps the first rows: contacts upsert to the
/// same values and call history keeps the first row per call id.
Future<void> seedD12Fixture(
  Database db, {
  required DateTime base,
  D12Fixture fixture = D12Fixture.synthetic,
}) async {
  final exactMillisecond = DateTime.utc(
    base.year,
    base.month,
    base.day,
    base.hour,
    base.minute,
    base.second,
    base.millisecond,
  );
  final existing = await dbLoadContact(db, fixture.peerId);
  if (existing == null) {
    if (fixture.peerId != d12ContactPeerId) {
      throw StateError('D12 paired peer is not a contact on this device');
    }
    await dbUpsertContact(
      db,
      ContactModel(
        peerId: d12ContactPeerId,
        publicKey: 'd12-synthetic-public-key',
        rendezvous: 'd12-synthetic',
        username: d12ContactUsername,
        signature: 'd12-synthetic-signature',
        scannedAt: exactMillisecond
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      ).toMap(),
    );
  }
  final repository = CallHistoryRepositoryImpl(db);
  await repository.upsertTerminal(
    _missed(fixture.peerId, fixture.olderCallId, exactMillisecond),
  );
  await repository.upsertTerminal(
    _missed(
      fixture.peerId,
      fixture.newerCallId,
      exactMillisecond.add(const Duration(microseconds: 500)),
    ),
  );
}

CallHistoryEntry _missed(String peerId, String id, DateTime startedAt) {
  final endedAt = startedAt.add(const Duration(seconds: 30));
  return CallHistoryEntry(
    callId: CallId.parse(id),
    contactAccountPeerId: peerId,
    direction: CallDirection.incoming,
    terminalReason: CallEndReason.noAnswer,
    status: CallHistoryStatus.missed,
    startedAt: startedAt,
    endedAt: endedAt,
    transportRoute: null,
    createdAt: endedAt,
    updatedAt: endedAt,
  );
}

final class D12Snapshot {
  const D12Snapshot({
    required this.rows,
    required this.unreadCalls,
    required this.contactUsername,
  });

  /// Stored rows for the synthetic contact, newest first, as raw column values.
  final List<Map<String, Object?>> rows;
  final int unreadCalls;
  final String? contactUsername;

  Map<String, Object?> toJson() => <String, Object?>{
    'rows': rows,
    'unreadCalls': unreadCalls,
    'contactUsername': contactUsername,
  };
}

/// Reads the fixture without changing it.
Future<D12Snapshot> d12Snapshot(
  Database db, {
  D12Fixture fixture = D12Fixture.synthetic,
}) async {
  final rows = await db.query(
    'call_history',
    where: 'contact_account_peer_id = ?',
    whereArgs: <Object?>[fixture.peerId],
  );
  final ordered = [...rows]
    ..sort(
      (a, b) => (b['call_id']! as String).compareTo(a['call_id']! as String),
    );
  final unread = await CallHistoryRepositoryImpl(
    db,
  ).unreadCallCountsForContacts(<String>[fixture.peerId]);
  final contact = await dbLoadContact(db, fixture.peerId);
  return D12Snapshot(
    rows: ordered.map((row) => Map<String, Object?>.of(row)).toList(),
    unreadCalls: unread[fixture.peerId] ?? 0,
    contactUsername: contact?['username'] as String?,
  );
}
