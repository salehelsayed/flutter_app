import 'package:flutter_app/features/push/application/group_notification_display_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const allowed = GroupNotificationDisplayPolicyInput(
    groupExists: true,
    hasCurrentLocalMembership: true,
    groupType: 'chat',
  );

  group('canonical group notification display policy', () {
    test('allows only current chat and announcement memberships', () {
      expect(
        evaluateGroupNotificationDisplayPolicy(allowed).shouldDisplay,
        isTrue,
      );
      expect(
        evaluateGroupNotificationDisplayPolicy(
          allowed.copyWith(groupType: 'announcement'),
        ).shouldDisplay,
        isTrue,
      );
    });

    for (final scenario
        in <
          ({
            String name,
            GroupNotificationDisplayPolicyInput input,
            String reason,
          })
        >[
          (
            name: 'missing group',
            input: allowed.copyWith(groupExists: false),
            reason: 'group_missing',
          ),
          (
            name: 'missing current membership',
            input: allowed.copyWith(hasCurrentLocalMembership: false),
            reason: 'local_member_missing',
          ),
          (
            name: 'QA group',
            input: allowed.copyWith(groupType: 'qa'),
            reason: 'unsupported_group_type',
          ),
          (
            name: 'missing group type',
            input: allowed.copyWith(clearGroupType: true),
            reason: 'unsupported_group_type',
          ),
          (
            name: 'unknown group type',
            input: allowed.copyWith(groupType: 'future_type'),
            reason: 'unsupported_group_type',
          ),
          (
            name: 'muted group',
            input: allowed.copyWith(isMuted: true),
            reason: 'muted',
          ),
          (
            name: 'archived group',
            input: allowed.copyWith(isArchived: true),
            reason: 'archived',
          ),
          (
            name: 'dissolved flag',
            input: allowed.copyWith(isDissolved: true),
            reason: 'dissolved',
          ),
          (
            name: 'dissolved timestamp',
            input: allowed.copyWith(hasDissolvedAt: true),
            reason: 'dissolved',
          ),
          (
            name: 'self-removal timestamp',
            input: allowed.copyWith(hasSelfRemovedAt: true),
            reason: 'self_removed',
          ),
        ]) {
      test('suppresses ${scenario.name}', () {
        final decision = evaluateGroupNotificationDisplayPolicy(scenario.input);

        expect(decision.shouldDisplay, isFalse);
        expect(decision.reason, scenario.reason);
      });
    }

    test('fails closed before considering device-local preferences', () {
      final decision = evaluateGroupNotificationDisplayPolicy(
        allowed.copyWith(
          groupExists: false,
          hasCurrentLocalMembership: false,
          groupType: 'qa',
          isMuted: true,
          isArchived: true,
          isDissolved: true,
          hasDissolvedAt: true,
          hasSelfRemovedAt: true,
        ),
      );

      expect(decision.shouldDisplay, isFalse);
      expect(decision.reason, 'group_missing');
    });

    test('reaction display requires a current local ordinary target', () {
      final allowedReaction = evaluateGroupReactionNotificationDisplayPolicy(
        const GroupReactionNotificationDisplayPolicyInput(
          group: allowed,
          hasCurrentLocalAuthoredTarget: true,
          targetRequiresRedaction: false,
        ),
      );
      expect(allowedReaction.shouldDisplay, isTrue);

      final nonLocalTarget = evaluateGroupReactionNotificationDisplayPolicy(
        const GroupReactionNotificationDisplayPolicyInput(
          group: allowed,
          hasCurrentLocalAuthoredTarget: false,
          targetRequiresRedaction: false,
        ),
      );
      expect(nonLocalTarget.shouldDisplay, isFalse);
      expect(nonLocalTarget.reason, 'reaction_target_not_local_authored');

      final privateTarget = evaluateGroupReactionNotificationDisplayPolicy(
        const GroupReactionNotificationDisplayPolicyInput(
          group: allowed,
          hasCurrentLocalAuthoredTarget: true,
          targetRequiresRedaction: true,
        ),
      );
      expect(privateTarget.shouldDisplay, isFalse);
      expect(privateTarget.reason, 'reaction_target_private_media');
    });

    test('reaction display inherits every canonical group suppression', () {
      for (final groupInput in <GroupNotificationDisplayPolicyInput>[
        allowed.copyWith(hasCurrentLocalMembership: false),
        allowed.copyWith(groupType: 'qa'),
        allowed.copyWith(isMuted: true),
        allowed.copyWith(isArchived: true),
        allowed.copyWith(isDissolved: true),
        allowed.copyWith(hasDissolvedAt: true),
        allowed.copyWith(hasSelfRemovedAt: true),
      ]) {
        expect(
          evaluateGroupReactionNotificationDisplayPolicy(
            GroupReactionNotificationDisplayPolicyInput(
              group: groupInput,
              hasCurrentLocalAuthoredTarget: true,
              targetRequiresRedaction: false,
            ),
          ).shouldDisplay,
          isFalse,
        );
      }
    });
  });
}
