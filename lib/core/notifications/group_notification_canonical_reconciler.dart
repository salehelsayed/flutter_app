import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';

typedef GroupNotificationCanonicalContentResolver =
    Future<GroupNotificationCanonicalContentDecision> Function(
      String groupId,
      ConversationNotificationContentMetadata metadata,
    );
typedef GroupNotificationCanonicalReplacementLoader =
    Future<CanonicalConversationNotificationReplacement?> Function(
      String groupId,
      ConversationNotificationContentMetadata currentMetadata,
    );

/// Canonical local-state verdict for the exact content currently represented
/// by one managed group notification generation.
///
/// [unknown] is deliberately distinct from [retire]. A push can publish the OS
/// card before its inbox row materializes locally, so row absence without an
/// exact deletion/REMOVE/policy transition must retain durable reconciliation
/// custody and retry instead of mutating the current generation.
enum GroupNotificationCanonicalContentDecision { keep, retire, unknown }

/// Signals that cross-isolate notification generations changed too often for
/// one bounded reconciliation pass. Durable custody must retry later.
final class GroupNotificationCanonicalReconciliationRetryable
    implements Exception {
  const GroupNotificationCanonicalReconciliationRetryable();

  @override
  String toString() =>
      'group notification reconciliation requires another canonical pass';
}

/// Regenerates one group card from canonical local state after a delete,
/// reaction REMOVE, or group-policy/lifecycle transition.
///
/// The in-process keyed queue closes races with ordinary main-runtime shows.
/// Generation CAS closes the corresponding background-isolate/process race.
final class GroupNotificationCanonicalReconciler {
  GroupNotificationCanonicalReconciler({
    required GroupNotificationPresentationCoordinator coordinator,
    required ConversationNotificationGenerationCancellation
    generationCancellation,
    required ConversationNotificationGenerationReplacement
    generationReplacement,
    required GroupNotificationCanonicalContentResolver
    isCurrentContentCanonical,
    required GroupNotificationCanonicalReplacementLoader loadReplacement,
    this.maxGenerationAttempts = 3,
  }) : _coordinator = coordinator,
       _generationCancellation = generationCancellation,
       _generationReplacement = generationReplacement,
       _isCurrentContentCanonical = isCurrentContentCanonical,
       _loadReplacement = loadReplacement {
    if (maxGenerationAttempts <= 0) {
      throw ArgumentError.value(
        maxGenerationAttempts,
        'maxGenerationAttempts',
        'must be positive',
      );
    }
  }

  final GroupNotificationPresentationCoordinator _coordinator;
  final ConversationNotificationGenerationCancellation _generationCancellation;
  final ConversationNotificationGenerationReplacement _generationReplacement;
  final GroupNotificationCanonicalContentResolver _isCurrentContentCanonical;
  final GroupNotificationCanonicalReplacementLoader _loadReplacement;
  final int maxGenerationAttempts;

  Future<void> reconcile(String rawGroupId) {
    final groupId = rawGroupId.trim();
    if (groupId.isEmpty) {
      throw ArgumentError.value(rawGroupId, 'groupId', 'must not be empty');
    }
    return _coordinator.runForGroup(
      groupId,
      () => _reconcileInsideKey(groupId),
    );
  }

  Future<void> _reconcileInsideKey(String groupId) async {
    final conversationKey = 'group:$groupId';
    for (var attempt = 0; attempt < maxGenerationAttempts; attempt++) {
      final metadata = await _generationCancellation
          .lookupConversationNotificationContentMetadata(conversationKey);
      // No managed generation means there is no exact card this job can own.
      if (metadata == null) return;
      final generation = metadata.generation?.trim();
      if (generation == null || generation.isEmpty) return;

      final decision = await _isCurrentContentCanonical(groupId, metadata);
      if (decision == GroupNotificationCanonicalContentDecision.unknown) {
        throw const GroupNotificationCanonicalReconciliationRetryable();
      }

      final replacement = await _loadReplacement(groupId, metadata);
      // A reconciliation job also repairs an ambiguous prior native show. Even
      // when the recorded content is canonical, silently re-publish it under
      // the exact generation CAS; stable-id replacement is idempotent and the
      // retained outbox is the only durable proof that the show still needs a
      // confirmed retry. A missing descriptor cannot justify cancelling
      // content that canonical state explicitly told us to keep.
      if (decision == GroupNotificationCanonicalContentDecision.keep &&
          replacement == null) {
        throw const GroupNotificationCanonicalReconciliationRetryable();
      }
      // Plan 372 TC-07 classifies this delivered-card generation CAS as an
      // approved N11 compatibility path. It neither mints an authenticated
      // event correlation nor reopens a SETTLED/OS_POSTED ledger record.
      final mutated = replacement == null
          ? await _generationCancellation
                .cancelConversationNotificationGeneration(
                  conversationKey,
                  generation,
                )
          : await _generationReplacement
                .replaceConversationNotificationGeneration(
                  conversationKey,
                  generation,
                  replacement,
                );
      if (mutated) return;
      // A different isolate won between snapshot and mutation. Re-read and
      // accept it only if that exact replacement is canonical now.
    }
    throw const GroupNotificationCanonicalReconciliationRetryable();
  }
}
