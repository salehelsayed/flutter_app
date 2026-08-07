import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

import '../../features/conversation/domain/repositories/fake_reaction_repository.dart';

/// Purpose-built authored-reaction adapter. Receiver/group fakes remain
/// intentionally incapable of sender custody.
class InMemoryDirectReactionCustodyRepository extends FakeReactionRepository
    implements OutgoingDirectReactionInboxCustodyRepository {
  InMemoryDirectReactionCustodyRepository({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, DirectReactionInboxCustodyOutboxEntry> _custody = {};

  bool custodySupported = true;
  bool refuseStage = false;
  bool throwOnStage = false;
  bool throwOnCompletion = false;
  bool throwOnFailureRecord = false;
  DirectReactionInboxCustodyCompletionOutcome? forcedCompletionOutcome;
  int stageCallCount = 0;
  int completionCallCount = 0;
  int failureRecordCallCount = 0;
  final List<DirectReactionInboxCustodyOutboxEntry> completionExpected = [];
  final List<DirectReactionInboxCustodyOutboxEntry> failureExpected = [];
  final List<String> failureErrorCodes = [];

  List<DirectReactionInboxCustodyOutboxEntry> get custodyRows =>
      _custody.values.toList(growable: false);

  @override
  bool get supportsDirectReactionInboxCustody => custodySupported;

  String _key(String recipientPeerId, String eventId) =>
      '$recipientPeerId\u0000$eventId';

  @override
  Future<DirectReactionCustodyStageResult>
  stageOutgoingDirectReactionInboxCustody({
    required MessageReaction reaction,
    required String recipientPeerId,
    required String action,
    required String wireEnvelope,
  }) async {
    stageCallCount++;
    if (throwOnStage) throw StateError('synthetic custody stage failure');
    if (!custodySupported || refuseStage) {
      return const DirectReactionCustodyStageResult.refused();
    }

    final key = _key(recipientPeerId, reaction.id);
    final existingCustody = _custody[key];
    if (existingCustody != null) {
      if (existingCustody.wireEnvelope != wireEnvelope) {
        return const DirectReactionCustodyStageResult.refused();
      }
      return DirectReactionCustodyStageResult(
        outcome: DirectReactionCustodyStageOutcome.idempotent,
        reaction: reaction,
        custody: existingCustody,
      );
    }

    final current = await getReactionForSenderIncludingRemoved(
      messageId: reaction.messageId,
      senderPeerId: reaction.senderPeerId,
    );
    final incomingAt = DateTime.tryParse(reaction.timestamp);
    final currentAt = current == null
        ? null
        : DateTime.tryParse(current.removedAt ?? current.timestamp);
    final isOlder =
        incomingAt != null &&
        currentAt != null &&
        incomingAt.isBefore(currentAt);
    if (!isOlder) {
      await saveReaction(
        action == 'remove'
            ? reaction.copyWith(removedAt: reaction.timestamp)
            : reaction.copyWith(clearRemovedAt: true),
      );
    }

    final custody = DirectReactionInboxCustodyOutboxEntry(
      recipientPeerId: recipientPeerId,
      eventId: reaction.id,
      wireEnvelope: wireEnvelope,
      retryCount: 0,
      lastAttemptAt: null,
      lastErrorCode: null,
      createdAt: reaction.createdAt,
      updatedAt: reaction.createdAt,
    );
    _custody[key] = custody;
    return DirectReactionCustodyStageResult(
      outcome: DirectReactionCustodyStageOutcome.applied,
      reaction: reaction,
      custody: custody,
    );
  }

  @override
  Future<List<DirectReactionInboxCustodyOutboxEntry>>
  loadDirectReactionInboxCustody({int limit = 50}) async {
    final rows = _custody.values.toList()
      ..sort((a, b) {
        final attempted = (a.lastAttemptAt ?? '').compareTo(
          b.lastAttemptAt ?? '',
        );
        if (attempted != 0) return attempted;
        return a.createdAt.compareTo(b.createdAt);
      });
    return rows.take(limit.clamp(0, 50)).toList(growable: false);
  }

  @override
  Future<DirectReactionInboxCustodyOutboxEntry?>
  loadDirectReactionInboxCustodyForEvent({
    required String recipientPeerId,
    required String eventId,
  }) async => _custody[_key(recipientPeerId, eventId)];

  @override
  Future<bool> recordDirectReactionInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) async {
    failureRecordCallCount++;
    failureExpected.add(expected);
    failureErrorCodes.add(errorCode);
    if (throwOnFailureRecord) {
      throw StateError('synthetic custody failure-record error');
    }
    final key = _key(expected.recipientPeerId, expected.eventId);
    final current = _custody[key];
    if (current == null || current.wireEnvelope != expected.wireEnvelope) {
      return false;
    }
    final attemptedAt = _now().toUtc().toIso8601String();
    _custody[key] = current.copyWith(
      retryCount: current.retryCount + 1,
      lastAttemptAt: attemptedAt,
      lastErrorCode: errorCode,
      updatedAt: attemptedAt,
    );
    return true;
  }

  @override
  Future<DirectReactionInboxCustodyCompletionOutcome>
  completeAcceptedDirectReactionInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
  }) async {
    completionCallCount++;
    completionExpected.add(expected);
    if (throwOnCompletion) {
      throw StateError('synthetic custody completion failure');
    }
    final forced = forcedCompletionOutcome;
    if (forced != null) return forced;
    final key = _key(expected.recipientPeerId, expected.eventId);
    final current = _custody[key];
    if (current == null) {
      return DirectReactionInboxCustodyCompletionOutcome.absent;
    }
    if (current.wireEnvelope != expected.wireEnvelope) {
      return DirectReactionInboxCustodyCompletionOutcome.stale;
    }
    _custody.remove(key);
    return DirectReactionInboxCustodyCompletionOutcome.completed;
  }
}
