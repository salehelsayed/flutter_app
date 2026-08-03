import 'package:flutter_app/core/notifications/group_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'invalid reaction card is atomically rebuilt from latest unread message',
    () async {
      final mutation = _FakeGenerationMutation(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'reaction-add',
          generation: 'reaction-generation',
        ),
      );
      final reconciler = GroupNotificationCanonicalReconciler(
        coordinator: GroupNotificationPresentationCoordinator(),
        generationCancellation: mutation,
        generationReplacement: mutation,
        isCurrentContentCanonical: (_, metadata) async =>
            metadata.eventIdentity != 'reaction-add'
            ? GroupNotificationCanonicalContentDecision.keep
            : GroupNotificationCanonicalContentDecision.retire,
        loadReplacement: (_, _) async =>
            const CanonicalConversationNotificationReplacement(
              senderUsername: 'Family',
              messageText: 'Alice: Photo',
              routePayload: 'mknoon-route-v1:group-a',
              contentKind: ConversationNotificationContentKind.message,
              eventIdentity: 'older-unread-message',
            ),
      );

      await reconciler.reconcile('group-a');

      expect(mutation.cancelledGenerations, isEmpty);
      expect(mutation.replacements, hasLength(1));
      expect(
        mutation.replacements.single.expectedGeneration,
        'reaction-generation',
      );
      expect(
        mutation.replacements.single.replacement.eventIdentity,
        'older-unread-message',
      );
    },
  );

  test(
    'invalid card with no remaining attention is cancelled exactly',
    () async {
      final mutation = _FakeGenerationMutation(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'deleted-message',
          generation: 'deleted-generation',
        ),
      );
      final reconciler = GroupNotificationCanonicalReconciler(
        coordinator: GroupNotificationPresentationCoordinator(),
        generationCancellation: mutation,
        generationReplacement: mutation,
        isCurrentContentCanonical: (_, _) async =>
            GroupNotificationCanonicalContentDecision.retire,
        loadReplacement: (_, _) async => null,
      );

      await reconciler.reconcile('group-a');

      expect(mutation.cancelledGenerations, <String>['deleted-generation']);
      expect(mutation.replacements, isEmpty);
    },
  );

  test(
    'a still-canonical generation is silently republished before custody clears',
    () async {
      final mutation = _FakeGenerationMutation(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'new-message',
          generation: 'new-generation',
        ),
      );
      final reconciler = GroupNotificationCanonicalReconciler(
        coordinator: GroupNotificationPresentationCoordinator(),
        generationCancellation: mutation,
        generationReplacement: mutation,
        isCurrentContentCanonical: (_, metadata) async =>
            metadata.eventIdentity == 'new-message'
            ? GroupNotificationCanonicalContentDecision.keep
            : GroupNotificationCanonicalContentDecision.retire,
        loadReplacement: (_, _) async =>
            const CanonicalConversationNotificationReplacement(
              senderUsername: 'Family',
              messageText: 'Alice: current',
              routePayload: 'mknoon-route-v1:group-a',
              contentKind: ConversationNotificationContentKind.message,
              eventIdentity: 'new-message',
            ),
      );

      await reconciler.reconcile('group-a');

      expect(mutation.cancelledGenerations, isEmpty);
      expect(mutation.replacements, hasLength(1));
      expect(mutation.replacements.single.expectedGeneration, 'new-generation');
    },
  );

  test(
    'replacement losing generation CAS rechecks and republishes newer card',
    () async {
      final mutation =
          _FakeGenerationMutation(
              const ConversationNotificationContentMetadata(
                kind: ConversationNotificationContentKind.reaction,
                eventIdentity: 'removed-reaction',
                generation: 'old-generation',
              ),
            )
            ..replaceRaceWinner = const ConversationNotificationContentMetadata(
              kind: ConversationNotificationContentKind.message,
              eventIdentity: 'new-message',
              generation: 'new-generation',
            );
      var replacementLoads = 0;
      final reconciler = GroupNotificationCanonicalReconciler(
        coordinator: GroupNotificationPresentationCoordinator(),
        generationCancellation: mutation,
        generationReplacement: mutation,
        isCurrentContentCanonical: (_, metadata) async =>
            metadata.eventIdentity == 'new-message'
            ? GroupNotificationCanonicalContentDecision.keep
            : GroupNotificationCanonicalContentDecision.retire,
        loadReplacement: (_, _) async {
          replacementLoads++;
          return CanonicalConversationNotificationReplacement(
            senderUsername: 'Family',
            messageText: replacementLoads == 1 ? 'Alice: older' : 'Alice: new',
            routePayload: 'mknoon-route-v1:group-a',
            contentKind: ConversationNotificationContentKind.message,
            eventIdentity: replacementLoads == 1
                ? 'older-message'
                : 'new-message',
          );
        },
      );

      await reconciler.reconcile('group-a');

      expect(mutation.replacements, hasLength(2));
      expect(mutation.metadata?.eventIdentity, 'new-message');
      expect(mutation.cancelledGenerations, isEmpty);
    },
  );

  test(
    'repeated generation churn remains retryable instead of blind cancelling',
    () async {
      final mutation = _AlwaysLosingGenerationMutation();
      final reconciler = GroupNotificationCanonicalReconciler(
        coordinator: GroupNotificationPresentationCoordinator(),
        generationCancellation: mutation,
        generationReplacement: mutation,
        isCurrentContentCanonical: (_, _) async =>
            GroupNotificationCanonicalContentDecision.retire,
        loadReplacement: (_, _) async =>
            const CanonicalConversationNotificationReplacement(
              senderUsername: 'Family',
              messageText: 'Alice: older',
              routePayload: 'mknoon-route-v1:group-a',
              contentKind: ConversationNotificationContentKind.message,
              eventIdentity: 'older-message',
            ),
        maxGenerationAttempts: 2,
      );

      await expectLater(
        reconciler.reconcile('group-a'),
        throwsA(isA<GroupNotificationCanonicalReconciliationRetryable>()),
      );
      expect(mutation.replaceAttempts, 2);
    },
  );

  test(
    'unknown current content retains custody without cancel or replacement',
    () async {
      final mutation = _FakeGenerationMutation(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: 'push-before-inbox',
          generation: 'current-generation',
        ),
      );
      var replacementLoads = 0;
      final reconciler = GroupNotificationCanonicalReconciler(
        coordinator: GroupNotificationPresentationCoordinator(),
        generationCancellation: mutation,
        generationReplacement: mutation,
        isCurrentContentCanonical: (_, _) async =>
            GroupNotificationCanonicalContentDecision.unknown,
        loadReplacement: (_, _) async {
          replacementLoads++;
          return null;
        },
      );

      await expectLater(
        reconciler.reconcile('group-a'),
        throwsA(isA<GroupNotificationCanonicalReconciliationRetryable>()),
      );

      expect(replacementLoads, 0);
      expect(mutation.cancelledGenerations, isEmpty);
      expect(mutation.replacements, isEmpty);
      expect(mutation.metadata?.generation, 'current-generation');
    },
  );

  test(
    'native replacement throw is repaired by a canonical silent retry',
    () async {
      final mutation = _FakeGenerationMutation(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'removed-reaction',
          generation: 'old-generation',
        ),
      )..replaceErrorsAfterMetadata.add(StateError('native show failed'));
      const replacement = CanonicalConversationNotificationReplacement(
        senderUsername: 'Family',
        messageText: 'Alice: fallback',
        routePayload: 'mknoon-route-v1:group-a',
        contentKind: ConversationNotificationContentKind.message,
        eventIdentity: 'fallback-message',
      );
      final reconciler = GroupNotificationCanonicalReconciler(
        coordinator: GroupNotificationPresentationCoordinator(),
        generationCancellation: mutation,
        generationReplacement: mutation,
        isCurrentContentCanonical: (_, metadata) async =>
            metadata.eventIdentity == replacement.eventIdentity
            ? GroupNotificationCanonicalContentDecision.keep
            : GroupNotificationCanonicalContentDecision.retire,
        loadReplacement: (_, _) async => replacement,
      );

      await expectLater(reconciler.reconcile('group-a'), throwsStateError);
      expect(mutation.metadata?.eventIdentity, 'fallback-message');

      await reconciler.reconcile('group-a');

      expect(mutation.replacements, hasLength(2));
      expect(
        mutation.replacements.map((attempt) => attempt.replacement),
        everyElement(replacement),
      );
      expect(mutation.metadata?.eventIdentity, 'fallback-message');
    },
  );
}

final class _ReplacementAttempt {
  const _ReplacementAttempt(this.expectedGeneration, this.replacement);

  final String expectedGeneration;
  final CanonicalConversationNotificationReplacement replacement;
}

class _FakeGenerationMutation
    implements
        ConversationNotificationGenerationCancellation,
        ConversationNotificationGenerationReplacement {
  _FakeGenerationMutation(this.metadata);

  ConversationNotificationContentMetadata? metadata;
  ConversationNotificationContentMetadata? replaceRaceWinner;
  final List<Object> replaceErrorsAfterMetadata = <Object>[];
  final List<String> cancelledGenerations = <String>[];
  final List<_ReplacementAttempt> replacements = <_ReplacementAttempt>[];

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async =>
      metadata;

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async {
    if (metadata?.generation != generation) return false;
    cancelledGenerations.add(generation);
    metadata = null;
    return true;
  }

  @override
  Future<bool> replaceConversationNotificationGeneration(
    String conversationKey,
    String expectedGeneration,
    CanonicalConversationNotificationReplacement replacement,
  ) async {
    replacements.add(_ReplacementAttempt(expectedGeneration, replacement));
    final winner = replaceRaceWinner;
    if (winner != null) {
      replaceRaceWinner = null;
      metadata = winner;
      return false;
    }
    if (metadata?.generation != expectedGeneration) return false;
    metadata = ConversationNotificationContentMetadata(
      kind: replacement.contentKind,
      eventIdentity: replacement.eventIdentity,
      generation: 'replacement-generation',
    );
    if (replaceErrorsAfterMetadata.isNotEmpty) {
      throw replaceErrorsAfterMetadata.removeAt(0);
    }
    return true;
  }
}

final class _AlwaysLosingGenerationMutation extends _FakeGenerationMutation {
  _AlwaysLosingGenerationMutation()
    : super(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'invalid-0',
          generation: 'generation-0',
        ),
      );

  int replaceAttempts = 0;

  @override
  Future<bool> replaceConversationNotificationGeneration(
    String conversationKey,
    String expectedGeneration,
    CanonicalConversationNotificationReplacement replacement,
  ) async {
    replaceAttempts += 1;
    metadata = ConversationNotificationContentMetadata(
      kind: ConversationNotificationContentKind.reaction,
      eventIdentity: 'invalid-$replaceAttempts',
      generation: 'generation-$replaceAttempts',
    );
    return false;
  }
}
