import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/features/contact_request/application/existing_contact_repair_policy.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

const _requests = 'contact_repair_requests';
const _peerState = 'contact_repair_peer_state';
const _clock = 'contact_repair_clock';
const _consent = 'contact_relationship_consent';

const _queuedStates = "('buildable', 'ready')";
const _pendingStates = "('buildable', 'ready', 'sending')";
const _terminalStates = "('completed', 'exhausted', 'expired', 'cancelled')";

/// SQLCipher implementation of [ContactRepairRepository] (DB v121).
///
/// Every reservation and state change is one write transaction or one
/// compare-and-set UPDATE, so concurrent callbacks and independent handles
/// converge on the primary key and the claim token. No bridge or network work
/// happens inside a transaction.
final class SqlContactRepairRepository implements ContactRepairRepository {
  SqlContactRepairRepository(this._db);

  final Database _db;

  @override
  Future<ContactRelationshipConsent?> readConsent(String peerId) async {
    final rows = await _db.query(
      _consent,
      columns: <String>['state', 'revision'],
      where: 'peer_id = ?',
      whereArgs: <Object?>[peerId],
    );
    if (rows.isEmpty) return null;
    return ContactRelationshipConsent(
      state: ContactRelationshipState.values.byName(
        rows.single['state']! as String,
      ),
      revision: rows.single['revision']! as int,
    );
  }

  @override
  Future<String?> lookupRequestDigest({
    required String peerId,
    required String requestId,
  }) async {
    final rows = await _db.query(
      _requests,
      columns: <String>['request_digest'],
      where: 'peer_id = ? AND request_id = ?',
      whereArgs: <Object?>[peerId, requestId],
    );
    return rows.isEmpty ? null : rows.single['request_digest']! as String;
  }

  @override
  Future<ContactRepairClaimOutcome> claimReply(ContactRepairClaim claim) {
    return dbWriteTransaction<ContactRepairClaimOutcome>(_db, (txn) async {
      final existing = await txn.query(
        _requests,
        columns: <String>['request_digest', 'reply_id', 'due_at_ms'],
        where: 'peer_id = ? AND request_id = ?',
        whereArgs: <Object?>[claim.peerId, claim.requestId],
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        if (row['request_digest'] != claim.requestDigest) {
          return const ContactRepairClaimOutcome(
            ContactRepairClaimStatus.conflict,
          );
        }
        return ContactRepairClaimOutcome(
          ContactRepairClaimStatus.duplicate,
          replyId: row['reply_id']! as String,
          dueAtMs: row['due_at_ms']! as int,
        );
      }

      if (!await _authorityIsCurrent(
        txn,
        peerId: claim.peerId,
        authorityFingerprint: claim.authorityFingerprint,
        relationshipRevision: claim.relationshipRevision,
      )) {
        return const ContactRepairClaimOutcome(
          ContactRepairClaimStatus.refused,
        );
      }

      final highWaterMs = await _readHighWater(txn);
      switch (signedRequestFreshness(
        signedAtMs: claim.signedAtMs,
        wallNowMs: claim.wallNowMs,
        highWaterMs: highWaterMs,
      )) {
        case ContactRepairFreshness.clockAnomaly:
          return const ContactRepairClaimOutcome(
            ContactRepairClaimStatus.clockAnomaly,
          );
        case ContactRepairFreshness.stale:
          return const ContactRepairClaimOutcome(
            ContactRepairClaimStatus.stale,
          );
        case ContactRepairFreshness.fresh:
          break;
      }
      final effectiveNowMs = await _advanceHighWater(
        txn,
        highWaterMs,
        claim.wallNowMs,
      );

      if (await _count(txn, 'peer_id = ? AND state IN $_pendingStates', [
                claim.peerId,
              ]) >=
              ContactRepairLimits.maxPendingPerPeer ||
          await _count(txn, 'state IN $_pendingStates', const []) >=
              ContactRepairLimits.maxPendingGlobal ||
          await _count(txn, 'peer_id = ?', [claim.peerId]) >=
              ContactRepairLimits.maxGuardsPerPeer ||
          await _count(txn, '1 = 1', const []) >=
              ContactRepairLimits.maxGuardsGlobal) {
        return const ContactRepairClaimOutcome(
          ContactRepairClaimStatus.overflow,
        );
      }

      final peerRows = await txn.query(
        _peerState,
        columns: <String>['next_reply_not_before_ms'],
        where: 'peer_id = ?',
        whereArgs: <Object?>[claim.peerId],
      );
      final notBeforeMs = peerRows.isEmpty
          ? 0
          : peerRows.single['next_reply_not_before_ms']! as int;
      final dueAtMs = notBeforeMs > effectiveNowMs
          ? notBeforeMs
          : effectiveNowMs;
      await txn.rawInsert(
        'INSERT INTO $_peerState '
        '(peer_id, next_reply_not_before_ms, supports_marked, updated_at_ms) '
        'VALUES (?, ?, 0, ?) '
        'ON CONFLICT(peer_id) DO UPDATE SET '
        'next_reply_not_before_ms = excluded.next_reply_not_before_ms, '
        'updated_at_ms = excluded.updated_at_ms',
        <Object?>[
          claim.peerId,
          dueAtMs + ContactRepairLimits.replyPacing.inMilliseconds,
          effectiveNowMs,
        ],
      );

      final replyId = const Uuid().v4();
      await txn.insert(_requests, <String, Object?>{
        'peer_id': claim.peerId,
        'request_id': claim.requestId,
        'request_digest': claim.requestDigest,
        'signed_at_ms': claim.signedAtMs,
        'guard_until_ms':
            claim.signedAtMs +
            ContactRepairLimits.guardRetention.inMilliseconds,
        'authority_fingerprint': claim.authorityFingerprint,
        'local_authority_fingerprint': claim.localAuthorityFingerprint,
        'relationship_revision': claim.relationshipRevision,
        'state': ContactRepairJobState.buildable.name,
        'reply_id': replyId,
        'due_at_ms': dueAtMs,
        'attempts': 0,
        'created_at_ms': effectiveNowMs,
        'updated_at_ms': effectiveNowMs,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      return ContactRepairClaimOutcome(
        ContactRepairClaimStatus.reserved,
        replyId: replyId,
        dueAtMs: dueAtMs,
      );
    });
  }

  @override
  Future<void> recordPeerSupportsMarked(String peerId) async {
    await _db.rawInsert(
      'INSERT INTO $_peerState '
      '(peer_id, next_reply_not_before_ms, supports_marked, updated_at_ms) '
      'VALUES (?, 0, 1, ?) '
      'ON CONFLICT(peer_id) DO UPDATE SET supports_marked = 1',
      <Object?>[peerId, DateTime.now().toUtc().millisecondsSinceEpoch],
    );
  }

  @override
  Future<bool> peerSupportsMarked(String peerId) async {
    final rows = await _db.query(
      _peerState,
      columns: <String>['supports_marked'],
      where: 'peer_id = ?',
      whereArgs: <Object?>[peerId],
    );
    return rows.isNotEmpty && rows.single['supports_marked'] == 1;
  }

  @override
  Future<List<ContactRepairJob>> takeDueJobs({
    required String claimToken,
    required int wallNowMs,
    required int limit,
  }) {
    return dbWriteTransaction<List<ContactRepairJob>>(_db, (txn) async {
      final room =
          ContactRepairLimits.maxTransmitting -
          await _count(txn, "state = 'sending'", const []);
      final take = limit < room ? limit : room;
      if (take <= 0) return const <ContactRepairJob>[];
      final effectiveNowMs = await _advanceHighWater(
        txn,
        await _readHighWater(txn),
        wallNowMs,
      );
      final due = await txn.query(
        _requests,
        columns: <String>['peer_id', 'request_id'],
        where: 'state IN $_queuedStates AND due_at_ms <= ? AND attempts < ?',
        whereArgs: <Object?>[effectiveNowMs, ContactRepairLimits.maxAttempts],
        orderBy: 'due_at_ms ASC, created_at_ms ASC',
        limit: take,
      );
      final claimed = <ContactRepairJob>[];
      for (final row in due) {
        final changed = await txn.rawUpdate(
          'UPDATE $_requests SET state = ?, claim_token = ?, '
          'attempts = attempts + 1, updated_at_ms = ? '
          'WHERE peer_id = ? AND request_id = ? AND state IN $_queuedStates',
          <Object?>[
            ContactRepairJobState.sending.name,
            claimToken,
            effectiveNowMs,
            row['peer_id'],
            row['request_id'],
          ],
        );
        if (changed != 1) continue;
        final job = await _readJob(
          txn,
          row['peer_id']! as String,
          row['request_id']! as String,
        );
        if (job != null) claimed.add(job);
      }
      return claimed;
    });
  }

  @override
  Future<bool> commitEnvelope({
    required ContactRepairJob job,
    required String claimToken,
    required String envelopeJson,
    required int? grantGeneration,
  }) async {
    final changed = await _db.rawUpdate(
      'UPDATE $_requests SET envelope_json = ?, grant_generation = ?, '
      'updated_at_ms = ? '
      "WHERE peer_id = ? AND request_id = ? AND state = 'sending' "
      'AND claim_token = ? AND envelope_json IS NULL',
      <Object?>[
        envelopeJson,
        grantGeneration,
        DateTime.now().toUtc().millisecondsSinceEpoch,
        job.peerId,
        job.requestId,
        claimToken,
      ],
    );
    return changed == 1;
  }

  @override
  Future<bool> stillOwns({
    required ContactRepairJob job,
    required String claimToken,
  }) async =>
      await _count(
        _db,
        "peer_id = ? AND request_id = ? AND state = 'sending' "
        'AND claim_token = ?',
        [job.peerId, job.requestId, claimToken],
      ) ==
      1;

  @override
  Future<bool> completeJob({
    required ContactRepairJob job,
    required String claimToken,
  }) => _finishOwned(job, claimToken, "'completed'", null);

  @override
  Future<bool> cancelJob({
    required ContactRepairJob job,
    required String claimToken,
  }) => _finishOwned(job, claimToken, "'cancelled'", null);

  @override
  Future<bool> releaseForRetry({
    required ContactRepairJob job,
    required String claimToken,
    required int dueAtMs,
  }) => _finishOwned(job, claimToken, _requeueState, dueAtMs);

  static const String _requeueState =
      "CASE WHEN attempts >= ${ContactRepairLimits.maxAttempts} "
      "THEN 'exhausted' WHEN envelope_json IS NULL THEN 'buildable' "
      "ELSE 'ready' END";

  Future<bool> _finishOwned(
    ContactRepairJob job,
    String claimToken,
    String stateExpression,
    int? dueAtMs,
  ) async {
    final changed = await _db.rawUpdate(
      'UPDATE $_requests SET state = $stateExpression, claim_token = NULL, '
      'due_at_ms = COALESCE(?, due_at_ms), updated_at_ms = ? '
      "WHERE peer_id = ? AND request_id = ? AND state = 'sending' "
      'AND claim_token = ?',
      <Object?>[
        dueAtMs,
        DateTime.now().toUtc().millisecondsSinceEpoch,
        job.peerId,
        job.requestId,
        claimToken,
      ],
    );
    return changed == 1;
  }

  @override
  Future<int> takeOverInFlight({required String newClaimToken}) =>
      _db.rawUpdate(
        'UPDATE $_requests SET state = $_requeueState, claim_token = NULL, '
        'updated_at_ms = ? '
        "WHERE state = 'sending' AND (claim_token IS NULL OR claim_token != ?)",
        <Object?>[DateTime.now().toUtc().millisecondsSinceEpoch, newClaimToken],
      );

  @override
  Future<int?> nextDueAtMs() async {
    final rows = await _db.rawQuery(
      'SELECT MIN(due_at_ms) AS due FROM $_requests '
      'WHERE state IN $_queuedStates AND attempts < ?',
      <Object?>[ContactRepairLimits.maxAttempts],
    );
    return rows.single['due'] as int?;
  }

  @override
  Future<int> collectGarbage({required int wallNowMs}) {
    return dbWriteTransaction<int>(_db, (txn) async {
      final effectiveNowMs = await _advanceHighWater(
        txn,
        await _readHighWater(txn),
        wallNowMs,
      );
      final expired = await txn.rawUpdate(
        "UPDATE $_requests SET state = 'expired', claim_token = NULL, "
        'updated_at_ms = ? WHERE state IN $_queuedStates AND guard_until_ms < ?',
        <Object?>[effectiveNowMs, effectiveNowMs],
      );
      final deleted = await txn.rawDelete(
        'DELETE FROM $_requests WHERE rowid IN ('
        'SELECT rowid FROM $_requests WHERE state IN $_terminalStates '
        'AND guard_until_ms < ? LIMIT ?)',
        <Object?>[effectiveNowMs, ContactRepairLimits.garbageBatch],
      );
      return expired + deleted;
    });
  }

  Future<bool> _authorityIsCurrent(
    DatabaseExecutor txn, {
    required String peerId,
    required String authorityFingerprint,
    required int relationshipRevision,
  }) async {
    final contacts = await txn.query(
      'contacts',
      columns: <String>['public_key', 'is_blocked'],
      where: 'peer_id = ?',
      whereArgs: <Object?>[peerId],
    );
    if (contacts.isEmpty || contacts.single['is_blocked'] == 1) return false;
    final String storedFingerprint;
    try {
      storedFingerprint = ed25519AuthorityFingerprint(
        contacts.single['public_key']! as String,
      );
    } on FormatException {
      return false;
    }
    if (storedFingerprint != authorityFingerprint) return false;
    final consent = await txn.query(
      _consent,
      columns: <String>['state', 'revision'],
      where: 'peer_id = ?',
      whereArgs: <Object?>[peerId],
    );
    final state = consent.isEmpty ? 'active' : consent.single['state'];
    final revision = consent.isEmpty ? 0 : consent.single['revision'];
    return state == 'active' && revision == relationshipRevision;
  }

  Future<int> _readHighWater(DatabaseExecutor txn) async {
    final rows = await txn.query(
      _clock,
      columns: <String>['high_water_ms'],
      where: 'id = 1',
    );
    return rows.isEmpty ? 0 : rows.single['high_water_ms']! as int;
  }

  Future<int> _advanceHighWater(
    DatabaseExecutor txn,
    int highWaterMs,
    int wallNowMs,
  ) async {
    if (wallNowMs <= highWaterMs) return highWaterMs;
    await txn.rawInsert(
      'INSERT INTO $_clock (id, high_water_ms) VALUES (1, ?) '
      'ON CONFLICT(id) DO UPDATE SET high_water_ms = excluded.high_water_ms',
      <Object?>[wallNowMs],
    );
    return wallNowMs;
  }

  Future<int> _count(
    DatabaseExecutor txn,
    String where,
    List<Object?> args,
  ) async {
    final rows = await txn.rawQuery(
      'SELECT COUNT(*) AS n FROM $_requests WHERE $where',
      args,
    );
    return rows.single['n']! as int;
  }

  Future<ContactRepairJob?> _readJob(
    DatabaseExecutor txn,
    String peerId,
    String requestId,
  ) async {
    final rows = await txn.query(
      _requests,
      where: 'peer_id = ? AND request_id = ?',
      whereArgs: <Object?>[peerId, requestId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ContactRepairJob(
      peerId: row['peer_id']! as String,
      requestId: row['request_id']! as String,
      replyId: row['reply_id']! as String,
      state: ContactRepairJobState.values.byName(row['state']! as String),
      authorityFingerprint: row['authority_fingerprint']! as String,
      localAuthorityFingerprint: row['local_authority_fingerprint']! as String,
      relationshipRevision: row['relationship_revision']! as int,
      attempts: row['attempts']! as int,
      dueAtMs: row['due_at_ms']! as int,
      claimToken: row['claim_token'] as String?,
      envelopeJson: row['envelope_json'] as String?,
      grantGeneration: row['grant_generation'] as int?,
    );
  }
}
