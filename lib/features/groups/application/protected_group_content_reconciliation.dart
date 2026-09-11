import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/database/helpers/group_media_key_snapshot.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_reaction_display_terminal_db_helpers.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const _reconciliationPageReason = 'authority_reconciliation_page';
const _reconciliationCompleteReason = 'authority_reconciliation_complete';

typedef LoadPreparedGroupAuthorityPage =
    Future<List<AuthenticatedGroupAuthorityProof>> Function({
      String? afterSourceTimestamp,
      String? afterSourceEventId,
      required int limit,
    });

typedef LoadExactGroupAuthorityPhase =
    Future<AuthenticatedGroupAuthorityProof?> Function({
      required AuthenticatedGroupAuthorityPhase phase,
      required String eventId,
    });

typedef LoadProtectedContentReconciliationRow =
    Future<Map<String, Object?>?> Function(String authorityEventId);

enum ProtectedGroupContentRetryAuthorityDisposition {
  eligible,
  stale,
  prerequisiteWaiting,
  failClosed,
}

typedef ClassifyProtectedGroupContentRetryAuthority =
    Future<ProtectedGroupContentRetryAuthorityDisposition> Function({
      required String groupId,
      required GroupContentAuthorityVersion observedAuthority,
      required DateTime contentAt,
      required String contentEventId,
    });

typedef ValidateProtectedContentHistoricalAuthority =
    Future<bool> Function({
      required String groupId,
      required String payloadType,
      required String contentEventId,
      required DateTime eventAt,
      required GroupContentAuthorityVersion authorityVersion,
      required String logicalSenderPeerId,
      required String senderDeviceId,
      required String senderTransportPeerId,
      required String senderPublicKey,
    });

typedef TerminalizePreparedProtectedGroupContent =
    Future<bool> Function({
      GroupMediaKeySnapshot? mediaKeySnapshot,
      required DatabaseExecutor txn,
      required String groupId,
      required String payloadType,
      required String contentEventId,
      required String ownerKind,
      required String ownerId,
      required Map<String, Object?> eventPayload,
      required String terminalSourcePeerId,
      required String terminalSourceEventId,
      required String terminalSourceTimestamp,
      required Map<String, Object?> terminalEventPayload,
    });

/// Classifies one already-staged strict owner against authenticated authority
/// history before another relay store or final local completion. An unfinished
/// transition is never collapsed into stale: retry waits until its authenticated
/// terminal phase and content reconciliation are durable.
Future<ProtectedGroupContentRetryAuthorityDisposition>
classifyProtectedGroupContentRetryAuthority({
  required String groupId,
  required GroupContentAuthorityVersion observedAuthority,
  required DateTime contentAt,
  required String contentEventId,
  required LoadPreparedGroupAuthorityPage loadPreparedPage,
  required LoadExactGroupAuthorityPhase loadExactPhase,
  required LoadProtectedContentReconciliationRow loadReconciliationRow,
  int pageSize = 200,
}) async {
  if (pageSize < 1 || pageSize > 200) {
    throw RangeError.range(pageSize, 1, 200, 'pageSize');
  }
  if (groupId.isEmpty ||
      contentEventId.isEmpty ||
      observedAuthority.eventId.isEmpty ||
      observedAuthority.keyEpoch < 0) {
    return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
  }
  try {
    final genesis = await loadExactPhase(
      phase: AuthenticatedGroupAuthorityPhase.genesis,
      eventId: observedAuthority.eventId,
    );
    final complete = await loadExactPhase(
      phase: AuthenticatedGroupAuthorityPhase.complete,
      eventId: observedAuthority.eventId,
    );
    if (genesis != null && complete != null) {
      return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
    }
    final observed = genesis ?? complete;
    if (observed == null ||
        observed.groupId != groupId ||
        observed.eventId != observedAuthority.eventId ||
        observed.eventAt.toUtc() != observedAuthority.eventAt.toUtc() ||
        observed.keyEpoch != observedAuthority.keyEpoch) {
      return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
    }
    var waiting = false;
    var stale = false;
    if (complete != null &&
        !isProtectedGroupContentReconciliationCompleteRow(
          await loadReconciliationRow(complete.eventId),
          authority: complete,
        )) {
      waiting = true;
    }

    String? afterAt;
    String? afterId;
    while (true) {
      final page = await loadPreparedPage(
        afterSourceTimestamp: afterAt,
        afterSourceEventId: afterId,
        limit: pageSize,
      );
      if (page.isEmpty) {
        return stale
            ? ProtectedGroupContentRetryAuthorityDisposition.stale
            : waiting
            ? ProtectedGroupContentRetryAuthorityDisposition.prerequisiteWaiting
            : ProtectedGroupContentRetryAuthorityDisposition.eligible;
      }
      for (final prepared in page) {
        if (prepared.groupId != groupId) {
          return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
        }
        if (!_authoritySortsAfterObserved(prepared, observedAuthority)) {
          continue;
        }
        final aborted = await loadExactPhase(
          phase: AuthenticatedGroupAuthorityPhase.aborted,
          eventId: prepared.eventId,
        );
        final settled = await loadExactPhase(
          phase: AuthenticatedGroupAuthorityPhase.complete,
          eventId: prepared.eventId,
        );
        if (aborted != null && settled != null) {
          return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
        }
        if (aborted != null) {
          if (!_sameAuthorityProof(aborted, prepared)) {
            return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
          }
          continue;
        }
        if (settled == null) {
          waiting = true;
          continue;
        }
        if (!_sameAuthorityProof(settled, prepared)) {
          return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
        }
        if (!isProtectedGroupContentReconciliationCompleteRow(
          await loadReconciliationRow(settled.eventId),
          authority: settled,
        )) {
          waiting = true;
          continue;
        }
        if (_authoritySortsAtOrBeforeContent(
          prepared,
          contentAt: contentAt,
          contentEventId: contentEventId,
        )) {
          stale = true;
        }
      }
      if (page.length < pageSize) {
        return stale
            ? ProtectedGroupContentRetryAuthorityDisposition.stale
            : waiting
            ? ProtectedGroupContentRetryAuthorityDisposition.prerequisiteWaiting
            : ProtectedGroupContentRetryAuthorityDisposition.eligible;
      }
      final last = page.last;
      final nextAt = fixedGroupAuthorityUtc(last.eventAt);
      final nextId = authenticatedGroupAuthoritySourceEventId(
        AuthenticatedGroupAuthorityPhase.prepared,
        last.eventId,
      );
      if (nextAt == afterAt && nextId == afterId) {
        return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
      }
      afterAt = nextAt;
      afterId = nextId;
    }
  } on GroupEventLogTamperException {
    return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
  } catch (_) {
    return ProtectedGroupContentRetryAuthorityDisposition.failClosed;
  }
}

bool _authoritySortsAfterObserved(
  AuthenticatedGroupAuthorityProof candidate,
  GroupContentAuthorityVersion observed,
) {
  final at = candidate.eventAt.toUtc().compareTo(observed.eventAt.toUtc());
  return at > 0 ||
      (at == 0 && candidate.eventId.compareTo(observed.eventId) > 0);
}

bool _sameAuthorityProof(
  AuthenticatedGroupAuthorityProof left,
  AuthenticatedGroupAuthorityProof right,
) =>
    left.signature == right.signature &&
    left.canonicalSignedPayload() == right.canonicalSignedPayload();

bool _authoritySortsAtOrBeforeContent(
  AuthenticatedGroupAuthorityProof authority, {
  required DateTime contentAt,
  required String contentEventId,
}) {
  final at = authority.eventAt.toUtc().compareTo(contentAt.toUtc());
  return at < 0 ||
      (at == 0 && authority.eventId.compareTo(contentEventId) <= 0);
}

/// Returns true when any authenticated PREPARED authority lacks an exact
/// terminal phase, or completed without its protected-content reconciliation
/// fact. Pages are bounded; pagination continues to exhaustion so an older
/// unfinished transition cannot hide behind a newer completed transition.
Future<bool> hasPendingProtectedGroupContentAuthority({
  required String groupId,
  required LoadPreparedGroupAuthorityPage loadPreparedPage,
  required LoadExactGroupAuthorityPhase loadExactPhase,
  required LoadProtectedContentReconciliationRow loadReconciliationRow,
  ReconcileCompletedProtectedGroupAuthority? repairCompletedAuthority,
  int pageSize = 200,
}) async {
  if (pageSize < 1 || pageSize > 200) {
    throw RangeError.range(pageSize, 1, 200, 'pageSize');
  }
  String? afterAt;
  String? afterId;
  while (true) {
    final page = await loadPreparedPage(
      afterSourceTimestamp: afterAt,
      afterSourceEventId: afterId,
      limit: pageSize,
    );
    if (page.isEmpty) return false;
    for (final prepared in page) {
      if (prepared.groupId != groupId) return true;
      final aborted = await loadExactPhase(
        phase: AuthenticatedGroupAuthorityPhase.aborted,
        eventId: prepared.eventId,
      );
      final complete = await loadExactPhase(
        phase: AuthenticatedGroupAuthorityPhase.complete,
        eventId: prepared.eventId,
      );
      if (aborted != null && complete != null) return true;
      if (aborted != null) {
        if (!_sameAuthorityProof(aborted, prepared)) return true;
        continue;
      }
      if (complete == null) return true;
      if (!_sameAuthorityProof(complete, prepared)) return true;
      var reconciliation = await loadReconciliationRow(prepared.eventId);
      if (!isProtectedGroupContentReconciliationCompleteRow(
        reconciliation,
        authority: prepared,
      )) {
        final repair = repairCompletedAuthority;
        if (repair == null || !await repair(complete)) return true;
        reconciliation = await loadReconciliationRow(prepared.eventId);
        if (!isProtectedGroupContentReconciliationCompleteRow(
          reconciliation,
          authority: prepared,
        )) {
          return true;
        }
      }
    }
    if (page.length < pageSize) return false;
    final last = page.last;
    final nextAt = fixedGroupAuthorityUtc(last.eventAt);
    final nextId = authenticatedGroupAuthoritySourceEventId(
      AuthenticatedGroupAuthorityPhase.prepared,
      last.eventId,
    );
    if (nextAt == afterAt && nextId == afterId) return true;
    afterAt = nextAt;
    afterId = nextId;
  }
}

/// Reconciles the bounded protected-content prefix invalidated by one newly
/// authenticated authority fact. Every page mutation, terminal evidence and
/// durable frontier commits in one transaction. A crash therefore resumes at
/// the last exact frontier and never exposes a half-reconciled authority.
Future<bool> reconcileProtectedGroupContentForAuthority({
  required Database db,
  required GroupRepository groupRepository,
  required AuthenticatedGroupAuthorityProof authority,
  required ValidateProtectedContentHistoricalAuthority
  validateHistoricalAuthority,
  TerminalizePreparedProtectedGroupContent? terminalizePreparedContent,
  GroupMediaKeyAccess? mediaKeyAccess,
  bool allowDominatingProjection = false,
  int pageSize = 200,
  int? stopAfterCommittedPages,
}) async {
  if (pageSize < 1 || pageSize > 200) {
    throw RangeError.range(pageSize, 1, 200, 'pageSize');
  }
  final group = await groupRepository.getGroup(authority.groupId);
  final latestKey = await groupRepository.getLatestKey(authority.groupId);
  if (group == null ||
      latestKey == null ||
      (allowDominatingProjection
          ? latestKey.keyGeneration < authority.keyEpoch
          : latestKey.keyGeneration != authority.keyEpoch)) {
    return false;
  }

  final completeSourceEventId =
      protectedGroupContentReconciliationCompleteSourceEventId(
        authority.eventId,
      );
  final existingComplete = await dbLoadGroupEventLogEntryExact(
    db,
    groupId: authority.groupId,
    sourceEventId: completeSourceEventId,
  );
  if (existingComplete != null) {
    return isProtectedGroupContentReconciliationCompleteRow(
      existingComplete,
      authority: authority,
    );
  }
  final recovered = await _loadFrontier(db, authority);
  final upperSequence =
      recovered?.upperSequence ??
      await _freezeProtectedUpperSequence(db, authority.groupId);
  var cursor = recovered?.lastProcessedSequence ?? 0;
  var afterSourceTimestamp = recovered?.lastSourceTimestamp;
  var afterSourceEventId = recovered?.lastSourceEventId;
  final reconciliationSourcePeerId = authority.actorAccountPeerId;
  var committedPages = 0;

  while (true) {
    final candidates = await _loadProtectedContentCutoffPage(
      db,
      groupId: authority.groupId,
      cutoffTimestamp: fixedGroupContentUtc(authority.eventAt),
      upperSequence: upperSequence,
      afterSourceTimestamp: afterSourceTimestamp,
      afterSourceEventId: afterSourceEventId,
      limit: pageSize,
    );
    if (candidates.isEmpty) {
      cursor = upperSequence;
      break;
    }
    final last = candidates.last;
    final lastSequence = last['sequence'] as int;
    final lastSourceTimestamp = last['source_timestamp'] as String;
    final lastSourceEventId = last['source_event_id'] as String;
    final invalid = <_InvalidProtectedContent>[];
    final invalidPrepared = <_PreparedProtectedContentFact>[];
    for (final row in candidates) {
      final parsed = _ProtectedContentFact.tryParse(row);
      if (parsed == null) {
        throw GroupEventLogTamperException(
          'malformed protected content during authority reconciliation',
        );
      }
      if (_contentSortsBeforeAuthority(parsed, authority)) continue;
      if (_contentObservedAuthorityAtOrAfter(parsed, authority)) continue;
      if (await _isContentAlreadyTerminalized(
        db,
        groupId: authority.groupId,
        fact: parsed,
      )) {
        continue;
      }
      if (row['event_type'] == protectedGroupContentPreparedEventType) {
        final prepared = _PreparedProtectedContentFact.tryParse(row);
        if (prepared == null) {
          throw GroupEventLogTamperException(
            'malformed prepared protected content during reconciliation',
          );
        }
        if (await _hasExactProtectedSuccess(db, prepared)) continue;
        invalidPrepared.add(prepared);
        continue;
      }
      // Receive rejects any event that was authored against a stale observed
      // authority when an intervening terminal authority sorts before it.
      // Reconciliation must apply the same rule independent of whether that
      // transition happened to change this sender's current role/device.
      final priorReaction =
          parsed.payloadType == groupOfflineReplayPayloadTypeReaction
          ? await _loadLatestValidReactionPrefix(
              db,
              authority: authority,
              invalid: parsed,
              validateHistoricalAuthority: validateHistoricalAuthority,
            )
          : null;
      invalid.add(
        _InvalidProtectedContent(
          row: row,
          fact: parsed,
          priorReaction: priorReaction,
        ),
      );
    }

    Future<void> commitPage(
      GroupMediaKeySnapshot? mediaKeySnapshot,
    ) => dbWriteTransaction<void>(db, (txn) async {
      for (final prepared in invalidPrepared) {
        final terminalize = terminalizePreparedContent;
        if (terminalize == null ||
            !await terminalize(
              mediaKeySnapshot: mediaKeySnapshot,
              txn: txn,
              groupId: authority.groupId,
              payloadType: prepared.fact.payloadType,
              contentEventId: prepared.fact.contentEventId,
              ownerKind: prepared.ownerKind,
              ownerId: prepared.ownerId,
              eventPayload: prepared.eventPayload,
              terminalSourcePeerId: authority.actorAccountPeerId,
              terminalSourceEventId: _terminalSourceEventId(
                authority.eventId,
                prepared.fact,
              ),
              terminalSourceTimestamp: fixedGroupContentUtc(authority.eventAt),
              terminalEventPayload: <String, Object?>{
                'reasonCode': 'authority_reconciliation_invalidated',
                'payloadType': prepared.fact.payloadType,
                'contentEventId': prepared.fact.contentEventId,
                'authorityEventId': authority.eventId,
                'preparedOwnerKind': prepared.ownerKind,
                'preparedOwnerId': prepared.ownerId,
                'replayEnvelopeHash': prepared.replayEnvelopeHash,
              },
            )) {
          throw StateError('protected prepared owner terminal CAS rejected');
        }
      }
      for (final candidate in invalid) {
        await _reconcileInvalidCandidate(
          txn,
          authority: authority,
          candidate: candidate,
        );
      }
      await _assertAuthorityProjectionInTransaction(
        txn,
        authority,
        allowDominatingProjection: allowDominatingProjection,
      );
      await _appendReconciliationFact(
        txn,
        authority: authority,
        sourceEventId: _pageSourceEventId(
          authority.eventId,
          upperSequence,
          lastSequence,
        ),
        payload: <String, Object?>{
          'reasonCode': _reconciliationPageReason,
          'groupId': authority.groupId,
          'authorityEventId': authority.eventId,
          'authorityEventAt': fixedGroupContentUtc(authority.eventAt),
          'authorityKeyEpoch': authority.keyEpoch,
          'upperSequence': upperSequence,
          'lastProcessedSequence': lastSequence,
          'lastSourceTimestamp': lastSourceTimestamp,
          'lastSourceEventId': lastSourceEventId,
          'invalidCount': invalid.length + invalidPrepared.length,
          'complete': false,
        },
      );
    }, exclusive: true);
    final mediaOwnerIds = invalidPrepared
        .where(
          (prepared) =>
              prepared.fact.payloadType ==
                  groupOfflineReplayPayloadTypeMessage &&
              prepared.ownerKind == 'group_message',
        )
        .map((prepared) => prepared.ownerId)
        .toSet();
    if (mediaKeyAccess != null && mediaOwnerIds.isNotEmpty) {
      // Resolve keys for this bounded page before SQLite owns a transaction,
      // and retain the shared media lifecycle scope until its commit/rollback.
      await mediaKeyAccess.run<void>(
        db: db,
        messageIds: mediaOwnerIds,
        action: commitPage,
      );
    } else {
      await commitPage(null);
    }
    cursor = lastSequence;
    afterSourceTimestamp = lastSourceTimestamp;
    afterSourceEventId = lastSourceEventId;
    committedPages++;
    if (stopAfterCommittedPages != null &&
        committedPages >= stopAfterCommittedPages) {
      return false;
    }
  }

  await dbWriteTransaction(db, (txn) async {
    // The group phase prevents new protected content while reconciling. This
    // final readback still proves the originally frozen content prefix was not
    // truncated or silently replaced before authority becomes visible.
    final remaining = await _loadProtectedContentCutoffPage(
      txn,
      groupId: authority.groupId,
      cutoffTimestamp: fixedGroupContentUtc(authority.eventAt),
      upperSequence: upperSequence,
      afterSourceTimestamp: afterSourceTimestamp,
      afterSourceEventId: afterSourceEventId,
      limit: 1,
    );
    if (remaining.isNotEmpty) {
      throw StateError('protected reconciliation frozen prefix changed');
    }
    await _assertAuthorityProjectionInTransaction(
      txn,
      authority,
      allowDominatingProjection: allowDominatingProjection,
    );
    if (reconciliationSourcePeerId != authority.actorAccountPeerId) {
      throw StateError('protected reconciliation authority projection drift');
    }
    await _appendReconciliationFact(
      txn,
      authority: authority,
      sourceEventId: completeSourceEventId,
      payload: <String, Object?>{
        'reasonCode': _reconciliationCompleteReason,
        'groupId': authority.groupId,
        'authorityEventId': authority.eventId,
        'authorityEventAt': fixedGroupContentUtc(authority.eventAt),
        'authorityKeyEpoch': authority.keyEpoch,
        'upperSequence': upperSequence,
        'lastProcessedSequence': cursor,
        'lastSourceTimestamp': afterSourceTimestamp,
        'lastSourceEventId': afterSourceEventId,
        'complete': true,
      },
    );
  }, exclusive: true);
  final exact = await dbLoadGroupEventLogEntryExact(
    db,
    groupId: authority.groupId,
    sourceEventId: completeSourceEventId,
  );
  return isProtectedGroupContentReconciliationCompleteRow(
    exact,
    authority: authority,
  );
}

Future<void> _assertAuthorityProjectionInTransaction(
  DatabaseExecutor txn,
  AuthenticatedGroupAuthorityProof authority, {
  required bool allowDominatingProjection,
}) async {
  final group = await txn.query(
    'groups',
    columns: const <String>['id'],
    where: 'id = ?',
    whereArgs: <Object?>[authority.groupId],
    limit: 1,
  );
  final keys = await txn.rawQuery(
    'SELECT MAX(key_generation) AS latest_key_generation '
    'FROM group_keys WHERE group_id = ?',
    <Object?>[authority.groupId],
  );
  final latest = keys.isEmpty ? null : keys.single['latest_key_generation'];
  if (group.isEmpty ||
      latest is! int ||
      (allowDominatingProjection
          ? latest < authority.keyEpoch
          : latest != authority.keyEpoch)) {
    throw StateError('protected reconciliation authority projection drift');
  }
}

Future<List<Map<String, Object?>>> _loadProtectedContentCutoffPage(
  DatabaseExecutor db, {
  required String groupId,
  required String cutoffTimestamp,
  required int upperSequence,
  String? afterSourceTimestamp,
  String? afterSourceEventId,
  required int limit,
}) {
  if (limit < 1 || limit > 200) {
    throw RangeError.range(limit, 1, 200, 'limit');
  }
  final cursorWhere = afterSourceTimestamp == null
      ? ''
      : 'AND (source_timestamp > ? OR '
            '(source_timestamp = ? AND source_event_id > ?)) ';
  return db.rawQuery(
    'SELECT * FROM group_event_log INDEXED BY idx_group_event_log_event_type '
    'WHERE group_id = ? AND event_type IN (?, ?, ?) '
    'AND source_timestamp >= ? AND sequence <= ? '
    '$cursorWhere'
    'ORDER BY source_timestamp ASC, source_event_id ASC LIMIT ?',
    <Object?>[
      groupId,
      protectedGroupMessageEventType,
      protectedGroupReactionEventType,
      protectedGroupContentPreparedEventType,
      cutoffTimestamp,
      upperSequence,
      if (afterSourceTimestamp != null) ...<Object?>[
        afterSourceTimestamp,
        afterSourceTimestamp,
        afterSourceEventId ?? '',
      ],
      limit,
    ],
  );
}

Future<bool> _isContentAlreadyTerminalized(
  DatabaseExecutor db, {
  required String groupId,
  required _ProtectedContentFact fact,
}) async {
  String? afterAt;
  String? afterId;
  while (true) {
    final rows = await dbLoadGroupEventLogTypePage(
      db,
      groupId: groupId,
      eventType: protectedGroupContentTerminalEventType,
      afterSourceTimestamp: afterAt,
      afterSourceEventId: afterId,
      newestFirst: true,
      limit: 200,
    );
    for (final row in rows) {
      if (isProtectedGroupContentTerminalRowExact(
        row,
        groupId: groupId,
        payloadType: fact.payloadType,
        contentEventId: fact.contentEventId,
      )) {
        return true;
      }
    }
    if (rows.length < 200) return false;
    final nextAt = rows.last['source_timestamp'] as String?;
    final nextId = rows.last['source_event_id'] as String?;
    if (nextAt == null ||
        nextId == null ||
        (nextAt == afterAt && nextId == afterId)) {
      throw StateError('protected terminal history cursor stalled');
    }
    afterAt = nextAt;
    afterId = nextId;
  }
}

Future<bool> _hasExactProtectedSuccess(
  Database db,
  _PreparedProtectedContentFact prepared,
) async {
  final fact = prepared.fact;
  final sourceEventId = fact.payloadType == groupOfflineReplayPayloadTypeMessage
      ? protectedGroupMessageSourceEventId(fact.contentEventId)
      : protectedGroupReactionSourceEventId(fact.contentEventId);
  final success = await dbLoadGroupEventLogEntryExact(
    db,
    groupId: prepared.groupId,
    sourceEventId: sourceEventId,
  );
  if (success == null) return false;
  final expectedType = fact.payloadType == groupOfflineReplayPayloadTypeMessage
      ? protectedGroupMessageEventType
      : protectedGroupReactionEventType;
  if (success['event_type'] != expectedType ||
      success['source_peer_id'] != fact.logicalSenderPeerId ||
      success['source_timestamp'] != fact.timestamp ||
      success['canonical_payload'] !=
          canonicalizeGroupEventLogPayload(prepared.eventPayload)) {
    throw GroupEventLogTamperException(
      'prepared protected content conflicts with success evidence',
    );
  }
  return true;
}

Future<_PriorProtectedReaction?> _loadLatestValidReactionPrefix(
  Database db, {
  required AuthenticatedGroupAuthorityProof authority,
  required _ProtectedContentFact invalid,
  required ValidateProtectedContentHistoricalAuthority
  validateHistoricalAuthority,
}) async {
  final messageId = invalid.payload['messageId'];
  final senderPeerId = invalid.payload['senderPeerId'];
  if (messageId is! String || senderPeerId is! String) return null;
  String? afterAt;
  String? afterId;
  while (true) {
    final rows = await dbLoadGroupEventLogTypePage(
      db,
      groupId: authority.groupId,
      eventType: protectedGroupReactionEventType,
      afterSourceTimestamp: afterAt,
      afterSourceEventId: afterId,
      throughSourceTimestamp: fixedGroupContentUtc(authority.eventAt),
      newestFirst: true,
      limit: 200,
    );
    for (final row in rows) {
      final candidate = _ProtectedContentFact.tryParse(row);
      if (candidate == null ||
          candidate.contentEventId == invalid.contentEventId ||
          candidate.payload['messageId'] != messageId ||
          candidate.payload['senderPeerId'] != senderPeerId ||
          !_contentSortsBeforeAuthority(candidate, authority) ||
          await _isContentAlreadyTerminalized(
            db,
            groupId: authority.groupId,
            fact: candidate,
          )) {
        continue;
      }
      final historicallyValid = await validateHistoricalAuthority(
        groupId: authority.groupId,
        payloadType: candidate.payloadType,
        contentEventId: candidate.contentEventId,
        eventAt: candidate.eventAt,
        authorityVersion: GroupContentAuthorityVersion(
          eventAt: candidate.authorityEventAt,
          eventId: candidate.authorityEventId,
          keyEpoch: candidate.authorityKeyEpoch,
        ),
        logicalSenderPeerId: candidate.logicalSenderPeerId,
        senderDeviceId: candidate.senderDeviceId,
        senderTransportPeerId: candidate.senderTransportPeerId,
        senderPublicKey: candidate.senderPublicKey,
      );
      if (historicallyValid) {
        return _PriorProtectedReaction(row: row, fact: candidate);
      }
    }
    if (rows.length < 200) return null;
    final nextAt = rows.last['source_timestamp'] as String?;
    final nextId = rows.last['source_event_id'] as String?;
    if (nextAt == null ||
        nextId == null ||
        (nextAt == afterAt && nextId == afterId)) {
      throw StateError('protected reaction prefix cursor stalled');
    }
    afterAt = nextAt;
    afterId = nextId;
  }
}

Future<void> _reconcileInvalidCandidate(
  DatabaseExecutor txn, {
  required AuthenticatedGroupAuthorityProof authority,
  required _InvalidProtectedContent candidate,
}) async {
  final fact = candidate.fact;
  if (fact.payloadType == groupOfflineReplayPayloadTypeMessage) {
    final rows = await txn.query(
      'group_messages',
      columns: const <String>['id', 'group_id', 'sender_peer_id', 'timestamp'],
      where: 'id = ? AND group_id = ?',
      whereArgs: <Object?>[fact.contentEventId, authority.groupId],
      limit: 1,
    );
    if (rows.isNotEmpty &&
        rows.single['sender_peer_id'] == fact.logicalSenderPeerId &&
        _sameUtcInstant(rows.single['timestamp'], fact.timestamp)) {
      await dbDeleteGroupNotificationDisplayOutboxForMessage(
        txn,
        groupId: authority.groupId,
        messageId: fact.contentEventId,
        // The protected terminal fact is appended below, but READY must also
        // survive this transaction for an already-PUBLISHING ledger attempt.
        preserveReadyCustody: true,
      );
      await txn.delete(
        'message_reactions',
        where: 'message_id = ?',
        whereArgs: <Object?>[fact.contentEventId],
      );
      await txn.delete(
        'group_reaction_replay_outbox',
        where: 'group_id = ? AND message_id = ?',
        whereArgs: <Object?>[authority.groupId, fact.contentEventId],
      );
      await txn.delete(
        'group_messages',
        where: 'id = ? AND group_id = ?',
        whereArgs: <Object?>[fact.contentEventId, authority.groupId],
      );
    }
  } else {
    await _restoreReactionPrefix(
      txn,
      authority: authority,
      invalid: fact,
      priorCandidate: candidate.priorReaction,
    );
  }
  await dbEnqueueGroupNotificationReconciliationOutbox(
    txn,
    groupId: authority.groupId,
  );
  await _appendReconciliationFact(
    txn,
    authority: authority,
    sourceEventId: _terminalSourceEventId(authority.eventId, fact),
    payload: <String, Object?>{
      'reasonCode': 'authority_reconciliation_invalidated',
      'groupId': authority.groupId,
      'authorityEventId': authority.eventId,
      'payloadType': fact.payloadType,
      'contentEventId': fact.contentEventId,
      'protectedSourceEventId': candidate.row['source_event_id'],
      'protectedEntryHash': candidate.row['entry_hash'],
    },
  );
}

bool _sameUtcInstant(Object? left, Object? right) {
  if (left is! String || right is! String) return false;
  final leftAt = DateTime.tryParse(left)?.toUtc();
  final rightAt = DateTime.tryParse(right)?.toUtc();
  return leftAt != null && rightAt != null && leftAt == rightAt;
}

Future<void> _restoreReactionPrefix(
  DatabaseExecutor txn, {
  required AuthenticatedGroupAuthorityProof authority,
  required _ProtectedContentFact invalid,
  required _PriorProtectedReaction? priorCandidate,
}) async {
  final payload = invalid.payload;
  final messageId = payload['messageId'];
  final senderPeerId = payload['senderPeerId'];
  if (messageId is! String || senderPeerId is! String) return;
  final currentRows = await txn.query(
    'message_reactions',
    where: 'message_id = ? AND sender_peer_id = ?',
    whereArgs: <Object?>[messageId, senderPeerId],
    limit: 1,
  );
  if (currentRows.isEmpty) return;
  final current = currentRows.single;
  final currentAction = current['removed_at'] == null ? 'add' : 'remove';
  final currentAt = DateTime.tryParse(
    (current['removed_at'] ?? current['timestamp']) as String,
  );
  if (currentAt == null) return;
  final currentTransition = buildGroupReactionTransitionId(
    groupId: authority.groupId,
    messageId: messageId,
    logicalActorPeerId: senderPeerId,
    action: currentAction,
    emoji: current['emoji'] as String,
    timestamp: currentAt,
  );
  if (currentTransition != invalid.contentEventId) return;

  var prior = priorCandidate?.fact;
  if (priorCandidate != null) {
    final exactRows = await txn.query(
      'group_event_log',
      where: 'group_id = ? AND source_event_id = ? AND event_type = ?',
      whereArgs: <Object?>[
        authority.groupId,
        priorCandidate.row['source_event_id'],
        protectedGroupReactionEventType,
      ],
      limit: 1,
    );
    if (exactRows.isEmpty ||
        exactRows.single['entry_hash'] != priorCandidate.row['entry_hash']) {
      throw StateError('protected reaction prior prefix changed');
    }
    if (await _isContentAlreadyTerminalized(
      txn,
      groupId: authority.groupId,
      fact: priorCandidate.fact,
    )) {
      prior = null;
    }
  }
  await dbDeleteGroupNotificationDisplayOutboxForReactionActor(
    txn,
    groupId: authority.groupId,
    messageId: messageId,
    actorPeerId: senderPeerId,
    preserveReadyCustody: true,
  );
  if (prior == null) {
    await txn.delete(
      'message_reactions',
      where: 'message_id = ? AND sender_peer_id = ?',
      whereArgs: <Object?>[messageId, senderPeerId],
    );
    return;
  }
  final previous = prior.payload;
  final action = previous['action'] as String;
  final timestamp = previous['timestamp'] as String;
  final restored = <String, Object?>{
    'id': previous['id'],
    'message_id': messageId,
    'emoji': previous['emoji'],
    'sender_peer_id': senderPeerId,
    'timestamp': timestamp,
    'created_at': timestamp,
    'removed_at': action == 'remove' ? timestamp : null,
  };
  if (action == 'add' &&
      await dbHasProtectedGroupReactionDisplayTerminalExact(
        txn,
        groupId: authority.groupId,
        transitionId: prior.contentEventId,
        messageId: messageId,
        actorPeerId: senderPeerId,
        reactionId: previous['id'] as String,
        eventTimestamp: timestamp,
      )) {
    restored['notification_display_terminal_event_id'] =
        boundedReactionEventIdentity(prior.contentEventId);
  }
  await txn.insert(
    'message_reactions',
    restored,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

bool _contentSortsBeforeAuthority(
  _ProtectedContentFact fact,
  AuthenticatedGroupAuthorityProof authority,
) {
  final at = fact.eventAt.compareTo(authority.eventAt.toUtc());
  return at < 0 ||
      (at == 0 && fact.contentEventId.compareTo(authority.eventId) < 0);
}

bool _contentObservedAuthorityAtOrAfter(
  _ProtectedContentFact fact,
  AuthenticatedGroupAuthorityProof authority,
) {
  final at = fact.authorityEventAt.compareTo(authority.eventAt.toUtc());
  return at > 0 ||
      (at == 0 && fact.authorityEventId.compareTo(authority.eventId) >= 0);
}

Future<int> _freezeProtectedUpperSequence(Database db, String groupId) async {
  final rows = await db.rawQuery(
    'SELECT MAX(sequence) FROM group_event_log '
    'WHERE group_id = ? AND event_type IN (?, ?, ?)',
    <Object?>[
      groupId,
      protectedGroupMessageEventType,
      protectedGroupReactionEventType,
      protectedGroupContentPreparedEventType,
    ],
  );
  return Sqflite.firstIntValue(rows) ?? 0;
}

Future<_ReconciliationFrontier?> _loadFrontier(
  Database db,
  AuthenticatedGroupAuthorityProof authority,
) async {
  String? afterAt;
  String? afterId;
  _ReconciliationFrontier? latest;
  int? frozenUpperSequence;
  while (true) {
    final rows = await dbLoadGroupEventLogTypePage(
      db,
      groupId: authority.groupId,
      eventType: protectedGroupContentTerminalEventType,
      afterSourceTimestamp: afterAt,
      afterSourceEventId: afterId,
      newestFirst: true,
      limit: 200,
    );
    for (final row in rows) {
      final encoded = row['canonical_payload'];
      if (encoded is! String) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(encoded);
      } on FormatException {
        continue;
      }
      if (decoded is! Map ||
          decoded['reasonCode'] != _reconciliationPageReason ||
          decoded['authorityEventId'] != authority.eventId) {
        continue;
      }
      final upper = decoded['upperSequence'];
      final processed = decoded['lastProcessedSequence'];
      final cursorAt = decoded['lastSourceTimestamp'];
      final cursorId = decoded['lastSourceEventId'];
      if (decoded['groupId'] != authority.groupId ||
          decoded['authorityEventAt'] !=
              fixedGroupContentUtc(authority.eventAt) ||
          decoded['authorityKeyEpoch'] != authority.keyEpoch ||
          decoded['complete'] != false ||
          upper is! int ||
          processed is! int ||
          upper < 0 ||
          processed < 0 ||
          processed > upper ||
          (cursorAt != null && cursorAt is! String) ||
          (cursorId != null && cursorId is! String) ||
          (cursorAt == null) != (cursorId == null) ||
          row['source_peer_id'] != authority.actorAccountPeerId ||
          row['source_timestamp'] != fixedGroupContentUtc(authority.eventAt) ||
          row['source_event_id'] !=
              _pageSourceEventId(authority.eventId, upper, processed)) {
        throw GroupEventLogTamperException(
          'protected reconciliation frontier authority mismatch',
        );
      }
      final candidate = _ReconciliationFrontier(
        upperSequence: upper,
        lastProcessedSequence: processed,
        lastSourceTimestamp: cursorAt as String?,
        lastSourceEventId: cursorId as String?,
      );
      if (candidate.lastSourceTimestamp == null) {
        // Legacy sequence-only frontiers cannot safely resume the indexed
        // timestamp ordering. Reprocess the frozen prefix idempotently.
        continue;
      }
      frozenUpperSequence ??= candidate.upperSequence;
      if (candidate.upperSequence != frozenUpperSequence) {
        throw GroupEventLogTamperException(
          'protected reconciliation frozen upper conflict',
        );
      }
      if (latest == null || _compareFrontier(candidate, latest) > 0) {
        latest = candidate;
      }
    }
    if (rows.length < 200) break;
    final nextAt = rows.last['source_timestamp'] as String?;
    final nextId = rows.last['source_event_id'] as String?;
    if (nextAt == null ||
        nextId == null ||
        (nextAt == afterAt && nextId == afterId)) {
      throw StateError('protected reconciliation frontier cursor stalled');
    }
    afterAt = nextAt;
    afterId = nextId;
  }
  return latest;
}

int _compareFrontier(
  _ReconciliationFrontier left,
  _ReconciliationFrontier right,
) {
  final timestamp = left.lastSourceTimestamp!.compareTo(
    right.lastSourceTimestamp!,
  );
  if (timestamp != 0) return timestamp;
  return left.lastSourceEventId!.compareTo(right.lastSourceEventId!);
}

Future<void> _appendReconciliationFact(
  DatabaseExecutor txn, {
  required AuthenticatedGroupAuthorityProof authority,
  required String sourceEventId,
  required Map<String, Object?> payload,
}) async {
  await dbAppendGroupEventLogEntryInTransaction(
    txn,
    groupId: authority.groupId,
    eventType: protectedGroupContentTerminalEventType,
    sourcePeerId: authority.actorAccountPeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: fixedGroupContentUtc(authority.eventAt),
    payload: payload,
  );
}

String _pageSourceEventId(String authorityId, int upper, int cursor) =>
    'pt1:${_b64('authority_reconciliation_page')}:'
    '${_b64(authorityId)}:$upper:$cursor';

String _terminalSourceEventId(String authorityId, _ProtectedContentFact fact) =>
    'pt1:${_b64('authority_invalidated_${fact.payloadType}')}:'
    '${_b64(fact.contentEventId)}:'
    '${sha256.convert(utf8.encode(authorityId))}';

String _b64(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

final class _ReconciliationFrontier {
  const _ReconciliationFrontier({
    required this.upperSequence,
    required this.lastProcessedSequence,
    required this.lastSourceTimestamp,
    required this.lastSourceEventId,
  });
  final int upperSequence;
  final int lastProcessedSequence;
  final String? lastSourceTimestamp;
  final String? lastSourceEventId;
}

final class _InvalidProtectedContent {
  const _InvalidProtectedContent({
    required this.row,
    required this.fact,
    required this.priorReaction,
  });
  final Map<String, Object?> row;
  final _ProtectedContentFact fact;
  final _PriorProtectedReaction? priorReaction;
}

final class _PriorProtectedReaction {
  const _PriorProtectedReaction({required this.row, required this.fact});
  final Map<String, Object?> row;
  final _ProtectedContentFact fact;
}

final class _PreparedProtectedContentFact {
  const _PreparedProtectedContentFact({
    required this.groupId,
    required this.fact,
    required this.ownerKind,
    required this.ownerId,
    required this.replayEnvelopeHash,
    required this.eventPayload,
  });

  final String groupId;
  final _ProtectedContentFact fact;
  final String ownerKind;
  final String ownerId;
  final String replayEnvelopeHash;
  final Map<String, Object?> eventPayload;

  static _PreparedProtectedContentFact? tryParse(Map<String, Object?> row) {
    try {
      if (row['event_type'] != protectedGroupContentPreparedEventType) {
        return null;
      }
      final raw = row['canonical_payload'];
      if (raw is! String) return null;
      final decodedRaw = jsonDecode(raw);
      if (decodedRaw is! Map) return null;
      final decoded = Map<String, Object?>.from(decodedRaw);
      const expectedKeys = <String>{
        'custodyKind',
        'groupId',
        'payloadType',
        'contentEventId',
        'authorityEventAt',
        'authorityEventId',
        'authorityKeyEpoch',
        'logicalSenderPeerId',
        'senderDeviceId',
        'senderTransportPeerId',
        'senderPublicKey',
        'recipientPeerIds',
        'payload',
        'preparedOwnerKind',
        'preparedOwnerId',
        'preparedOwnerStatus',
        'replayEnvelopeHash',
      };
      if (decoded.length != expectedKeys.length ||
          !decoded.keys.toSet().containsAll(expectedKeys)) {
        return null;
      }
      final fact = _ProtectedContentFact.tryParse(row);
      final groupId = decoded['groupId'];
      final ownerKind = decoded['preparedOwnerKind'];
      final ownerId = decoded['preparedOwnerId'];
      final ownerStatus = decoded['preparedOwnerStatus'];
      final replayHash = decoded['replayEnvelopeHash'];
      if (fact == null ||
          groupId is! String ||
          groupId != row['group_id'] ||
          ownerKind is! String ||
          ownerId is! String ||
          ownerId != fact.contentEventId ||
          replayHash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(replayHash) ||
          row['source_peer_id'] != fact.logicalSenderPeerId ||
          row['source_timestamp'] != fact.timestamp) {
        return null;
      }
      final expectedSourceId =
          fact.payloadType == groupOfflineReplayPayloadTypeMessage
          ? localPreparedProtectedGroupMessageSourceEventId(fact.contentEventId)
          : localPreparedProtectedGroupReactionSourceEventId(
              fact.contentEventId,
            );
      final validOwner =
          fact.payloadType == groupOfflineReplayPayloadTypeMessage
          ? ownerKind == 'group_message' && ownerStatus == 'queued_offline'
          : ownerKind == 'group_reaction' && ownerStatus == 'pending';
      if (!validOwner || row['source_event_id'] != expectedSourceId) {
        return null;
      }
      final eventPayload = Map<String, Object?>.from(decoded)
        ..remove('preparedOwnerKind')
        ..remove('preparedOwnerId')
        ..remove('preparedOwnerStatus')
        ..remove('replayEnvelopeHash');
      return _PreparedProtectedContentFact(
        groupId: groupId,
        fact: fact,
        ownerKind: ownerKind,
        ownerId: ownerId,
        replayEnvelopeHash: replayHash,
        eventPayload: eventPayload,
      );
    } catch (_) {
      return null;
    }
  }
}

final class _ProtectedContentFact {
  const _ProtectedContentFact({
    required this.payloadType,
    required this.contentEventId,
    required this.eventAt,
    required this.authorityEventAt,
    required this.authorityEventId,
    required this.authorityKeyEpoch,
    required this.logicalSenderPeerId,
    required this.senderDeviceId,
    required this.senderTransportPeerId,
    required this.senderPublicKey,
    required this.timestamp,
    required this.payload,
  });

  final String payloadType;
  final String contentEventId;
  final DateTime eventAt;
  final DateTime authorityEventAt;
  final String authorityEventId;
  final int authorityKeyEpoch;
  final String logicalSenderPeerId;
  final String senderDeviceId;
  final String senderTransportPeerId;
  final String senderPublicKey;
  final String timestamp;
  final Map<String, dynamic> payload;

  static _ProtectedContentFact? tryParse(Map<String, Object?> row) {
    try {
      final decoded = jsonDecode(row['canonical_payload'] as String);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final payloadRaw = map['payload'];
      if (payloadRaw is! Map) return null;
      final payload = Map<String, dynamic>.from(payloadRaw);
      final payloadType = map['payloadType'];
      final contentEventId = map['contentEventId'];
      final authorityAt = parseFixedGroupContentUtc(map['authorityEventAt']);
      final timestamp = payload['timestamp'];
      final eventAt = parseFixedGroupContentUtc(timestamp);
      if (payloadType is! String ||
          contentEventId is! String ||
          authorityAt == null ||
          eventAt == null ||
          timestamp is! String ||
          map['authorityEventId'] is! String ||
          map['authorityKeyEpoch'] is! int ||
          map['logicalSenderPeerId'] is! String ||
          map['senderDeviceId'] is! String ||
          map['senderTransportPeerId'] is! String ||
          map['senderPublicKey'] is! String) {
        return null;
      }
      return _ProtectedContentFact(
        payloadType: payloadType,
        contentEventId: contentEventId,
        eventAt: eventAt,
        authorityEventAt: authorityAt,
        authorityEventId: map['authorityEventId'] as String,
        authorityKeyEpoch: map['authorityKeyEpoch'] as int,
        logicalSenderPeerId: map['logicalSenderPeerId'] as String,
        senderDeviceId: map['senderDeviceId'] as String,
        senderTransportPeerId: map['senderTransportPeerId'] as String,
        senderPublicKey: map['senderPublicKey'] as String,
        timestamp: timestamp,
        payload: payload,
      );
    } catch (_) {
      return null;
    }
  }
}
