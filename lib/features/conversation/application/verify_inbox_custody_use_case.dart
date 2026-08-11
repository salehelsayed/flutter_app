import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

const int kRelayCustodySkewMarginMs = 12 * 60 * 60 * 1000;
const Duration kInboxCustodyRecheckInterval = Duration(hours: 6);
const Duration kCustodyStaleReceiptRestoreAfter = Duration(hours: 24);
const Duration kOldRelayZombieDefenseAge = Duration(days: 7);

typedef LoadInboxCustodyFn =
    Future<List<ConversationMessage>> Function({
      required Duration recheckOlderThan,
    });

typedef MarkCustodyCheckedFn =
    Future<void> Function(String messageId, {int? relayExpiresAtMs});

Future<int> verifyInboxCustody({
  required LoadInboxCustodyFn loadInboxCustody,
  required StoreInInboxDetailedFn storeInInboxDetailed,
  required MarkCustodyCheckedFn markCustodyChecked,
  required MessageRepository messageRepo,
  DateTime Function()? nowFn,
}) async {
  final now = (nowFn ?? DateTime.now)().toUtc();
  final rows = await loadInboxCustody(
    recheckOlderThan: kInboxCustodyRecheckInterval,
  );
  var checked = 0;

  for (final row in rows) {
    final envelope = row.wireEnvelope;
    if (envelope == null || envelope.isEmpty) continue;
    // 361: a fanout-marked generation is excluded at the DB loader and again
    // here — the verifier may never re-store the canonical witness to the
    // logical contact.
    if (row.directEventFanoutGenerationId != null) continue;
    if (!_shouldRecheck(row, now)) continue;

    try {
      final outcome = await storeInInboxDetailed(row.contactPeerId, envelope);
      checked++;
      await _applyOutcome(
        row: row,
        outcome: outcome,
        now: now,
        messageRepo: messageRepo,
        markCustodyChecked: markCustodyChecked,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INBOX_CUSTODY_VERIFY_ERROR',
        details: {'id': _shortId(row.id), 'error': e.toString()},
      );
    }
  }

  return checked;
}

bool _shouldRecheck(ConversationMessage row, DateTime now) {
  if (_isStaleUnreceipted(row, now)) return true;
  final expiresAtMs = row.relayExpiresAt;
  if (expiresAtMs == null) return true;
  final marginAt = DateTime.fromMillisecondsSinceEpoch(
    expiresAtMs - kRelayCustodySkewMarginMs,
    isUtc: true,
  );
  return !marginAt.isAfter(now);
}

bool _isStaleUnreceipted(ConversationMessage row, DateTime now) {
  final checkedAt = row.custodyCheckedAt == null
      ? null
      : DateTime.tryParse(row.custodyCheckedAt!)?.toUtc();
  final reference = checkedAt ?? DateTime.tryParse(row.timestamp)?.toUtc();
  if (reference == null) return false;
  return now.difference(reference) >= kCustodyStaleReceiptRestoreAfter;
}

Future<void> _applyOutcome({
  required ConversationMessage row,
  required InboxStoreOutcome outcome,
  required DateTime now,
  required MessageRepository messageRepo,
  required MarkCustodyCheckedFn markCustodyChecked,
}) async {
  if (_isOldRelayZombie(row, outcome, now) ||
      outcome.status == InboxStoreStatus.rejectedFull ||
      outcome.status == InboxStoreStatus.failed) {
    await _surfaceLostCustody(row, messageRepo);
    emitFlowEvent(
      layer: 'FL',
      event: 'INBOX_CUSTODY_LOST',
      details: {
        'id': _shortId(row.id),
        'status': outcome.status.name,
        if (outcome.errorCode != null) 'errorCode': outcome.errorCode,
      },
    );
    return;
  }

  await markCustodyChecked(row.id, relayExpiresAtMs: outcome.expiresAtMs);
  emitFlowEvent(
    layer: 'FL',
    event: outcome.status == InboxStoreStatus.duplicate
        ? 'INBOX_CUSTODY_DUPLICATE'
        : 'INBOX_CUSTODY_RESTORED',
    details: {
      'id': _shortId(row.id),
      if (outcome.expiresAtMs != null) 'expiresAtMs': outcome.expiresAtMs,
    },
  );
}

bool _isOldRelayZombie(
  ConversationMessage row,
  InboxStoreOutcome outcome,
  DateTime now,
) {
  if (outcome.status != InboxStoreStatus.duplicate) return false;
  final messageTime = DateTime.tryParse(row.timestamp)?.toUtc();
  if (messageTime == null) return false;
  return now.difference(messageTime) > kOldRelayZombieDefenseAge;
}

Future<void> _surfaceLostCustody(
  ConversationMessage row,
  MessageRepository messageRepo,
) async {
  final transitioned = await messageRepo.conditionalTransitionStatus(
    row.id,
    fromStatus: 'inboxed',
    toStatus: 'sent',
  );
  if (transitioned <= 0) return;

  // The status CAS above is already the complete persisted mutation. A stale
  // full-row save here can only widen the race surface and can reinsert a
  // parent that contact deletion removed after the CAS.
}

String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;
